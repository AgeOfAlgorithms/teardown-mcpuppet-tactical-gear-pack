-- McPuppet Tactical Gear Pack Vol 1: what the pack's files share - the item list, the registry keys that make the
-- tools and the goggles inventory items, the click and ammo helpers, sounds, and the events the host sends the
-- clients. Globals only: each included file keeps its own locals (Teardown's #include gives no access to them).

TAC_ITEMS = {
	-- id, name, prefab name, price, ammo (one item = a pack of that many; nil: no ammo), spent (gone with the last), tip
	{id = "tac_binoculars", name = "Binoculars", file = "binoculars", price = 400,
		tip = "Hold LMB to look through them|Shows the range to what you look at"},
	{id = "tac_sensor", name = "Motion Sensor", file = "sensor", price = 1500,
		tip = "Held: pings every 2.5 s|Reveals players moving within 30 m"},
	{id = "tac_glowstick", name = "Glowstick", file = "glowstick", price = 60, ammo = 5, spent = true,
		tip = "LMB: crack and throw one|Glows green for 3 minutes"},
	{id = "tac_flashbang", name = "Flashbang", file = "flashbang", price = 300, ammo = 2, spent = true,
		tip = "LMB: throw (1.8 s fuse)|Blinds and deafens whoever sees it"},
	{id = "tac_smoke", name = "Smoke Grenade", file = "smoke", price = 250, ammo = 2, spent = true,
		tip = "LMB: throw (1.5 s fuse)|A thick cloud for 25 s"},
	{id = "tac_c4", name = "C4", file = "c4", price = 800, ammo = 1, spent = true,
		tip = "LMB: stick it where you aim, or throw it|LMB again: detonate"},
	{id = "tac_claymore", name = "Claymore", file = "claymore", price = 700, ammo = 1, spent = true,
		tip = "LMB: set it down facing where you look|Fires at players who walk into its front"},
	{id = "tac_wiretrap", name = "Wire Trap", file = "wiretrap", price = 500, ammo = 1, spent = true,
		tip = "LMB: plant the charge, LMB: hook the wire|Whoever crosses the wire sets it off"},
}
TAC_BY_ID = {}
for _, t in ipairs(TAC_ITEMS) do TAC_BY_ID[t.id] = t end
TAC_NVG = "tac_nvg"

-- the registry keys that make them inventory items: every machine, from both inits (MODDING.md)
function TacRegister()
	for _, t in ipairs(TAC_ITEMS) do
		local k = "inventory.tools." .. t.id
		SetBool(k, true)
		SetInt(k .. ".price", t.price)
		SetString(k .. ".icon", "icons/" .. t.id .. ".png")
		SetString(k .. ".tip", t.tip)
		if t.ammo then
			SetInt(k .. ".ammo", t.ammo)
			SetBool(k .. ".spent", t.spent == true)
		end
	end
end

-- the goggles: clothing through this pack's inventory_api.lua (head slot, worn over everything, not reshaped)
function TacClothing()
	InventoryClothing({id = TAC_NVG, name = "Night Vision Goggles", slot = "head", layer = 2, rigid = true,
		vox = "MOD/vox/tac_nvg.vox", parts = "head", covers = "", tint = false, armor = 0.02, mobility = 0, noise = 0,
		type = "equipment.head.nightvision", price = 1200, icon = "icons/tac_nvg.png", drop = "vox/drop_tac_nvg.vox"})
end

-- (host) the tools become game tools
function TacRegisterTools()
	for _, t in ipairs(TAC_ITEMS) do
		RegisterTool(t.id, t.name, "MOD/prefab/tac_" .. t.file .. ".xml", 6)
		if t.ammo then SetBool("game.tool." .. t.id .. ".ammo.display", true) end
	end
end

-- (host) player p holds tool id, alive, on foot
function TacHolding(p, id)
	return GetPlayerTool(p) == id and GetPlayerHealth(p) > 0 and (GetPlayerVehicle(p) or 0) == 0
end

-- (host) a fresh click of the tool's button
function TacClicked(p, id)
	return TacHolding(p, id) and InputPressed("usetool", p)
end

-- (host) one unit of the tool's ammo used (the Inventory follows the game's count; .spent removes the item at 0)
function TacSpend(p, id)
	SetToolAmmo(id, math.max(0, GetToolAmmo(id, p) - 1), p)
