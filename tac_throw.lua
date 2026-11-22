-- Thrown things (glowsticks, flashbangs, smoke grenades, a thrown C4): static bodies the host moves itself - gravity,
-- a raycast per step, a bounce, then at rest (a .vox at scale 0.5 is static, and these need 0.05 m voxels). And what the
-- clients draw: the glows, the smoke clouds, the flash.

TAC_THROW_SPEED, TAC_THROW_UP = 13, 2.5          -- m/s along the look, and upward
TAC_BOUNCE, TAC_REST_SPEED = 0.32, 0.9
TAC_GLOW_LIFE, TAC_GLOW_MAX = 180, 10            -- s a glowstick glows; at most this many per player (the oldest goes)
TAC_FLASH_FUSE, TAC_FLASH_RANGE = 1.8, 15
TAC_SMOKE_FUSE, TAC_SMOKE_LIFE = 1.5, 25
TAC_THROW_COOLDOWN = 0.6

-- (the world models' pivots, from tools/make_tactical.py: the height of the pivot over what it rests on, and whether
--  it lies on its side; a stuck C4's flat bottom is 0.10 m under its pivot)
TAC_REST = {glowstick = {lift = 0.03, lie = true}, flashbang = {lift = 0.175}, smoke = {lift = 0.2}, c4 = {lift = 0.10}}
TacProj = {}                                     -- (host) flying: {body, pos, vel, spin, rot, stick, owner, onRest(pos, normal, shape)}
local throwReady = {}                            -- player -> time the next throw may go
local glows = {}                                 -- (host) lit glowsticks: {body, owner, t0}
local coverAt = 0                                -- (host) next re-send of the smoke clouds to the villagers
local fuses = {}                                 -- (host) {t, kind, body}

-- (host) launch body from player p's hand along the look
function TacThrow(p, body, stick, onRest, kind)
	local e, fwd = TacEye(p)
	local right = TransformToParentVec(e, Vec(1, 0, 0))
	local pos = VecAdd(VecAdd(e.pos, VecScale(fwd, 0.45)), VecAdd(VecScale(right, 0.18), Vec(0, -0.1, 0)))
	local vel = VecAdd(VecScale(fwd, TAC_THROW_SPEED), Vec(0, TAC_THROW_UP, 0))
	vel = VecAdd(vel, GetPlayerVelocity(p))
	local pr = {body = body, pos = pos, vel = vel, rot = e.rot, spin = QuatEuler(math.random(-400, 400), math.random(-300, 300), 0),
		stick = stick, owner = p, onRest = onRest, t0 = GetTime(), rest = false, fit = TAC_REST[kind or ""] or {lift = 0.05}}
	SetBodyTransform(body, Transform(pos, e.rot))
	TacProj[#TacProj + 1] = pr
	TacEvent("throw", pos)
	return pr
end

local function restOn(pr, pos, n, sh)
	pr.rest = true
	n = n or Vec(0, 1, 0)                                            -- (a hit without a normal: lie flat)
	local yaw = QuatEuler(0, math.random(0, 359), 0)
	local rot = pr.stick and TacOnSurface(n, pr.vel) or QuatRotateQuat(TacOnSurface(n), yaw)
	if pr.fit.lie then rot = QuatRotateQuat(rot, QuatEuler(90, 0, 0)) end
	local at = VecAdd(pos, VecScale(n, pr.fit.lift))
	SetBodyTransform(pr.body, Transform(at, rot))
	if pr.onRest then pr.onRest(at, n, sh, rot) end
end

-- (host) every update: move what flies
function TacProjTick(dt)
	local i = 1
	while i <= #TacProj do
		local pr = TacProj[i]
		if pr.rest or not IsHandleValid(pr.body) or GetTime() - pr.t0 > 20 then
			table.remove(TacProj, i)
		else
			local left = dt
			for _ = 1, 3 do                                          -- (a bounce may use part of the step)
				if left <= 0 or pr.rest then break end
				pr.vel = VecAdd(pr.vel, Vec(0, -9.81 * left, 0))
				local step = VecScale(pr.vel, left)
				local len = VecLength(step)
				if len < 1e-4 then break end
				local dir = VecScale(step, 1 / len)
				QueryRejectBody(pr.body)
				QueryRejectPlayer(pr.owner)
				QueryRequire("physical")
				local hit, d, n, sh = QueryRaycast(pr.pos, dir, len + 0.04, 0.03)
				if hit then
					local at = VecAdd(pr.pos, VecScale(dir, math.max(0, d - 0.03)))
					if pr.stick then
						restOn(pr, at, n, sh)
					else
						local vn = VecDot(pr.vel, n)
						pr.vel = VecScale(VecSub(pr.vel, VecScale(n, 2 * vn)), TAC_BOUNCE)
						pr.pos = at
						left = left * (1 - d / (len + 0.04))
						if VecLength(pr.vel) < TAC_REST_SPEED and n[2] > 0.5 then restOn(pr, at, n, sh) end
						if math.abs(vn) > 2 then TacEvent("clink", at) end
					end
				else
					pr.pos = VecAdd(pr.pos, step)
					left = 0
				end
			end
			if not pr.rest then
				pr.rot = QuatRotateQuat(pr.rot, QuatSlerp(Quat(), pr.spin, dt))
				SetBodyTransform(pr.body, Transform(pr.pos, pr.rot))
			end
			i = i + 1
		end
	end
end

-- the published state for the clients (shared.tac: this script's own)
local function publishGlows()
	local out = {}
	for _, g in ipairs(glows) do out[#out + 1] = {b = g.body, t0 = g.t0} end
	shared.tac.glow = out
end

function TacThrowInit()
	shared.tac = shared.tac or {}
	shared.tac.glow = {}
	shared.tac.smoke = {}
end

-- (host) every tick: the three throwables' clicks, fuses, glowsticks burning out
function TacThrowTick(dt)
	local now = GetTime()
	for _, p in ipairs(GetAllPlayers()) do
		for _, id in ipairs({"tac_glowstick", "tac_flashbang", "tac_smoke"}) do
			if TacClicked(p, id) then TacThrowAction(p, id) end
		end
	end
	TacFuseTick(now)
end

-- (host) what a click of a throwable does (tests call it directly)
function TacThrowAction(p, id)
	local now = GetTime()
	if TacHasAmmo(p, id) and now >= (throwReady[p] or 0) then
				throwReady[p] = now + TAC_THROW_COOLDOWN
				local name = string.sub(id, 5)
				local body = TacSpawnWorld(name, Transform(TacEye(p).pos))
				if body then
					TacSpend(p, id)
					TacThrow(p, body, false, nil, name)
					if id == "tac_glowstick" then
						local mine = {}
						for k, g in ipairs(glows) do if g.owner == p then mine[#mine + 1] = k end end
						if #mine >= TAC_GLOW_MAX then
							local old = table.remove(glows, mine[1])
							if IsHandleValid(old.body) then Delete(old.body) end
						end
						glows[#glows + 1] = {body = body, owner = p, t0 = now}
						publishGlows()
						TacEvent("crack", TacEye(p).pos)
					else
						fuses[#fuses + 1] = {t = now + (id == "tac_flashbang" and TAC_FLASH_FUSE or TAC_SMOKE_FUSE), kind = name, body = body, owner = p}
						TacEvent("pin", TacEye(p).pos)
					end
				end
	end
end

function TacFuseTick(now)
	local i = 1
	while i <= #fuses do
		local f = fuses[i]
		if now < f.t and TacBroken(f.body) then f.t, f.broken = now, true end   -- (shot / hit: it goes off now)
		if now >= f.t then
			table.remove(fuses, i)
			if IsHandleValid(f.body) then
				local pos = GetBodyTransform(f.body).pos
				if f.kind == "flashbang" then
					TacEvent("flash", pos)
					TacVillagersFlash(pos, TAC_FLASH_RANGE, 1)                       -- (villagers: who sees it is blinded)
					Delete(f.body)
				else
					local s = shared.tac.smoke
					local keep = {}
					for _, c in ipairs(s) do
						if now - c.t0 < (c.dur or TAC_SMOKE_LIFE) + 30 then keep[#keep + 1] = c
						elseif IsHandleValid(c.b) then Delete(c.b) end          -- (a spent canister: gone with its entry)
					end
					local b = f.body
					if f.broken then Delete(f.body) b = TacNewKey() end         -- (shot: the canister is gone, the cloud comes)
					keep[#keep + 1] = {b = b, t0 = now, x = pos[1], y = pos[2], z = pos[3]}
					shared.tac.smoke = keep
					TacEvent("smoke", pos)
				end
			end
		else
			i = i + 1
		end
	end
	-- spent glowsticks and smoke canisters lie there a while, then go
	local changed = false
	i = 1
	while i <= #glows do
		local g = glows[i]
		local broken = TacBroken(g.body)
		if now - g.t0 > TAC_GLOW_LIFE + 60 or not IsHandleValid(g.body) or broken then
			if broken then TacEvent("glowbreak", GetBodyTransform(g.body).pos) end
			if IsHandleValid(g.body) then Delete(g.body) end
			table.remove(glows, i)
			changed = true
		else
			i = i + 1
		end
	end
	if changed then publishGlows() end
	if now >= coverAt then                                           -- (villagers can't see through the clouds)
		coverAt = now + 1
		for _, c in ipairs(shared.tac.smoke) do
			local age, dur = now - c.t0, c.dur or TAC_SMOKE_LIFE
			if age < dur + 6 then
				local r = c.burst and TAC_SMOKE_R or math.min(TAC_SMOKE_R, 0.8 + age * 1.1)
				TacVillagersCover(c.b, Vec(c.x, c.y + r * 0.4, c.z), r, c.t0 + dur + 8)
			end
		end
	end
	local s = shared.tac.smoke
	local hit = false
	for _, c in ipairs(s) do if TacBroken(c.b) then hit = true end end
	if hit then
		local keep = {}
		for _, c in ipairs(s) do
			if TacBroken(c.b) then
				local pos = GetBodyTransform(c.b).pos
				Delete(c.b)
				if now - c.t0 < (c.dur or TAC_SMOKE_LIFE) then              -- (still smoking: punctured, it all comes out now)
					keep[#keep + 1] = {b = TacNewKey(), t0 = now, x = pos[1], y = pos[2], z = pos[3], dur = 3, burst = true}
					TacEvent("puncture", pos)
				end
			else
				keep[#keep + 1] = c
			end
		end
		shared.tac.smoke = keep
		s = keep
	end
	if #s > 0 and now - s[1].t0 > (s[1].dur or TAC_SMOKE_LIFE) + 30 then
		if IsHandleValid(s[1].b) then Delete(s[1].b) end
		local keep = {}
		for k = 2, #s do keep[#keep + 1] = s[k] end
		shared.tac.smoke = keep
	end
end

------------------------------------------------------------------------------------------------------------ client

local flash = {t0 = -100, dur = 0, s = 0}        -- my white-out
local seenSweep = {}                             -- local player -> next sweep (per machine)
local hiss = {}                                  -- smoke body -> playing

-- (client) a flashbang went off at pos: how hard it hits me (distance, a clear line, which way I look)
function TacFlashHit(pos)
	local me = GetLocalPlayer()
	if GetPlayerHealth(me) <= 0 then return 0 end
	local eye = GetPlayerEyeTransform(me)
	local to = VecSub(pos, eye.pos)
	local d = VecLength(to)
	if d > TAC_FLASH_RANGE then return 0 end
	local dir = VecScale(to, 1 / math.max(d, 0.01))
	-- hidden only if a wall is in the way: the line to the grenade AND the line to a point above it both blocked (a
	-- grenade lying behind a kerb, a glowstick or a bit of rubble still blinds)
	local blocked = false
	if d > 0.3 then
		QueryRejectPlayer(me)
		QueryRequire("physical")
		if QueryRaycast(eye.pos, dir, d - 0.25) then
			local up = VecSub(VecAdd(pos, Vec(0, 0.6, 0)), eye.pos)
			local du = VecLength(up)
			QueryRejectPlayer(me)
			QueryRequire("physical")
			blocked = QueryRaycast(eye.pos, VecScale(up, 1 / du), du - 0.1)
		end
	end
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	TacFlashLast = {d = d, blocked = blocked, dot = VecDot(fwd, dir)}          -- (tests: why a flash did or did not blind)
	if blocked then return 0 end
	local facing = 0.25 + 0.75 * math.max(0, VecDot(fwd, dir))
	local s = facing * (1 - d / TAC_FLASH_RANGE) ^ 0.6
	if TacNvgOn and TacNvgOn() then s = math.min(1, s * 1.5) end
	return s
end

function TacThrowEvent(kind, pos, v)
	if kind == "throw" then
		PlaySound(TacSound("throw", "throw/m" .. math.random(0, 4) .. ".ogg"), pos, 0.6)
	elseif kind == "clink" then
		PlaySound(TacSound("clink", "metal/hit-s0.ogg"), pos, 0.5, true, 0.9 + 0.3 * math.random())
	elseif kind == "pin" then
		PlaySound(TacSound("pin", "clickup.ogg"), pos, 0.7, false, 1.4)
	elseif kind == "crack" then
		PlaySound(TacSound("crack", "clickdown.ogg"), pos, 0.7, false, 0.7)
	elseif kind == "flash" then
		PlaySound(TacSound("bang", "explosion/m2.ogg"), pos, 0.96)          -- (40% down from 1.6: the user found it too loud)
		local s = TacFlashHit(pos)
		if s > 0.05 then
			flash = {t0 = GetTime(), dur = 0.6 + 3.4 * s, s = s}
			PlaySound(TacSound("ring", "MOD/snd/tac_ring.ogg"), GetPlayerEyeTransform(GetLocalPlayer()).pos, 0.6 * (0.4 + 0.6 * s), false)
		end
		flash.light = {pos = pos, t0 = GetTime()}
	elseif kind == "smoke" then
		PlaySound(TacSound("pop", "clickdown.ogg"), pos, 0.8, false, 0.5)
	elseif kind == "glowbreak" then                                  -- (shot: a crack and a green splash)
		PlaySound(TacSound("glassbreak", "glass/break-s0.ogg"), pos, 0.6, true, 1.4)
		for _ = 1, 14 do
			ParticleReset()
			ParticleColor(0.35, 1, 0.4)
			ParticleRadius(0.04, 0.01)
			ParticleAlpha(1, 0)
			ParticleGravity(-6)
			ParticleEmissive(4, 0)
			ParticleCollide(1)
			SpawnParticle(VecAdd(pos, Vec(0, 0.05, 0)), Vec((math.random() - 0.5) * 3, 1 + math.random() * 2, (math.random() - 0.5) * 3), 1.2)
		end
	elseif kind == "puncture" then                                   -- (a smoke canister shot open)
		PlaySound(TacSound("pop", "clickdown.ogg"), pos, 1.0, true, 0.4)
	end
end

TAC_SMOKE_R = 4.5                                -- m: the cloud's half width when full
TAC_SMOKE_BUDGET = 1600                          -- smoke particles alive on one machine at most (all clouds together)
TAC_SMOKE_ALIVE = 700                            -- about how many one full cloud keeps alive
local smokeEmit = {}                             -- smoke body -> particles owed (jet, fill): this machine's own

-- one smoke particle's look: big, grey, opaque most of its life, fading late
local function smokePuff(r0, r1)
	ParticleReset()
	ParticleType("smoke")
	local grey = 0.6 + 0.12 * math.random()
	ParticleColor(grey, grey, grey * 1.02)
	ParticleRadius(r0 + 0.4 * math.random(), r1 + 1.4 * math.random())
	ParticleAlpha(0.95, 0.0, "easein")
	ParticleGravity(0.04 + 0.08 * math.random())
	ParticleDrag(0.7)
	ParticleCollide(1)
end

-- (client) every frame: glow lights, smoke particles, the flash's light
function TacThrowClientTick(dt)
	local now = GetTime()
	local sw = seenSweep[GetLocalPlayer()] or 0
	if now >= sw then                                                -- (forget what is gone: a handle may come back)
		seenSweep[GetLocalPlayer()] = now + 1
		local t, me, keep = shared.tac or {}, GetLocalPlayer(), {}
		local mine = TAC_SEEN[me] or {}
		for _, list in ipairs({t.glow or {}, t.smoke or {}, t.clay or {}}) do
			for _, e in ipairs(list) do if e.b and mine[e.b] then keep[e.b] = mine[e.b] end end
		end
		TAC_SEEN[me] = keep
	end
	for _, g in ipairs((shared.tac and shared.tac.glow) or {}) do
		local age = now - TacSeen(g.b, now)
		if age < TAC_GLOW_LIFE and IsHandleValid(g.b) then
			local k = age > TAC_GLOW_LIFE - 20 and (TAC_GLOW_LIFE - age) / 20 or 1
			local t = GetBodyTransform(g.b)
			PointLight(TransformToParentPoint(t, Vec(0.025, -0.05, -0.025)), 0.25, 1.0, 0.35, 1.6 * k)
		end
	end
	-- many clouds: ones close together share the density (they fill the same air), and all together stay under
	-- TAC_SMOKE_BUDGET on this machine; a cloud far from my camera makes half as many
	local clouds = {}
	for _, c in ipairs((shared.tac and shared.tac.smoke) or {}) do
		if now - TacSeen(c.b, now) < (c.dur or TAC_SMOKE_LIFE) then clouds[#clouds + 1] = c end
	end
	local camPos = GetCameraTransform().pos
	local want, share = 0, {}                                       -- (this machine's own: shared.tac is read-only here)
	for _, c in ipairs(clouds) do
		local near = 0
		for _, o in ipairs(clouds) do
			local dx, dz = o.x - c.x, o.z - c.z
			if dx * dx + dz * dz < 36 then near = near + 1 end                -- (itself too: 1 when alone)
		end
		local sh = 1 / math.max(1, near) ^ 0.75
		local dx, dy, dz = camPos[1] - c.x, camPos[2] - c.y, camPos[3] - c.z
		if dx * dx + dy * dy + dz * dz > 50 * 50 then sh = sh * 0.5 end
		share[c.b] = sh
		want = want + sh * TAC_SMOKE_ALIVE
	end
	local cap = want > TAC_SMOKE_BUDGET and TAC_SMOKE_BUDGET / want or 1
	TacSmokeLoad = want * cap                                         -- (tests: particles this machine aims to keep alive)
	for _, c in ipairs((shared.tac and shared.tac.smoke) or {}) do
		local age = now - TacSeen(c.b, now)
		local at = IsHandleValid(c.b) and TransformToParentPoint(GetBodyTransform(c.b), Vec(0, 0.2, 0)) or Vec(c.x, c.y, c.z)
		if age < (c.dur or TAC_SMOKE_LIFE) then
			if not hiss[c.b] then hiss[c.b] = true end
			PlayLoop(TacLoop("hiss", "tools/spray-loop.ogg"), at, 0.5)
			-- a thick wall of smoke. Two emitters: the jet out of the canister (the billow you see come out of it), and a
			-- fill that puts slow particles at random points in a dome growing to TAC_SMOKE_R round it - the cloud fills
			-- evenly instead of thinning out from one point. (What is owed is kept in this machine's own table: the first
			-- version kept it in shared.tac - read-only here - so after 4 s, at 60 fps, nothing came out at all.)
			local e = smokeEmit[c.b] or {jet = 0, fill = 0}
			smokeEmit[c.b] = e
			local burst = age < 3 or c.burst
			local k = (share[c.b] or 1) * cap * (c.burst and 2.5 or 1)      -- (punctured: it all comes out at once)
			e.jet = e.jet + (burst and 45 or 18) * k * dt
			e.fill = e.fill + (burst and 65 or 37) * k * dt
			local R = math.min(TAC_SMOKE_R, 0.8 + age * 1.1)
			while e.jet >= 1 do
				e.jet = e.jet - 1
				smokePuff(0.35, 1.6)
				local v = Vec((math.random() - 0.5) * 6, 1.0 + math.random() * 2.2, (math.random() - 0.5) * 6)
				SpawnParticle(at, v, 9 + 4 * math.random())
			end
			while e.fill >= 1 do
				e.fill = e.fill - 1
				smokePuff(1.0, 2.6)
				local u = Vec(math.random() * 2 - 1, math.random() * 0.8, math.random() * 2 - 1)    -- (a squat dome)
				if VecLength(u) > 1 then u = VecNormalize(u) end
				local p = VecAdd(at, VecScale(u, R))
				local len = VecLength(u) * R
				if len > 0.3 then                                         -- (kept on this side of walls: smoke fills the room it is in)
					local dir = VecScale(u, R / len)
					QueryRequire("physical")
					local hit, d = QueryRaycast(at, dir, len)
					if hit then p = VecAdd(at, VecScale(dir, math.max(0, d - 0.4))) end
				end
				SpawnParticle(p, Vec((math.random() - 0.5) * 0.6, 0.15 + 0.25 * math.random(), (math.random() - 0.5) * 0.6), 10 + 5 * math.random())
			end
		else
			smokeEmit[c.b] = nil
		end
	end
	if flash.light and now - flash.light.t0 < 0.25 then
		PointLight(flash.light.pos, 1, 1, 1, 60 * (1 - (now - flash.light.t0) / 0.25))
	end
end

-- (client draw) the white-out
function TacThrowDraw()
	local age = GetTime() - flash.t0
	if age < flash.dur then
		local a = age < flash.dur * 0.5 and 1 or 1 - (age - flash.dur * 0.5) / (flash.dur * 0.5)
		UiPush()
		UiColor(1, 1, 1, math.min(1, a * (0.6 + 0.4 * flash.s) * 1.05))
		UiRect(UiWidth(), UiHeight())
		UiPop()
	end
end

-- (tests) how hard the last flash hit me, and when
function TacFlashState() return flash.s or 0, flash.t0 end
