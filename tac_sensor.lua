-- The motion sensor (client only, the owner's screen): held, it pings every TAC_SENSOR_EVERY s; a player within
-- TAC_SENSOR_RANGE m who MOVES gets revealed - the user: "sensed player gets revealed to the owner of the sensor just
-- like echolocation on hvc mod": their live pose drawn as glowing lines through walls for TAC_SENSOR_SHOW s, as
-- Humans vs Clickers draws an echolocated human (its capturePose / drawPose). No radar on screen (the user: "that
-- should be a separate equipment").

TAC_SENSOR_EVERY, TAC_SENSOR_RANGE, TAC_SENSOR_SHOW = 2.5, 30, 2.0
TAC_SENSOR_MOVE = 1.0                            -- m/s: slower than this (standing, creeping) is not sensed
TAC_SENSOR_COL = {0.35, 1.0, 0.45}

local CHAINS = {
	{"head", "neck", "chest", "stomach", "pelvis"},
	{"chest", "shoulder_l", "arm_upper_l", "arm_lower_l", "hand_l"},
	{"chest", "shoulder_r", "arm_upper_r", "arm_lower_r", "hand_r"},
	{"pelvis", "leg_upper_l", "leg_lower_l", "foot_l"},
	{"pelvis", "leg_upper_r", "leg_lower_r", "foot_r"},
}

local nextPing = 0
local seen = {}          -- player -> time revealed until
local seenV = {}         -- {pos, untilT}: moving villagers caught by the last pings (AI Villagers: shared.tac.vmove)
local last = {}          -- player -> {pos, t}: speed from movement (a remote player's velocity isn't always known)

local function speedOf(p, now)
	local pos = GetPlayerTransform(p).pos
	local l = last[p]
	local v = 0
	if l and now - l.t > 0.02 then
		v = VecLength(VecSub(Vec(pos[1], 0, pos[3]), Vec(l.pos[1], 0, l.pos[3]))) / (now - l.t)
		l.v = 0.6 * (l.v or v) + 0.4 * v
		v = l.v
		l.pos, l.t = pos, now
	elseif not l then
		last[p] = {pos = pos, t = now, v = 0}
	else
		v = l.v or 0
	end
	return math.max(v, VecLength(GetPlayerVelocity(p) or Vec()))
end

function TacSensorHeld()
	local me = GetLocalPlayer()
	return GetPlayerTool(me) == "tac_sensor" and GetPlayerHealth(me) > 0
end

-- (client tick)
function TacSensorTick(dt)
	local now = GetTime()
	local me = GetLocalPlayer()
	for _, p in ipairs(GetAllPlayers()) do if p ~= me then speedOf(p, now) end end
	if not TacSensorHeld() then
		nextPing = math.max(nextPing, now + 0.6)                     -- (the first ping comes soon after taking it out)
		return
	end
	if now < nextPing then return end
	nextPing = now + TAC_SENSOR_EVERY
	local mine = GetPlayerTransform(me)
	local any = false
	for _, p in ipairs(GetAllPlayers()) do
		if p ~= me and GetPlayerHealth(p) > 0 then
			local pos = GetPlayerTransform(p).pos
			local rel = TransformToLocalPoint(mine, pos)
			local d = VecLength(Vec(rel[1], 0, rel[3]))
			if d <= TAC_SENSOR_RANGE and speedOf(p, now) >= TAC_SENSOR_MOVE then
				seen[p] = now + TAC_SENSOR_SHOW
				any = true
			end
		end
	end
	for _, v in ipairs((shared.tac and shared.tac.vmove) or {}) do
		local pos = Vec(v.x, v.y, v.z)
		local rel = TransformToLocalPoint(mine, pos)
		if VecLength(Vec(rel[1], 0, rel[3])) <= TAC_SENSOR_RANGE then
			seenV[#seenV + 1] = {pos = pos, untilT = now + TAC_SENSOR_SHOW}
			any = true
		end
	end
	PlaySound(TacSound(any and "ping2" or "ping", "MOD/snd/tac_ping.ogg"), mine.pos, any and 0.55 or 0.3, false, any and 1.25 or 1.0)
end

-- a revealed player's live pose on screen: glowing lines, through walls
local function drawPose(p, a)
	local anim = GetPlayerAnimator(p)
	if not anim or anim == 0 then return end
	local c = TAC_SENSOR_COL
	for pass = 1, 2 do
		for _, ch in ipairs(CHAINS) do
			local px, py, pd = nil, nil, nil
			for _, bone in ipairs(ch) do
				local x, y, d = UiWorldToPixel(GetBoneWorldTransform(anim, bone).pos)
				if d > 0 and pd and pd > 0 then
					UiPush()
					UiColor(c[1], c[2], c[3], a * (pass == 1 and 0.25 or 0.95))
					local dx, dy = x - px, y - py
					local len = math.sqrt(dx * dx + dy * dy)
					if len > 0.5 then
						UiTranslate(px, py)
						UiRotate(-math.deg(math.atan2(dy, dx)))
						UiAlign("left middle")
						UiRect(len, pass == 1 and 9 or 3)
					end
					UiPop()
				end
				px, py, pd = x, y, d
			end
		end
		local hx, hy, hd = UiWorldToPixel(GetBoneWorldTransform(anim, "head").pos)
		if hd > 0 then
			UiPush()
			UiTranslate(hx, hy)
			UiAlign("center middle")
			UiColor(c[1], c[2], c[3], a * (pass == 1 and 0.25 or 0.95))
			UiCircle(pass == 1 and 12 or 6)
			UiPop()
		end
	end
end

-- a villager caught moving (no pose of theirs here): a glowing upright figure at their feet's point, through walls
local function drawFigure(feet, a)
	local c = TAC_SENSOR_COL
	local fx, fy, fd = UiWorldToPixel(feet)
	local hx, hy, hd = UiWorldToPixel(VecAdd(feet, Vec(0, 1.6, 0)))
	if fd <= 0 or hd <= 0 then return end
	for pass = 1, 2 do
		UiPush()
		UiColor(c[1], c[2], c[3], a * (pass == 1 and 0.25 or 0.95))
		local dx, dy = hx - fx, hy - fy
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0.5 then
			UiTranslate(fx, fy)
			UiRotate(-math.deg(math.atan2(dy, dx)))
			UiAlign("left middle")
			UiRect(len, pass == 1 and 9 or 3)
		end
		UiPop()
		UiPush()
		UiTranslate(hx, hy)
		UiAlign("center middle")
		UiColor(c[1], c[2], c[3], a * (pass == 1 and 0.25 or 0.95))
		UiCircle(pass == 1 and 12 or 6)
		UiPop()
	end
end

-- (client draw) the reveals
function TacSensorDraw()
	local now = GetTime()
	local me = GetLocalPlayer()
	for p, untilT in pairs(seen) do
		if now < untilT and IsPlayerValid(p) then
			drawPose(p, math.min(1, (untilT - now) / 0.6))
		else
			seen[p] = nil
		end
	end
	local keepV = {}
	for _, v in ipairs(seenV) do
		if now < v.untilT then
			keepV[#keepV + 1] = v
			drawFigure(v.pos, math.min(1, (v.untilT - now) / 0.6))
		end
	end
	seenV = keepV
end

-- (tests) is player p revealed on this screen now
function TacSensorRevealed(p) return seen[p] ~= nil and GetTime() < seen[p] end

-- (tests) how many moving villagers this screen shows now
function TacSensorSeenVillagers()
	local n, now = 0, GetTime()
	for _, v in ipairs(seenV) do if now < v.untilT then n = n + 1 end end
	return n
end
