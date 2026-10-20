-- RuneUI: player frame, target frame, resource bar and cooldown groups drawn over the game.
-- Each server tick reads the client through src/adapter and redraws from the src/frames models.
local adapter = require("src/adapter")
local frames = require("src/frames")
local view = require("src/view")

local MARKERS = { threshold = 50, ultimate = 100 }

-- Default positions, offset from the bottom centre of the game window.
local POSITIONS = {
  player = { x = -558, y = -74, anchorX = 0.5, anchorY = 1 },
  target = { x = 258, y = -104, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -176, anchorX = 0.5, anchorY = 1 },
}

local root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local elements = {
  player = view.playerFrame(root),
  target = view.targetFrame(root),
  resource = view.resourceBar(root),
}
for name, element in pairs(elements) do view.place(element.layer, POSITIONS[name]) end

local function refresh()
  elements.player.update(frames.player(adapter.playerReads()))
  elements.target.update(frames.target(adapter.targetReads()))
  elements.resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), MARKERS))
end

Event.ServerLogic.Subscribe("refresh", refresh)
refresh()

function PluginShutdown()
  for _, element in pairs(elements) do element.layer:Destroy() end
end

log("loaded")
