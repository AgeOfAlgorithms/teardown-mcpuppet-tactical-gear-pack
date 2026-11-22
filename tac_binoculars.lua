-- Binoculars (client only): held, LMB down looks through them - a narrow view from the eye (first person whatever the
-- camera), the two-lens mask, a mil-dot reticle and the range to what's in the middle.

TAC_BINO_FOV = 12

local zoomed = false
TacBinoForce = false              -- (tests: look through them without the button)

-- (client tick: the camera is set every frame while looking)
function TacBinoTick(dt)
	local me = GetLocalPlayer()
	local want = TacBinoForce or GetPlayerTool(me) == "tac_binoculars" and GetPlayerHealth(me) > 0 and InputDown("usetool")
		and not GetBool("proxchat.typing." .. me)
	if want ~= zoomed then
		zoomed = want
		PlaySound(TacSound("scope", "tools/scope0.ogg"), GetPlayerEyeTransform(me).pos, 0.5, false, want and 1.1 or 0.9)
	end
	if zoomed then
		local eye = GetPlayerEyeTransform(me)
		local cam = GetPlayerCameraTransform(me)
		local fwd = TransformToParentVec(cam, Vec(0, 0, -1))
		SetCameraTransform(Transform(VecAdd(eye.pos, VecScale(fwd, 0.25)), cam.rot), TAC_BINO_FOV)
	end
end

function TacBinoZoomed() return zoomed end

-- (client draw)
function TacBinoDraw()
	if not zoomed then return end
	local W, H = UiWidth(), UiHeight()
	local r = H * 0.42
	local cx1, cx2, cy = W / 2 - r * 0.62, W / 2 + r * 0.62, H / 2
	UiPush()
	UiColor(0, 0, 0, 1)
	-- the mask: black everywhere but the two lenses (thick rings round each, bars above, below and at the sides)
	for _, cx in ipairs({cx1, cx2}) do
		UiPush()
		UiTranslate(cx, cy)
		UiAlign("center middle")
		UiCircleOutline(r + W, W * 2)
		UiPop()
	end
	UiPush() UiTranslate(W / 2, cy - r * 0.9) UiAlign("center bottom") UiRect(r * 0.5, H) UiPop()   -- (the bridge's gaps)
	UiPush() UiTranslate(W / 2, cy + r * 0.9) UiAlign("center top") UiRect(r * 0.5, H) UiPop()
	UiPop()
	-- reticle: a cross of mil dots, green
	UiPush()
	UiTranslate(W / 2, cy)
	UiAlign("center middle")
	UiColor(0.45, 1, 0.5, 0.75)
	UiRect(r * 0.9, 1)
	UiRect(1, r * 0.6)
	for k = -4, 4 do
		if k ~= 0 then
			UiPush() UiTranslate(k * r * 0.1, 0) UiCircle(2) UiPop()
			UiPush() UiTranslate(0, k * r * 0.07) UiCircle(2) UiPop()
		end
	end
	-- the range finder
	local me = GetLocalPlayer()
	local cam = GetPlayerCameraTransform(me)
	QueryRejectPlayer(me)
	local hit, d = QueryRaycast(cam.pos, TransformToParentVec(cam, Vec(0, 0, -1)), 400)
	UiTranslate(0, r * 0.75)
	UiFont("bold.ttf", 22)
	UiText(hit and string.format("%03d m", math.floor(d + 0.5)) or "--- m")
	UiPop()
end