end

function TacHasAmmo(p, id)
	return GetToolAmmo(id, p) > 0
end

-- (host) the eye: position and the way the player looks. TacAimOverride[p] = {pos, dir} replaces it (tests: no mouse)
TacAimOverride = {}
function TacEye(p)
	local o = TacAimOverride[p]
	if o then
		local d = VecNormalize(o.dir)
		return Transform(o.pos, QuatLookAt(o.pos, VecAdd(o.pos, d))), d
	end
	local e = GetPlayerEyeTransform(p)
	return e, TransformToParentVec(e, Vec(0, 0, -1))
end

-- (host) the first solid thing along the look, within reach: point, normal, shape
function TacAim(p, reach)
	local e, fwd = TacEye(p)
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist, n, sh = QueryRaycast(e.pos, fwd, reach)
	if hit then return VecAdd(e.pos, VecScale(fwd, dist)), n, sh end
	return nil
end

-- a rotation whose local +y is the surface normal n (and -z faces along `ahead` as near as it can)
function TacOnSurface(n, ahead)
	local fwd = ahead or Vec(0, 0, -1)
	local d = VecDot(fwd, n)
	local t = VecSub(fwd, VecScale(n, d))
	if VecLength(t) < 0.05 then t = math.abs(n[2]) < 0.9 and Vec(0, 1, 0) or Vec(1, 0, 0); t = VecSub(t, VecScale(n, VecDot(t, n))) end
	t = VecNormalize(t)
	local x = VecCross(n, VecScale(t, -1))             -- (right = up x back)
	return QuatAlignXZ(x, VecScale(t, -1))
end

-- (host) spawn one of the pack's world models (0.05 m voxels at scale 0.5: a static body the host moves)
function TacSpawnWorld(name, t)
	local e = Spawn("<body><vox file='MOD/vox/tac_" .. name .. "_w.vox' scale='0.5'/></body>", t, true)
	for _, h in ipairs(e or {}) do
		if GetEntityType(h) == "body" then
			SetTag(h, "tac")
			return h
		end
	end
	return nil
end

-- events for every client (sounds, the flash, the smoke start): kind, position, a value
function TacEvent(kind, pos, v)
	ClientCall(0, "client.tacEvent", kind, pos[1], pos[2], pos[3], v or 0)
end

-- (host) a set-down thing was shot, hit or caught in a blast (the user: "anyone could also shoot them or attack them to
-- activate and/or break them"): any of its voxels gone - bullets, melee weapons, fists and explosions all take some
-- What hits a thing, gathered once a tick (TacHitsTick, first in server.tick): the engine's projectilehit (a bullet's
-- shape - a hole or not), its explosion events (a blast within reach: 0.5 m + 1 m a unit of strength) and the
-- Inventory's melee hit ring (inventory.melee.hit.*: weapons and punches) - and, besides, the game's own broken flag and
-- fewer voxels than the thing ever had.
TAC_HITBODY, TAC_BLASTS = {}, {}
local meleeSeen = nil
-- a gun: the game's own, or another mod's whose id says so (gun, rifle, pistol)
TAC_GUNS = {gun = true, shotgun = true, rifle = true}
function TacIsGun(id)
	if not id or id == "" or id == "none" then return false end
	return TAC_GUNS[id] == true or string.find(id, "gun", 1, true) ~= nil or string.find(id, "rifle", 1, true) ~= nil
		or string.find(id, "pistol", 1, true) ~= nil
