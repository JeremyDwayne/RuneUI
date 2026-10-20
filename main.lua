-- RuneUI: player frame, target frame, resource bar, cooldown groups and aura rows drawn over the game.
-- Each server tick reads the client through src/adapter and redraws from the src/frames, src/cooldowns and
-- src/auras models.
local adapter = require("src/adapter")
local auralists = require("src/auralists")
local auras = require("src/auras")
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local icons = require("src/icons")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

-- Game interfaces such as the bank draw over the game area, so the HUD sits under them. The options window
-- goes on the plugin layer above them. Both span the whole window.
local hud = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local saved = settings.load(adapter.store(), tonumber(hud.height))
local auraNames = icons.index(saved.debuffs(), adapter.spriteName)
local tooltip = view.tooltip(hud)
local elements = {
  player = view.playerFrame(hud),
  target = view.targetFrame(hud),
  resource = view.resourceBar(hud),
  rotation = view.cooldownGroup(hud, view.TILE_STYLES.rotation, tooltip),
  cooldowns = view.cooldownGroup(hud, view.TILE_STYLES.cooldowns, tooltip),
}
for name, style in pairs(view.AURA_STYLES) do elements[name] = view.auraRow(hud, style, tooltip, auraNames.info) end
local tracker = cooldowns.tracker()
local auraTracker = auras.tracker()
local optionsWindow
tracker.seed(saved.known())
-- What the aura rows show: tracked debuffs, and Keep up tiles while the player has a target.
local auraFilters = {
  tracked = function(kind, sprite) return auralists.tracked(kind, saved.tracked(kind), sprite) end,
  keepUp = saved.keepUp(),
  hasTarget = false,
}
-- Struct ids scanned per tick while an aura icon is unnamed, about 48 seconds for a full scan.
local ICON_SCAN_BUDGET = 1000

Event.VarTransmit.Subscribe("cooldowns", function(e)
  tracker.onVar(adapter.varChange(e))
end)
Event.Draw.Subscribe("targetPanel", adapter.keepTargetPanelHidden)
Event.Draw.Subscribe("buffBars", adapter.keepBuffBarsHidden)
Event.InventoryAdded.Subscribe("lantern", adapter.inventoryChanged)
Event.InventoryUpdated.Subscribe("lantern", adapter.inventoryChanged)

local function refresh()
  adapter.hideTargetPanel(saved.hideTargetPanel())
  adapter.hideBuffBars(saved.hideBuffBars())
  for _, element in pairs(elements) do
    if element.setTexture ~= nil then element.setTexture(saved.texture()) end
  end
  elements.player.update(frames.player(adapter.playerReads()))
  local target = frames.target(adapter.targetReads())
  elements.target.update(target)
  elements.resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), saved.markers()))
  -- Until the first edit in the options window, groups fill by cooldown length as abilities fire.
  local groups = saved.groups() or tracker.defaultGroups()
  local slots = adapter.barSlots()
  local accent = view.STYLE_COLOURS[tracker.style()]
  local rotationMoved = elements.rotation.update(tracker.tiles(groups.rotation, slots), accent)
  local moved = elements.cooldowns.update(tracker.tiles(groups.cooldowns, slots), accent) or rotationMoved
  local bars = saved.auraBars()
  auraFilters.hasTarget = not target.hidden
  -- Listing each debuff seen puts it on the Buffs page; seeDebuff saves only a new one.
  for _, sprite in ipairs(target.debuffs or {}) do saved.seeDebuff("target", sprite) end
  for name, models in pairs(auraTracker.rows(saved.auras(), target.debuffs or {}, auraFilters)) do
    -- Asking for each aura's name queues unnamed icons for the background scan.
    for _, model in ipairs(models) do auraNames.info(model.sprite) end
    if elements[name].update(models, bars) then moved = true end
  end
  -- Anchored elements follow a row whose shown tiles changed.
  if moved then optionsWindow.placeAll() end
  optionsWindow.redrawBuffs()
end

optionsWindow = options.create(top, {
  saved = saved, tracker = tracker, elements = elements, view = view, auraInfo = auraNames.info, refresh = refresh,
})

Event.ServerLogic.Subscribe("refresh", function()
  local learned = tracker.onTick(adapter.justUsed)
  if learned ~= nil then saved.learn(learned.key, learned.name, learned.icon) end
  local auraReads = adapter.auraReads()
  for _, found in ipairs(auraTracker.onTick(auraReads)) do saved.learnAura(found.sprite, found.category) end
  for _, read in ipairs(auraReads.debuffs) do saved.seeDebuff("player", read.sprite) end
  for _, found in ipairs(auraNames.step(adapter.iconStruct, ICON_SCAN_BUDGET)) do
    saved.learnDebuff(found.sprite, found.name, found.info)
  end
  refresh()
end)
refresh()

function PluginShutdown()
  adapter.hideTargetPanel(false)
  adapter.hideBuffBars(false)
  optionsWindow.shutdown()
  for _, element in pairs(elements) do element.layer:Destroy() end
  tooltip.destroy()
end

log("loaded")
