#version 2
-- McPuppet Tactical Gear Pack Vol 1: binoculars, a motion sensor, night-vision goggles, glowsticks, flashbangs, smoke
-- grenades, C4 with a detonator, a claymore and a wire trap - items of the McPuppet Inventory System (declared through
-- inventory.tools.*, the goggles through inventory_api.lua). Without the Inventory mod they are plain game tools nobody
-- is handed. Each part has its own file; they share globals only (tac_common.lua).
#include "script/toolanimation.lua"
#include "inventory_api.lua"
#include "tac_common.lua"
#include "tac_throw.lua"
#include "tac_place.lua"
#include "tac_sensor.lua"
#include "tac_nvg.lua"
#include "tac_binoculars.lua"
#include "tac_anim.lua"
#include "tac_villagers.lua"

TacClothing()

function server.init()
	TacRegister()
	TacRegisterTools()
	TacThrowInit()
	TacPlaceInit()
	TacVillagersInit()
end

function server.tick(dt)
	TacHitsTick()
	TacThrowTick(dt)
	TacPlaceTick(dt)
	TacVillagersTick()
end

function server.update(dt)
	TacProjTick(dt)
end

function client.init()
	TacRegister()
end

-- (the host's events: sounds, the flash, the smoke starting)
function client.tacEvent(kind, x, y, z, v)
	local pos = Vec(x, y, z)
	TacThrowEvent(kind, pos, v)
	TacPlaceEvent(kind, pos, v)
end

function client.tick(dt)
	InventoryClientTick()
	TacAnimTick(dt)
	TacThrowClientTick(dt)
	TacPlaceClientTick(dt)
	TacSensorTick(dt)
	TacNvgTick(dt)
	TacBinoTick(dt)
end

function client.draw()
	TacNvgDraw()
	TacSensorDraw()
	TacBinoDraw()
	TacThrowDraw()
end
