-- Placed things: C4 (stick or throw, then detonate: the user, "first click to place/throw C4, second click to blow it
-- up"), the claymore (a cone in front, owner safe) and the wire trap (charge, then the hook: crossing the wire fires it).
-- The host decides; shared.tac.c4 / .clay / .wire tell the clients what to draw.

TAC_C4_REACH, TAC_C4_SIZE, TAC_C4_ORPHAN = 3.0, 2.5, 120   -- m to stick it; explosion size; s it waits for an owner
TAC_CLAY_ARM, TAC_CLAY_RANGE, TAC_CLAY_HALF = 2.5, 4.0, 35 -- s to arm; m; half the cone's angle (degrees)
TAC_CLAY_PELLETS, TAC_CLAY_SIZE = 12, 1.0
TAC_WIRE_REACH, TAC_WIRE_LEN, TAC_WIRE_ARM = 4.0, 6.0, 2.0 -- m to plant; longest wire; s to arm
TAC_WIRE_SIZE, TAC_WIRE_NEAR = 1.5, 0.35                   -- explosion size; m from the wire that trips it (a body's half width)

local c4 = {}            -- (host) player -> {body, parent, local, t0, flying}
local clays = {}         -- (host) {body, owner, armAt, fwd}
local wireSet = {}       -- (host) player -> {charge, pos, t0}: the charge planted, the hook still to come
local wires = {}         -- (host) {charge, hook, a, b, owner, armAt}

local function publish()
	local c, w, k = {}, {}, {}
	for p, s in pairs(c4) do if s.body then c[#c + 1] = {p = p, b = s.body} end end
	for _, s in ipairs(clays) do k[#k + 1] = {b = s.body, armAt = s.armAt} end
	for _, s in ipairs(wires) do w[#w + 1] = {ax = s.a[1], ay = s.a[2], az = s.a[3], bx = s.b[1], by = s.b[2], bz = s.b[3], armAt = s.armAt, b = s.charge} end
	for p, s in pairs(wireSet) do w[#w + 1] = {b = s.charge, armAt = -1, single = true} end
	shared.tac.c4, shared.tac.clay, shared.tac.wire = c, k, w
end

function TacPlaceInit()
	shared.tac = shared.tac or {}
	shared.tac.c4, shared.tac.clay, shared.tac.wire = {}, {}, {}
end

-- a placed body that sits on another body follows it (a car, a door)
local function follow(s)
	if s.parent and s.parent ~= 0 and IsHandleValid(s.parent) and IsHandleValid(s.body) and IsBodyDynamic(s.parent) then
		SetBodyTransform(s.body, TransformToParentTransform(GetBodyTransform(s.parent), s.loc))
	end
end

local function attach(s, sh)
	s.parent = (sh and sh ~= 0) and GetShapeBody(sh) or 0
	if s.parent ~= 0 then s.loc = TransformToLocalTransform(GetBodyTransform(s.parent), GetBodyTransform(s.body)) end
end

local function boom(pos, size, owner)
	TacVillagersCause(pos, 1.5)                                      -- (villagers: a device fired here)
	Explosion(pos, size)
	TacEvent("boom", pos, size)
end

------------------------------------------------------------------------------------------------------------ C4

-- (host) what a click of the C4 does (tests call it directly)
function TacC4Action(p)
	local now = GetTime()
	local s = c4[p]
	if TacHasAmmo(p, "tac_c4") then
		if not s then
			-- 1st click: stick it where aimed, else throw it (it sticks to what it hits)
			local at, n, sh = TacAim(p, TAC_C4_REACH)
			local _, fwd = TacEye(p)
			if at then
				local rot = TacOnSurface(n, fwd)
				local body = TacSpawnWorld("c4", Transform(VecAdd(at, VecScale(n, 0.10)), rot))
				TacVillagersMark(body)
				if body then
					s = {body = body, t0 = now}
					attach(s, sh)
					c4[p] = s
					TacEvent("stick", at)
				end
			else
				local body = TacSpawnWorld("c4", Transform(TacEye(p).pos))
				TacVillagersMark(body)
				if body then
					s = {body = body, t0 = now, flying = true}
					c4[p] = s
					TacThrow(p, body, true, function(pos, nrm, sh)
						s.flying = false
						attach(s, sh)
						TacEvent("stick", pos)
					end, "c4")
				end
			end
			publish()
		elseif not s.flying then
			-- 2nd click: the detonator
			local pos = IsHandleValid(s.body) and GetBodyTransform(s.body).pos
			if IsHandleValid(s.body) then Delete(s.body) end
			c4[p] = nil
			TacEvent("click", TacEye(p).pos)
			if pos then boom(pos, TAC_C4_SIZE, p) end
			TacSpend(p, "tac_c4")
			publish()
		end
	end
end

local function c4Tick(p, now)
	if TacClicked(p, "tac_c4") then TacC4Action(p) end
	local s = c4[p]
	if s and not s.flying and TacBroken(s.body) then                  -- (shot / hit / a blast: it goes off)
		local pos = GetBodyTransform(s.body).pos
		Delete(s.body)
		c4[p] = nil
		boom(pos, TAC_C4_SIZE, p)
		TacSpend(p, "tac_c4")
		publish()
		return
	end
	if s then
		follow(s)
		if not IsHandleValid(s.body) then
			c4[p] = nil                                              -- (blown up by something else)
			publish()
		elseif GetToolAmmo("tac_c4", p) <= 0 and now - s.t0 > TAC_C4_ORPHAN then
			Delete(s.body)                                           -- (the detonator is gone: the charge goes quiet)
			c4[p] = nil
			publish()
		end
	end
end

------------------------------------------------------------------------------------------------------------ claymore

-- (host) what a click of the claymore does
function TacClayAction(p)
	local now = GetTime()
	if not TacHasAmmo(p, "tac_claymore") then return end
	local e, fwd = TacEye(p)
	local flat = VecNormalize(Vec(fwd[1], 0, fwd[3]))
	if VecLength(flat) < 0.1 then flat = Vec(0, 0, -1) end
	local start = VecAdd(VecAdd(Vec(e.pos[1], GetPlayerTransform(p).pos[2], e.pos[3]), VecScale(flat, 0.9)), Vec(0, 1.0, 0))
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, d, n, sh = QueryRaycast(start, Vec(0, -1, 0), 2.5)
	if not hit then return end
	local at = VecAdd(start, Vec(0, -d + 0.15, 0))
	local body = TacSpawnWorld("claymore", Transform(at, QuatLookAt(at, VecAdd(at, flat))))
	TacVillagersMark(body, TAC_VKIND_DEVICE)                         -- (villagers: "a strange little box on legs")
	if not body then return end
	local s = {body = body, owner = p, armAt = now + TAC_CLAY_ARM, fwd = flat}
	attach(s, sh)
	clays[#clays + 1] = s
	TacSpend(p, "tac_claymore")
	TacEvent("place", at)
	publish()
end

local function clayFire(s)
	local t = GetBodyTransform(s.body)
	local fwd = TransformToParentVec(t, Vec(0, 0, -1))
	local origin = TransformToParentPoint(t, Vec(0, 0.0, -0.12))
	TacVillagersCause(VecAdd(origin, VecScale(fwd, 2.5)), 5)          -- (its pellets)
	Delete(s.body)
	boom(VecAdd(origin, VecScale(fwd, 0.2)), TAC_CLAY_SIZE, s.owner)
	for _ = 1, TAC_CLAY_PELLETS do                               -- the steel balls: a fan forward
		local yaw = math.rad((math.random() * 2 - 1) * TAC_CLAY_HALF)
		local pitch = math.rad(math.random() * 14 - 4)
		local dir = Vec(fwd[1] * math.cos(yaw) - fwd[3] * math.sin(yaw), math.sin(pitch), fwd[1] * math.sin(yaw) + fwd[3] * math.cos(yaw))
		Shoot(origin, VecNormalize(dir), "bullet", 1.0, 12, s.owner)
	end
end

local function clayTick(now)
	local i = 1
	local changed = false
	while i <= #clays do
		local s = clays[i]
		follow(s)
		local fired = false
		if not IsHandleValid(s.body) then
			fired = true
		elseif TacBroken(s.body) then                                -- (shot / hit / a blast: it fires)
			clayFire(s)
			fired = true
		elseif now >= s.armAt then
			local t = GetBodyTransform(s.body)
			local fwd = TransformToParentVec(t, Vec(0, 0, -1))
			local eye = TransformToParentPoint(t, Vec(0, 0.05, -0.12))
			for _, v in ipairs(GetAllPlayers()) do
				if GetPlayerHealth(v) > 0 then                       -- (anyone, the owner too - the user; it arms after TAC_CLAY_ARM)
					local chest = VecAdd(GetPlayerTransform(v).pos, Vec(0, 1.0, 0))
					local to = VecSub(chest, eye)
					local d = VecLength(to)
					if d < TAC_CLAY_RANGE and d > 0.05 then
						local dir = VecScale(to, 1 / d)
						if VecDot(VecNormalize(Vec(dir[1], 0, dir[3])), fwd) >= math.cos(math.rad(TAC_CLAY_HALF)) then
							QueryRejectBody(s.body)
							QueryRejectPlayer(v)
							QueryRequire("physical")
							if not QueryRaycast(eye, dir, d) then
								clayFire(s)
								fired = true
								break
							end
						end
					end
				end
			end
			if not fired then                                          -- (and for villagers: AI Villagers, tac_villagers.lua)
				for _, V in ipairs(TacVillagers()) do
					local chest = VecAdd(V.pos, Vec(0, 1.1, 0))
					local to = VecSub(chest, eye)
					local d = VecLength(to)
					if d < TAC_CLAY_RANGE and d > 0.05 then
						local dir = VecScale(to, 1 / d)
						if VecDot(VecNormalize(Vec(dir[1], 0, dir[3])), fwd) >= math.cos(math.rad(TAC_CLAY_HALF)) and TacVillagerClear(eye, chest, s.body) then
							clayFire(s)
							fired = true
							break
						end
					end
				end
			end
		end
		if fired then
			table.remove(clays, i)
			changed = true
		else
			i = i + 1
		end
	end
	if changed then publish() end
end

------------------------------------------------------------------------------------------------------------ wire trap

local function distToSegment(p, a, b)
	local ab = VecSub(b, a)
	local l2 = VecDot(ab, ab)
	local t = l2 > 0 and math.max(0, math.min(1, VecDot(VecSub(p, a), ab) / l2)) or 0
	return VecLength(VecSub(p, VecAdd(a, VecScale(ab, t))))
end

local function wirePlace(p, now)
	local s = wireSet[p]
	if s and TacBroken(s.charge) then                                -- (the charge shot before the hook is in: it goes off)
		local pos = GetBodyTransform(s.charge).pos
		Delete(s.charge)
		wireSet[p] = nil
		boom(pos, TAC_WIRE_SIZE, p)
		TacSpend(p, "tac_wiretrap")
		publish()
		return
	end
	if s and (not TacHolding(p, "tac_wiretrap") or now - s.t0 > 30) then
		if IsHandleValid(s.charge) then Delete(s.charge) end         -- (left half-done: the charge comes back up)
		wireSet[p] = nil
		publish()
		return
	end
	if TacClicked(p, "tac_wiretrap") then TacWireAction(p) end
end

-- (host) what a click of the wire trap does: the charge, then the hook
function TacWireAction(p)
	local now = GetTime()
	local s = wireSet[p]
	if not TacHasAmmo(p, "tac_wiretrap") then return end
	local _, fwd = TacEye(p)
	if not s then
		local at, n, sh = TacAim(p, TAC_WIRE_REACH)
		if not at then return end
		local body = TacSpawnWorld("wiretrap", Transform(VecAdd(at, VecScale(n, 0.22)), TacOnSurface(n, fwd)))
		if not body then return end
		wireSet[p] = {charge = body, pos = TransformToParentPoint(GetBodyTransform(body), Vec(0.025, 0.225, -0.025)), t0 = now}
		TacEvent("place", at)
	else
		local at, n, sh = TacAim(p, TAC_WIRE_REACH + TAC_WIRE_LEN)
		if not at then return end
		local len = VecLength(VecSub(at, s.pos))
		if len > TAC_WIRE_LEN or len < 0.4 then TacEvent("deny", at) return end
		-- (the wire's line: to where it ties on the hook, 0.3 m off the surface - to the aimed point itself a bump on
		-- rough ground refused it: the joint villagers run)
		local tie = VecAdd(at, VecScale(n, 0.3))
		local tl = VecLength(VecSub(tie, s.pos))
		local dir = VecScale(VecSub(tie, s.pos), 1 / tl)
		QueryRejectBody(s.charge)
		QueryRequire("physical")
		local hit, d = QueryRaycast(s.pos, dir, tl - 0.15)
		if hit then TacEvent("deny", at) return end
		local hook = TacSpawnWorld("wiretrap_hook", Transform(VecAdd(at, VecScale(n, 0.17)), TacOnSurface(n, fwd)))
		if not hook then return end
		local b = TransformToParentPoint(GetBodyTransform(hook), Vec(0.025, 0.125, -0.025))
		wires[#wires + 1] = {charge = s.charge, hook = hook, a = s.pos, b = b, owner = p, armAt = now + TAC_WIRE_ARM}
		wireSet[p] = nil
		TacSpend(p, "tac_wiretrap")
		TacEvent("place", at)
	end
	publish()
end

local wireAt = 0
local function wireTick(now)
	local slow = now >= wireAt                                       -- (players every tick: a sprint must not skip the
	if slow then wireAt = now + 0.05 end                             -- wire; the raycast for moving things at 20 Hz)
	local i = 1
	local changed = false
	while i <= #wires do
		local w = wires[i]
		local fire = not IsHandleValid(w.charge) or TacBroken(w.charge) or not IsHandleValid(w.hook) or TacBroken(w.hook)
		if not fire and now >= w.armAt then
			for _, v in ipairs(GetAllPlayers()) do
				if GetPlayerHealth(v) > 0 then                       -- (anyone, the owner too - the user; it arms after TAC_WIRE_ARM)
					local f = GetPlayerTransform(v).pos
					-- (the body as a line from the shins to the chest: crossing anywhere on it)
					for _, h in ipairs({0.25, 0.6, 1.0, 1.4}) do
						if distToSegment(VecAdd(f, Vec(0, h, 0)), w.a, w.b) < TAC_WIRE_NEAR then fire = true break end
					end
				end
				if fire then break end
			end
			if not fire then                                           -- (and villagers walking through it)
				for _, V in ipairs(TacVillagers()) do
					for _, h in ipairs({0.25, 0.6, 1.0, 1.4}) do
						if distToSegment(VecAdd(V.pos, Vec(0, h, 0)), w.a, w.b) < TAC_WIRE_NEAR then fire = true break end
					end
					if fire then break end
				end
			end
			if not fire and slow then                                -- something moving through it (a car, a crate)
				local len = VecLength(VecSub(w.b, w.a))
				QueryRejectBody(w.charge)
				QueryRejectBody(w.hook)
				QueryRequire("physical dynamic")
				local hit, d, n, sh = QueryRaycast(w.a, VecScale(VecSub(w.b, w.a), 1 / len), len - 0.05)
				if hit and sh and sh ~= 0 and VecLength(GetBodyVelocity(GetShapeBody(sh))) > 0.3 then fire = true end
			end
		end
		if fire then
			if IsHandleValid(w.charge) then Delete(w.charge) end
			if IsHandleValid(w.hook) then Delete(w.hook) end
			boom(w.a, TAC_WIRE_SIZE, w.owner)
			table.remove(wires, i)
			changed = true
		else
			i = i + 1
		end
	end
	if changed then publish() end
end

-- (host) every tick
function TacPlaceTick(dt)
	local now = GetTime()
	for _, p in ipairs(GetAllPlayers()) do
		c4Tick(p, now)
		if TacClicked(p, "tac_claymore") then TacClayAction(p) end
		wirePlace(p, now)
	end
	clayTick(now)
	wireTick(now)
end

------------------------------------------------------------------------------------------------------------ client

function TacPlaceEvent(kind, pos, v)
	if kind == "stick" then
		PlaySound(TacSound("stick", "tools/wire-attach0.ogg"), pos, 0.8, true, 0.8)
	elseif kind == "place" then
		PlaySound(TacSound("place", "tools/plank-attach0.ogg"), pos, 0.7, true, 1.2)
	elseif kind == "click" then
		PlaySound(TacSound("det", "clickdown.ogg"), pos, 1.0, false, 0.6)
	elseif kind == "deny" then
		PlaySound(TacSound("deny", "tool-select-fail.ogg"), pos, 0.6, false)
	elseif kind == "boom" then
		-- (Explosion makes its own sound and fire; nothing more)
	end
end

-- (client) every frame: blinking lights, the wires, the C4 brick gone from the hand of who placed it
local hidden = {}        -- player -> the brick shape hidden on this machine
function TacPlaceClientTick(dt)
	local now = GetTime()
	local t = shared.tac or {}
	local blink = (now % 1.0) < 0.12
	local placed = {}
	for _, s in ipairs(t.c4 or {}) do
		placed[s.p] = true
		if blink and IsHandleValid(s.b) then
			PointLight(TransformToParentPoint(GetBodyTransform(s.b), Vec(-0.025, 0.1, -0.025)), 1, 0.08, 0.05, 0.35)
		end
	end
	for _, s in ipairs(t.clay or {}) do
		if IsHandleValid(s.b) then
			local armed = now >= TacSeen(s.b, now) + TAC_CLAY_ARM            -- (this machine's clock, not the host's)
			if (armed and (now % 1.4) < 0.1) or (not armed and (now % 0.3) < 0.12) then
				PointLight(TransformToParentPoint(GetBodyTransform(s.b), Vec(0, 0.2, 0)), 1, armed and 0.1 or 0.7, 0.05, 0.25)
			end
		end
	end
	for _, w in ipairs(t.wire or {}) do
		if not w.single then
			DrawLine(Vec(w.ax, w.ay, w.az), Vec(w.bx, w.by, w.bz), 0.22, 0.24, 0.2, 0.9)
		end
	end
	-- the brick: the second shape of the C4 tool's body, hidden once its charge is placed
	for _, p in ipairs(GetAllPlayers()) do
		local want = placed[p] and GetPlayerTool(p) == "tac_c4"
		local tb = GetToolBody(p)
		if want and tb and tb ~= 0 then
			local shapes = GetBodyShapes(tb)
			local brick = shapes[2]
			if brick and hidden[p] ~= brick then
				SetTag(brick, "invisible")
				hidden[p] = brick
			end
		elseif hidden[p] then
			if IsHandleValid(hidden[p]) then RemoveTag(hidden[p], "invisible") end
			hidden[p] = nil
		end
	end
end

-- (tests) what is placed: C4 charges, claymores, wires, half-set wires
function TacPlaceCounts()
	local n = 0
	for _ in pairs(c4) do n = n + 1 end
	local h = 0
	for _ in pairs(wireSet) do h = h + 1 end
	return n, #clays, #wires, h
end