end
function TacHitsTick()
	TAC_HITBODY, TAC_BLASTS = {}, {}
	for i = 1, GetEventCount("projectilehit") do
		local sh = GetEvent("projectilehit", i)
		if sh and sh ~= 0 and IsHandleValid(sh) then TAC_HITBODY[GetShapeBody(sh)] = true end
	end
	for i = 1, GetEventCount("explosion") do
		local p, strength = GetEvent("explosion", i)
		if type(p) == "table" then TAC_BLASTS[#TAC_BLASTS + 1] = {pos = p, r = 0.5 + 1.0 * (tonumber(strength) or 1)} end
	end
	-- gunfire: bullets pass through these scaled shapes (run 17: no projectilehit for them), so a shot is traced here -
	-- a player who presses fire with a gun: their aim ray through one of our things before what it hits
	local items = nil
	for _, p in ipairs(GetAllPlayers()) do
		local tool = GetPlayerTool(p)
		if TacIsGun(tool) and InputPressed("usetool", p) and GetPlayerHealth(p) > 0 then
			items = items or FindBodies("tac", true)
			if #items > 0 then
				local e = GetPlayerEyeTransform(p)
				local hit, start, _, dir, _, hitDist = GetPlayerAimInfo(e.pos, 120, p)
				if start and dir then
					local far = (hit and hitDist and hitDist > 0) and hitDist or 120
					local spread = string.find(tool, "shotgun", 1, true) and 2.2 or 1
					for _, b in ipairs(items) do
						if IsHandleValid(b) then
							local mn, mx = GetBodyBounds(b)
							local c = VecLerp(mn, mx, 0.5)
							local w = VecSub(c, start)
							local t = VecDot(w, dir)
							if t > 0 and t < far + 0.4 then
								local r = math.max(0.15, 0.35 * VecLength(VecSub(mx, mn))) * spread   -- (a little forgiving)
								if VecLength(VecSub(w, VecScale(dir, t))) < r then TAC_HITBODY[b] = true end
							end
						end
					end
				end
			end
		end
	end
	local last = GetInt("inventory.melee.hit.last")
	if meleeSeen == nil or last < meleeSeen then meleeSeen = last end
	while meleeSeen < last do
		meleeSeen = meleeSeen + 1
		TAC_HITBODY[GetInt("inventory.melee.hit." .. (meleeSeen % 16) .. ".body")] = true
	end
end

TAC_VOX = {}                       -- body -> the most voxels it had
function TacBroken(body)
	if body == nil or body <= 0 then return false end
	if not IsHandleValid(body) then TAC_VOX[body] = nil return false end
	if TAC_HITBODY[body] then return true end
	if #TAC_BLASTS > 0 then
		local at = GetBodyTransform(body).pos
		for _, b in ipairs(TAC_BLASTS) do
			if VecLength(VecSub(at, b.pos)) < b.r then return true end
		end
	end
	if IsBodyBroken(body) then return true end
	local n = 0
	for _, sh in ipairs(GetBodyShapes(body)) do n = n + GetShapeVoxelCount(sh) end
	local most = TAC_VOX[body] or 0
	if n > most then TAC_VOX[body] = n return false end
	return most > 0 and n < most
end

-- (host) a key for a smoke cloud whose canister is gone (shot): negative, never a handle
local tacKey = 0
function TacNewKey()
	tacKey = tacKey - 1
	return tacKey
end

-- (client) when THIS machine first saw a thing the host made (a body handle): ages on a client are counted from here.
-- The host's GetTime is its own clock - a joined client's differs (the tenth in-game run: the client counted every
-- smoke cloud as over and drew none). A late joiner sees a thing as new: harmless.
TAC_SEEN = {}                      -- local player -> {body -> time} (one entry per machine; the offline mock runs both in one)
function TacSeen(b, now)
	local me = GetLocalPlayer()
	local m = TAC_SEEN[me] or {}
	TAC_SEEN[me] = m
	local t = m[b]
	if not t then
		t = now
		m[b] = t
	end
	return t
end

-- (client) the pack's sounds, loaded once
TAC_SND = {}
function TacSound(name, path)
	if not TAC_SND[name] then TAC_SND[name] = LoadSound(path) end
	return TAC_SND[name]
end
function TacLoop(name, path)
	if not TAC_SND[name] then TAC_SND[name] = LoadLoop(path) end
	return TAC_SND[name]
end

-- (client) the local player's own key: typing in Proximity Comms' chat is not a key press
function TacKey(key)
	local me = GetLocalPlayer()
	if GetBool("proxchat.typing." .. me) then return false end
	return InputPressed(key)
end
