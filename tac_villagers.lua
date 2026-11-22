-- The Tactical Gear Pack and AI Villagers (villagers/mods/villagers/API.md, agreed with that mod's session
-- 2026-11-21; the user: "make these work on those villagers as well"). Host registry keys only: without the
-- Villagers mod nothing reads them and nothing here breaks.
--   - what villagers see and judge for themselves (vlkind tags: gone with the body): a planted C4 is "a planted
--     explosive" (danger 0.7: a blinking brick reads as a bomb); a claymore is what they would honestly see, "a strange
--     little box on legs" (danger 0.15, no reputation: most are curious or ignore it, a reckless one may poke at it -
--     the Villagers session's suggestion: as "a planted explosive" they all fled it); a wire trap is not marked (a thin
--     wire nobody notices);
--   - claymores and wire traps go off for villagers as for players (villagers.v.<id>.x/y/z, read at 10 Hz);
--   - the blasts and the claymore's pellets say a device fired there (villagers.cause.*: nobody blamed - the user: villagers
--     only know who set a trap if they see it) - the engine's own hits do the harm;
--   - a flashbang: villagers.flash.* (the Villagers mod decides who is blinded);
--   - smoke: villagers.cover.* spheres they can't see through, re-sent as a cloud grows;
--   - the motion sensor shows moving villagers too (the host publishes them in shared.tac.vmove).
-- No villagers.news for the bangs: they hear engine explosions already (their session: it would make them react twice).

TAC_VKIND = "tacexplosive"
TAC_VKIND_DEVICE = "tacdevice"
TAC_VMOVE = 1.0                                   -- m/s: a villager moving faster shows on the sensor (as players)

-- (server.init) the kind, described once: the villagers judge it themselves (no per-villager feelings)
function TacVillagersInit()
	local b = "villagers.kind." .. TAC_VKIND .. "."
	SetString(b .. "name", "a planted explosive")
	SetString(b .. "note", "a brick of plastic explosive with a blinking light, stuck where someone left it. It can go off "
		.. "at any moment and kill whoever is near")
	SetFloat(b .. "danger", 0.7)
	SetString(b .. "feel", "fear")
	SetString(b .. "doing", "blinking")
	local d = "villagers.kind." .. TAC_VKIND_DEVICE .. "."
	SetString(d .. "name", "a strange little box on legs")
	SetString(d .. "note", "a small curved green box standing on short legs, facing one way, with a cable; you don't know what it is")
	SetFloat(d .. "danger", 0.15)
end

-- (host) a set-down thing becomes what villagers see: kind = TAC_VKIND (a C4) or TAC_VKIND_DEVICE (a claymore)
function TacVillagersMark(body, kind)
	if body and body ~= 0 and IsHandleValid(body) then SetTag(body, "vlkind", kind or TAC_VKIND) end
end

local vl, vlAt = {}, -1
local vlLast = {}                                 -- id -> {pos, t}: speed from movement
-- (host) the living villagers: {id, pos (feet), speed}; refreshed 10 times a second
function TacVillagers()
	local now = GetTime()
	if now < vlAt then return vl end
	vlAt = now + 0.1
	vl = {}
	local list = GetString("villagers.list")
	if list == "" then return vl end
	for id in string.gmatch(list, "[^,]+") do
		local b = "villagers.v." .. id .. "."
		if GetBool(b .. "alive") then
			local pos = Vec(GetFloat(b .. "x"), GetFloat(b .. "y"), GetFloat(b .. "z"))
			-- (their positions come twice a second: the speed is taken between two different positions - at 10 Hz
			-- most samples saw none and a walking villager read as standing; the joint villagers run)
			local l = vlLast[id]
			local v = l and l.v or 0
			if not l then
				vlLast[id] = {pos = pos, t = now, v = 0}
			else
				local moved = VecLength(Vec(pos[1] - l.pos[1], 0, pos[3] - l.pos[3]))
				if moved > 0.02 and now - l.t > 0.2 then
					v = moved / (now - l.t)
					vlLast[id] = {pos = pos, t = now, v = v}
				elseif now - l.t > 1.2 then                          -- (no new position for a while: standing)
					v = 0
					vlLast[id] = {pos = pos, t = now, v = 0}
				end
			end
			vl[#vl + 1] = {id = id, pos = pos, speed = v, shape = GetInt(b .. "shape")}
		end
	end
	return vl
end

local function ring(name)
	local n = GetInt("villagers." .. name .. ".last") + 1
	return n, "villagers." .. name .. "." .. (n % 16) .. "."
end

-- (host) a blast or shot of ours at pos: a device fired here (the engine's own hits within r hurt the villagers; no blame)
function TacVillagersCause(pos, r)
	if GetString("villagers.list") == "" and not GetBool("villagers.present") then return end
	local n, b = ring("cause")
	SetFloat(b .. "x", pos[1]) SetFloat(b .. "y", pos[2]) SetFloat(b .. "z", pos[3])
	SetFloat(b .. "r", r)
	SetFloat(b .. "until", GetTime() + 0.5)
	SetBool(b .. "handled", false)
	SetInt("villagers.cause.last", n)
end

-- (host) a flashbang went off at pos: the Villagers mod works out who sees it
function TacVillagersFlash(pos, range, strength)
	if GetString("villagers.list") == "" and not GetBool("villagers.present") then return end
	local n, b = ring("flash")
	SetFloat(b .. "x", pos[1]) SetFloat(b .. "y", pos[2]) SetFloat(b .. "z", pos[3])
	SetFloat(b .. "range", range)
	SetFloat(b .. "strength", strength)
	SetInt("villagers.flash.last", n)
end

-- (host) a smoke cloud: a sphere villagers can't see through; the same id re-sent moves or grows it
function TacVillagersCover(id, pos, r, untilT)
	if GetString("villagers.list") == "" and not GetBool("villagers.present") then return end
	local n, b = ring("cover")
	SetFloat(b .. "x", pos[1]) SetFloat(b .. "y", pos[2]) SetFloat(b .. "z", pos[3])
	SetFloat(b .. "r", r)
	SetFloat(b .. "until", untilT)
	SetString(b .. "id", "tac" .. tostring(id))
	SetInt("villagers.cover.last", n)
end

-- (host) is villager V's body (feet to chest) clear to see from `eye` (a claymore's): a ray that stops on the
-- villager itself counts as clear (their hitbox and body are in the way of their own chest)
function TacVillagerClear(eye, target, ignoreBody)
	local to = VecSub(target, eye)
	local d = VecLength(to)
	if d < 0.05 then return true end
	if ignoreBody then QueryRejectBody(ignoreBody) end
	QueryRequire("physical")
	local hit, hd = QueryRaycast(eye, VecScale(to, 1 / d), d)
	return not hit or hd > d - 0.6
end

-- (host, every tick) the moving villagers for the sensor, published about once a second (a small list)
local moveAt = 0
function TacVillagersTick()
	local now = GetTime()
	if now < moveAt then return end
	moveAt = now + 1.0
	local out = {}
	for _, V in ipairs(TacVillagers()) do
		if V.speed >= TAC_VMOVE then out[#out + 1] = {x = V.pos[1], y = V.pos[2], z = V.pos[3]} end
	end
	local had = shared.tac.vmove or {}
	if #out > 0 or #had > 0 then shared.tac.vmove = out end         -- (nothing written while nobody moves)
end
