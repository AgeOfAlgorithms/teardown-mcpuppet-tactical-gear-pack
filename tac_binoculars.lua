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
	-- the mask: one image, black with the two lenses clear (tools/make_bino_mask.py: 1600 x 800, drawn at the screen's
	-- height), black bars at the sides of a wider screen. (Two black rings, the first version, each covered the other
	-- lens: the whole view was black - the user, on the desert map.)
	local k = H / 800
	local iw = 1600 * k
	local x0 = (W - iw) / 2
	UiPush()
	UiColor(1, 1, 1, 1)
	UiTranslate(x0, 0)
	UiScale(k)
	UiImage("MOD/images/tac_bino_mask.png")
	UiPop()
	UiPush()
	UiColor(0, 0, 0, 1)
	if x0 > 0 then
		UiRect(x0 + 1, H)
		UiTranslate(W - x0 - 1, 0)
		UiRect(x0 + 1, H)
	end
	UiPop()
	-- reticle: a cross of mil dots, green
	UiPush()
	UiTranslate(W / 2, cy)
	UiAlign("center middle")
	UiColor(0.45, 1, 0.5, 0.75)
	UiRect(r * 0.9, 2)
	UiRect(2, r * 0.6)
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
