-- The tools in the hands (client, every player): the game's "script/toolanimation.lua" (included by main.lua) places a
-- held tool at its prefab's fp_ / tp_ poses with the hands on it - as the game's own snowball does (data/script/
-- snowball.lua: one ToolAnimator per player, ticked while they hold it). Without it the game drew every one of
-- these tools at the holder's head (the user: "the c4 looks stuck on the player's head when he equips it").

TacAnimators = {}

-- (client tick)
function TacAnimTick(dt)
	local live = {}
	for _, p in ipairs(GetAllPlayers()) do
		live[p] = true
		if TAC_BY_ID[GetPlayerTool(p)] then
			local a = TacAnimators[p]
			if not a then
				a = ToolAnimator()
				TacAnimators[p] = a
			end
			tickToolAnimator(a, dt, nil, p)
		end
	end
	for p in pairs(TacAnimators) do
		if not live[p] then TacAnimators[p] = nil end
	end
end
