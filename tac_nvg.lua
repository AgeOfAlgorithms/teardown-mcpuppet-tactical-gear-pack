-- Night-vision goggles (client only): worn in the head slot (the wear engine says so in inventory.worn.<me>), N
-- switches them on and off. On: the picture goes green and colourless, brighter, a light at the eye lights the dark,
-- a dark rim and faint scan lines. A flashbang through them hits harder (tac_throw.lua).

TAC_NVG_KEY = "n"

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
	if TacKey(TAC_NVG_KEY) then
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
	UiText("NV  [" .. string.upper(TAC_NVG_KEY) .. "]")
	UiPop()
end

-- (tests) switch them on or off without the key
function TacNvgForce(v) on = v == true end
