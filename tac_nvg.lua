-- Night-vision goggles: worn in the head slot (the wear engine says so in inventory.worn.<me>), F (the flashlight
-- key) switches them on and off. On: the picture goes green and colourless, brighter, a light at the eye lights the dark,
-- a dark rim and faint scan lines. A flashbang through them hits harder (tac_throw.lua).

-- F (the flashlight key) switches them, not N (the user: N switches windows in Teardown): while a player wears them
-- the flashlight is off for them (TacNvgServerTick), and its key is ours
TAC_NVG_INPUT = "flashlight"

local on = false
local applied = nil      -- the picture's own settings while ours are on (post-processing keeps what is set: put back)
local PP = {"saturation", "colorbalance", "gamma", "bloom"}

local function ppApply(want)
	if want and not applied then
		applied = {}
		for _, k in ipairs(PP) do applied[k] = {GetPostProcessingProperty(k)} end
	elseif not want and applied then
		for _, k in ipairs(PP) do
			local v = applied[k]
			if v and v[1] then SetPostProcessingProperty(k, v[1], v[2], v[3]) end
		end
		applied = nil
	end
end

function TacNvgWorn()
	local w = " " .. GetString("inventory.worn." .. GetLocalPlayer()) .. " "
	return string.find(w, " " .. TAC_NVG .. " ", 1, true) ~= nil
end

function TacNvgOn()
	return on and TacNvgWorn() and GetPlayerHealth(GetLocalPlayer()) > 0
end

-- (client tick)
function TacNvgTick(dt)
	if not TacNvgWorn() then on = false ppApply(false) return end
	local fl = GetFlashlight(GetLocalPlayer())                        -- (worn: a flashlight that was on goes off -
	if fl and fl ~= 0 and IsLightActive(fl) then SetLightEnabled(fl, false) end   -- the user)
	if InputPressed(TAC_NVG_INPUT) and not GetBool("proxchat.typing." .. GetLocalPlayer()) then
		on = not on
		PlaySound(TacSound(on and "nvgon" or "nvgoff", on and "clickup.ogg" or "clickdown.ogg"),
			GetPlayerEyeTransform(GetLocalPlayer()).pos, 0.6, false, on and 1.6 or 1.2)
	end
	ppApply(TacNvgOn())
	if not TacNvgOn() then return end
	SetPostProcessingProperty("saturation", 0)
	SetPostProcessingProperty("colorbalance", 0.42, 1.45, 0.5)
	SetPostProcessingProperty("gamma", 0.62)
	SetPostProcessingProperty("bloom", 1.8)
	-- light: one at the eye (the near room), one ahead along the look (the far wall)
	local eye = GetPlayerEyeTransform(GetLocalPlayer())
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	PointLight(VecAdd(eye.pos, VecScale(fwd, 0.6)), 0.7, 1, 0.7, 6)
	QueryRejectPlayer(GetLocalPlayer())
	local hit, d = QueryRaycast(eye.pos, fwd, 40)
	local far = hit and math.max(1, d - 0.6) or 18
	PointLight(VecAdd(eye.pos, VecScale(fwd, far)), 0.7, 1, 0.7, 4 + far * 0.6)
end

-- (client draw) the tube's rim and scan lines
function TacNvgDraw()
	if not TacNvgOn() then return end
	local W, H = UiWidth(), UiHeight()
	UiPush()
	UiAlign("center middle")
	UiTranslate(W / 2, H / 2)
	local r = math.max(W, H) * 0.62
	for k = 0, 7 do                                                -- (a soft dark rim: rings growing darker outward)
		UiColor(0, 0.02, 0, 0.12 + 0.05 * k)
		UiCircleOutline(r + k * r * 0.06, r * 0.07)
	end
	UiPop()
	UiPush()
	UiColor(0, 0.05, 0, 0.08)
	local off = (GetTime() * 40) % 6
	for y = off, H, 6 do                                           -- scan lines
		UiPush()
		UiTranslate(0, y)
		UiRect(W, 1)
		UiPop()
	end
	UiPop()
	UiPush()
	UiTranslate(30, H - 40)
	UiFont("bold.ttf", 18)
	UiColor(0.5, 1, 0.55, 0.8)
	local key = GetString("options.input.keymap.flashlight")
	UiText("NV  [" .. (key ~= "" and string.upper(key) or "F") .. "]")
	UiPop()
end

-- (tests) switch them on or off without the key
function TacNvgForce(v) on = v == true end

-- (server tick) a player wearing the goggles has no flashlight - its key switches night vision (the flashlight would
-- light up and toggle too); back when they take them off. Written on a change and re-said every 2 s (not every tick:
-- a replicated value written each tick costs traffic)
local nvgNoLight, nvgAt = {}, 0
function TacNvgServerTick()
	local now = GetTime()
	local again = now >= nvgAt
	if again then nvgAt = now + 2 end
	local live = {}
	for _, p in ipairs(GetAllPlayers()) do
		live[p] = true
		local wears = string.find(" " .. GetString("inventory.wear." .. p) .. " ", " " .. TAC_NVG .. " ", 1, true) ~= nil
		if wears and (not nvgNoLight[p] or again) then
			SetPlayerParam("flashlightallowed", false, p)
			if not nvgNoLight[p] then                                    -- (just put on: a flashlight that was on goes off)
				local fl = GetFlashlight(p)
				if fl and fl ~= 0 then SetLightEnabled(fl, false) end
			end
			nvgNoLight[p] = true
		elseif not wears and nvgNoLight[p] then
			SetPlayerParam("flashlightallowed", true, p)
			nvgNoLight[p] = nil
		end
	end
	for p in pairs(nvgNoLight) do if not live[p] then nvgNoLight[p] = nil end end
end
