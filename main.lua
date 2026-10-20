-- RuneUI: player frame, target frame, resource bar and cooldown groups drawn over the game.
-- Each server tick reads the client through src/adapter and redraws from the src/frames models.
local adapter = require("src/adapter")
local frames = require("src/frames")
local view = require("src/view")

local MARKERS = { threshold = 50, ultimate = 100 }

-- Default positions, offset from the bottom centre of the game window.
local POSITIONS = {
  player = { x = -558, y = -74, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -176, anchorX = 0.5, anchorY = 1 },
}

local root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local player = view.playerFrame(root)
local resource = view.resourceBar(root)
view.place(player.layer, POSITIONS.player)
view.place(resource.layer, POSITIONS.resource)

local function refresh()
  player.update(frames.player(adapter.playerReads()))
  resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), MARKERS))
end

Event.ServerLogic.Subscribe("refresh", refresh)
refresh()

function PluginShutdown()
  player.layer:Destroy()
  resource.layer:Destroy()
end

log("loaded")
