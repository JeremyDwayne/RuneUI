-- RuneUI: player frame, target frame, resource bar, cast bar, cooldown groups and aura rows drawn over the
-- game. Each server tick reads the client through src/adapter and redraws from the src/frames, src/cooldowns,
-- src/channel and src/auras models. The cast bar and cooldown groups also redraw on the Logic tick after
-- their vars change, and count down on every Logic tick.
local adapter = require("src/adapter")
local auralists = require("src/auralists")
local auras = require("src/auras")
local channel = require("src/channel")
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local icons = require("src/icons")
local options = require("src/options")
local presets = require("src/presets")
local settings = require("src/settings")
local styling = require("src/style")
local view = require("src/view")

-- Game interfaces such as the bank draw over the game area, so the HUD sits under them. The options window
-- goes on the plugin layer above them. Both span the whole window.
local hud = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local saved = settings.load(adapter.store(), tonumber(hud.height))
local auraNames = icons.index(saved.debuffs(), {
  spriteName = adapter.spriteName, itemName = adapter.itemName, describe = adapter.structInfo,
})
local tooltip = view.tooltip(hud)
local elements = {
  player = view.playerFrame(hud),
  target = view.targetFrame(hud),
  resource = view.resourceBar(hud),
  castbar = view.castBar(hud),
}
-- Every cooldown group element, built-in then custom. A custom group not in use stays hidden.
local GROUP_NAMES = {}
for _, group in ipairs(settings.GROUPS) do GROUP_NAMES[#GROUP_NAMES + 1] = group.name end
for _, name in ipairs(settings.CUSTOM_GROUPS) do GROUP_NAMES[#GROUP_NAMES + 1] = name end
for _, name in ipairs(GROUP_NAMES) do elements[name] = view.cooldownGroup(hud, tooltip) end
for name, style in pairs(view.AURA_STYLES) do elements[name] = view.auraRow(hud, style, tooltip, auraNames.info) end
local tracker = cooldowns.tracker()
local channelTracker = channel.tracker()
local auraTracker = auras.tracker()
local optionsWindow
tracker.seed(presets.INFO)
tracker.seed(saved.known())
-- These vars send no change until they next differ, so their values at load seed the trackers.
tracker.onVar("COMBATV2_MAINHAND_STYLE", nil, adapter.playerVar("COMBATV2_MAINHAND_STYLE"))
channelTracker.seed(adapter.playerVar)
-- Each aura kind's sorted order as { [sprite] = position }, rebuilt only after a saved aura choice changes.
local auraRanks, ranksVersion = nil, nil
local function rank(kind)
  if ranksVersion ~= saved.auraVersion() then
    local choices = { target = saved.tracked("target"), player = saved.tracked("player") }
    auraRanks = auralists.ranks(auralists.groups(saved.auras(), choices, saved.orders()))
    ranksVersion = saved.auraVersion()
  end
  return auraRanks[kind]
end
-- What the aura rows show: tracked debuffs in their sorted order, and Keep up tiles while the player has a
-- target.
local auraFilters = {
  tracked = function(kind, sprite) return auralists.tracked(kind, saved.tracked(kind), sprite) end,
  keepUp = saved.keepUp(),
  hasTarget = false,
  rank = rank,
}
-- Struct ids scanned per tick while an aura icon is unnamed, about 48 seconds for a full scan.
local ICON_SCAN_BUDGET = 1000

Event.VarTransmit.Subscribe("cooldowns", function(e)
  local name, old, new = adapter.varChange(e)
  tracker.onVar(name, old, new)
  channelTracker.onVar(name, old, new)
end)
Event.Draw.Subscribe("targetPanel", adapter.keepTargetPanelHidden)
Event.Draw.Subscribe("buffBars", adapter.keepBuffBarsHidden)
Event.Draw.Subscribe("castBar", adapter.keepCastBarHidden)

-- Event.Logic runs 50 times a second, so each of its ticks is 0.02 s.
local LOGIC_SECONDS = 0.02
-- Logic ticks since the last server tick, and the action bar slots read on it.
local logicTicks, slots = 0, {}

-- Shows each group's tiles for the worn weapon's style. Returns whether a group's bounds changed.
local function updateGroups()
  local style, since = tracker.style(), logicTicks * LOGIC_SECONDS
  local moved = false
  for _, name in ipairs(GROUP_NAMES) do
    local element, group = elements[name], saved.group(name)
    element.setInUse(group ~= nil)
    if group ~= nil and element.configure(group) then moved = true end
    if element.update(tracker.tiles(saved.keys(name, style) or {}, slots), since) then moved = true end
  end
  return moved
end

-- Shows a channel or a cooldown change on the Logic tick after its vars arrive, and counts the cast bar and
-- cooling tiles down each tick. With nothing channelling or cooling it makes no client calls.
Event.Logic.Subscribe("hud", function()
  logicTicks = logicTicks + 1
  if channelTracker.changed() then
    channelTracker.read(adapter.iconStruct)
    elements.castbar.update(channelTracker.model())
  end
  elements.castbar.step(LOGIC_SECONDS)
  if tracker.changed() and updateGroups() then optionsWindow.placeAll() end
  local since = logicTicks * LOGIC_SECONDS
  for _, name in ipairs(GROUP_NAMES) do elements[name].step(since) end
end)
Event.InventoryAdded.Subscribe("lantern", adapter.inventoryChanged)
Event.InventoryUpdated.Subscribe("lantern", adapter.inventoryChanged)

-- The src/style look every element shows, rebuilt only after an appearance change or a weapon swap.
local look, lookVersion, lookStyle = nil, nil, nil

-- Gives every element the current look. Returns whether a unit frame's bounds changed.
local function restyle()
  local equipped = tracker.style()
  if look ~= nil and lookVersion == saved.appearanceVersion() and lookStyle == equipped then return false end
  look, lookVersion, lookStyle = styling.look(saved.appearance(), equipped), saved.appearanceVersion(), equipped
  return view.setLook(elements, look)
end

local function refresh()
  local appearance = saved.appearance()
  adapter.hideTargetPanel(appearance.hideTargetPanel)
  adapter.hideBuffBars(appearance.hideBuffBars)
  adapter.hideCastBar(appearance.hideCastBar)
  local moved = restyle()
  elements.player.update(frames.player(adapter.playerReads(), appearance.lifepoints))
  local target = frames.target(adapter.targetReads(), appearance.lifepoints)
  elements.target.update(target)
  elements.resource.update(frames.resource(adapter.resourceReads(frames.SPENDERS), saved.markers()))
  -- This redraw covers any change waiting for the next Logic tick.
  channelTracker.changed()
  tracker.changed()
  elements.castbar.update(channelTracker.model())
  slots = adapter.barSlots()
  if updateGroups() then moved = true end
  local bars = appearance.auraBars
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
  logicTicks = 0
  channelTracker.onTick()
  channelTracker.read(adapter.iconStruct)
  local learned = tracker.onTick(adapter.justUsed)
  if learned ~= nil then saved.learn(learned.key, learned.name, learned.icon) end
  local auraReads = adapter.auraReads()
  for _, found in ipairs(auraTracker.onTick(auraReads)) do saved.learnAura(found.sprite, found.category) end
  for _, read in ipairs(auraReads.debuffs) do saved.seeDebuff("player", read.sprite) end
  for _, found in ipairs(auraNames.step(adapter.iconStruct, ICON_SCAN_BUDGET)) do
    saved.learnDebuff(found.sprite, found.name, found.struct)
  end
  refresh()
end)
refresh()

function PluginShutdown()
  adapter.hideTargetPanel(false)
  adapter.hideBuffBars(false)
  adapter.hideCastBar(false)
  optionsWindow.shutdown()
  for _, element in pairs(elements) do element.layer:Destroy() end
  tooltip.destroy()
end

log("loaded")
