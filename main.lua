-- RuneUI: player frame, target frame, resource bar and cooldown groups drawn over the game.
-- Each server tick reads the client through src/adapter and redraws from the src/frames and
-- src/cooldowns models.
local adapter = require("src/adapter")
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

local saved = settings.load(adapter.store())

local root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local elements = {
  player = view.playerFrame(root),
  target = view.targetFrame(root),
  resource = view.resourceBar(root),
  rotation = view.cooldownGroup(root, view.TILE_STYLES.rotation),
  cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns),
}
local tracker = cooldowns.tracker()
tracker.seed(saved.known())

Event.VarTransmit.Subscribe("cooldowns", function(e)
  tracker.onVar(adapter.varChange(e))
end)

local function refresh()
  elements.player.update(frames.player(adapter.playerReads()))
  elements.target.update(frames.target(adapter.targetReads()))
  elements.resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), saved.markers()))
  -- Until the first edit in the options window, groups fill by cooldown length as abilities fire.
  local groups = saved.groups() or tracker.defaultGroups()
  local keybinds = adapter.slotKeybinds()
  elements.rotation.update(tracker.tiles(groups.rotation, keybinds))
  elements.cooldowns.update(tracker.tiles(groups.cooldowns, keybinds))
end

local optionsWindow = options.create(root, {
  saved = saved, tracker = tracker, elements = elements, view = view, refresh = refresh,
})

Event.ServerLogic.Subscribe("refresh", function()
  local learned = tracker.onTick(adapter.justUsed)
  if learned ~= nil then saved.learn(learned.key, learned.name, learned.icon) end
  refresh()
end)
refresh()

function PluginShutdown()
  optionsWindow.shutdown()
  for _, element in pairs(elements) do element.layer:Destroy() end
end

log("loaded")
