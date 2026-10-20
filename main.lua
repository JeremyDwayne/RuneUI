-- RuneUI: player frame, target frame, resource bar and cooldown groups drawn over the game.
-- Each server tick reads the client through src/adapter and redraws from the src/frames and
-- src/cooldowns models.
local adapter = require("src/adapter")
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local view = require("src/view")

local MARKERS = { threshold = 50, ultimate = 100 }

-- Default positions, offset from the bottom centre of the game window, clear of the native bottom panel.
local POSITIONS = {
  player = { x = -558, y = -394, anchorX = 0.5, anchorY = 1 },
  target = { x = 258, y = -424, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -496, anchorX = 0.5, anchorY = 1 },
  rotation = { x = -286, y = -396, anchorX = 0.5, anchorY = 1 },
  cooldowns = { x = -139, y = -552, anchorX = 0.5, anchorY = 1 },
}

local root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local elements = {
  player = view.playerFrame(root),
  target = view.targetFrame(root),
  resource = view.resourceBar(root),
  rotation = view.cooldownGroup(root, view.TILE_STYLES.rotation),
  cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns),
}
for name, element in pairs(elements) do view.place(element.layer, POSITIONS[name]) end

local tracker = cooldowns.tracker()

Event.VarTransmit.Subscribe("cooldowns", function(e)
  tracker.onVar(adapter.varChange(e))
end)

local function refresh()
  elements.player.update(frames.player(adapter.playerReads()))
  elements.target.update(frames.target(adapter.targetReads()))
  elements.resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), MARKERS))
  -- Until the settings panel lets you pick abilities, groups fill by cooldown length as abilities fire.
  local groups = tracker.defaultGroups()
  local keybinds = adapter.slotKeybinds()
  elements.rotation.update(tracker.tiles(groups.rotation, keybinds))
  elements.cooldowns.update(tracker.tiles(groups.cooldowns, keybinds))
end

Event.ServerLogic.Subscribe("refresh", function()
  tracker.onTick(adapter.justUsed)
  refresh()
end)
refresh()

function PluginShutdown()
  for _, element in pairs(elements) do element.layer:Destroy() end
end

log("loaded")
