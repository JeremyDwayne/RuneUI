-- RuneUI: player frame, target frame, resource bar and cooldown groups drawn over the game.
-- Each server tick reads the client through src/adapter and redraws from the src/frames and
-- src/cooldowns models.
local adapter = require("src/adapter")
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local icons = require("src/icons")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

local saved = settings.load(adapter.store())

local root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local debuffNames = icons.index(saved.debuffs())
local tooltip = view.tooltip(root)
local elements = {
  player = view.playerFrame(root),
  target = view.targetFrame(root, tooltip, debuffNames.info),
  resource = view.resourceBar(root),
  rotation = view.cooldownGroup(root, view.TILE_STYLES.rotation, tooltip),
  cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns, tooltip),
}
tooltip.raise()
local tracker = cooldowns.tracker()
tracker.seed(saved.known())
-- Struct ids scanned per tick while a debuff icon is unnamed, about 48 seconds for a full scan.
local ICON_SCAN_BUDGET = 1000

Event.VarTransmit.Subscribe("cooldowns", function(e)
  tracker.onVar(adapter.varChange(e))
end)
Event.InventoryAdded.Subscribe("lantern", adapter.inventoryChanged)
Event.InventoryUpdated.Subscribe("lantern", adapter.inventoryChanged)

local function refresh()
  adapter.hideTargetPanel(saved.hideTargetPanel())
  for _, element in pairs(elements) do
    if element.setTexture ~= nil then element.setTexture(saved.texture()) end
  end
  elements.player.update(frames.player(adapter.playerReads()))
  local target = frames.target(adapter.targetReads())
  -- Asking for each debuff's name queues unnamed icons for the background scan.
  for _, sprite in ipairs(target.debuffs or {}) do debuffNames.info(sprite) end
  elements.target.update(target)
  elements.resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), saved.markers()))
  -- Until the first edit in the options window, groups fill by cooldown length as abilities fire.
  local groups = saved.groups() or tracker.defaultGroups()
  local keybinds = adapter.slotKeybinds()
  local accent = view.STYLE_COLOURS[tracker.style()]
  elements.rotation.update(tracker.tiles(groups.rotation, keybinds), accent)
  elements.cooldowns.update(tracker.tiles(groups.cooldowns, keybinds), accent)
end

local optionsWindow = options.create(root, {
  saved = saved, tracker = tracker, elements = elements, view = view, refresh = refresh,
})

Event.ServerLogic.Subscribe("refresh", function()
  local learned = tracker.onTick(adapter.justUsed)
  if learned ~= nil then saved.learn(learned.key, learned.name, learned.icon) end
  for _, found in ipairs(debuffNames.step(adapter.iconStruct, ICON_SCAN_BUDGET)) do
    saved.learnDebuff(found.sprite, found.name, found.info)
  end
  refresh()
end)
refresh()

function PluginShutdown()
  adapter.hideTargetPanel(false)
  optionsWindow.shutdown()
  for _, element in pairs(elements) do element.layer:Destroy() end
  tooltip.destroy()
end

log("loaded")
