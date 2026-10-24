-- RuneUI: player frame, target frame, resource bar, cast bar, cooldown groups and aura rows drawn over the
-- game. Each server tick reads the client through src/adapter and redraws from the src/frames, src/cooldowns,
-- src/channel and src/auras models. The cast bar and cooldown groups also redraw on the Logic tick after
-- their vars change, and count down on every Logic tick.
local adapter = require("src/adapter")
local auralists = require("src/auralists")
local autohide = require("src/autohide")
local auras = require("src/auras")
local catalog = require("src/catalog")
local channel = require("src/channel")
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local gameui = require("src/gameui")
local icons = require("src/icons")
local options = require("src/options")
local presets = require("src/presets")
local settings = require("src/settings")
local styling = require("src/style")
local targeteffects = require("src/targeteffects")
local view = require("src/view")

-- Game interfaces such as the bank draw over the game area, so the HUD sits under them. The options window
-- goes on the plugin layer above them. Both span the whole window.
local hud = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local saved = settings.load(adapter.store(), tonumber(hud.height))
local auraNames = icons.index(catalog.names, {
  spriteName = adapter.spriteName,
  itemName = adapter.itemName,
  describe = adapter.structInfo,
})
local tooltip = view.tooltip(hud)
local elements = {
  player = view.playerFrame(hud),
  target = view.targetFrame(hud),
  resource = view.resourceBar(hud),
  castbar = view.castBar(hud),
}
-- Every cooldown group element, built-in then custom. A custom group not in use stays hidden.
local GROUP_NAMES = view.GROUP_NAMES
for _, name in ipairs(GROUP_NAMES) do
  elements[name] = view.cooldownGroup(hud, tooltip, adapter.abilityInfo)
end
for name, style in pairs(view.AURA_STYLES) do
  elements[name] = view.auraRow(hud, style, tooltip, auraNames.info)
end
-- The world map draws under the HUD's layer, so the HUD hides while it is open. Out of combat, the Appearance
-- page's setting fades or hides it.
view.holdable(elements)
local tracker = cooldowns.tracker()
local channelTracker = channel.tracker()
local auraTracker = auras.tracker()
local effectsTracker = targeteffects.tracker()
local optionsWindow
-- Whether the world map is open, COMBATV2_PLAYER_IS_IN_COMBAT as last read, nil while unread, and whether the
-- player has a target, which showHud draws the HUD from.
local mapOpen = false
local inCombat = nil
local hasTarget = false

-- Hides the HUD while the world map is open, and fades or hides it out of combat as src/autohide says. Writes
-- nothing while neither changes.
local function showHud()
  local hidden, alpha = autohide.state(saved.appearance(), inCombat, hasTarget, optionsWindow.configuring())
  view.hold(mapOpen or hidden)
  view.fade(alpha)
end
tracker.seed(presets.INFO)
tracker.seed(saved.known())
-- These vars send no change until they next differ, so their values at load seed the trackers.
tracker.onVar("COMBATV2_MAINHAND_STYLE", nil, adapter.playerVar("COMBATV2_MAINHAND_STYLE"))
channelTracker.seed(adapter.playerVar)
effectsTracker.seed(adapter.playerVar)
-- Each aura kind's sorted order as { [sprite] = position }, rebuilt only after a saved aura choice changes.
local auraRanks = nil
local ranksVersion = nil
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
  tracked = function(kind, sprite)
    return auralists.tracked(kind, saved.tracked(kind), sprite)
  end,
  keepUp = saved.keepUp(),
  hasTarget = false,
  rank = rank,
}

Event.VarTransmit.Subscribe("cooldowns", function(e)
  local name, old, new = adapter.varChange(e)
  -- WORLDMAP_FOCUS holds -1 while the world map is closed and a component id while it is open.
  if name == "WORLDMAP_FOCUS" then
    mapOpen = new ~= -1
    showHud()
  end
  tracker.onVar(name, old, new)
  channelTracker.onVar(name, old, new)
  effectsTracker.onVar(name, old, new)
end)
Event.Draw.Subscribe("gameui", gameui.onFrame)

-- Event.Logic runs 50 times a second, so each of its ticks is 0.02 s.
local LOGIC_SECONDS = 0.02
-- Logic ticks since the last server tick, and the action bar slots and spender rows read on it.
local logicTicks = 0
local slots = {}
local stacks = nil

-- Shows each group's tiles for the worn weapon's style, with the queued ability's tile marked, and runs the
-- resource bar's strip through the global cooldown. Returns whether a group's bounds changed.
local function updateGroups()
  local style = tracker.style()
  local queuedIcon = adapter.slotSprite(tracker.queued())
  local since = logicTicks * LOGIC_SECONDS
  elements.resource.setGlobal(since, tracker.globalCooldown())
  local moved = false
  for _, name in ipairs(GROUP_NAMES) do
    local element = elements[name]
    local group = saved.group(name)
    element.setInUse(group ~= nil)
    if group ~= nil and element.configure(group) then
      moved = true
    end
    if element.update(tracker.tiles(saved.keys(name, style) or {}, slots, stacks, queuedIcon), since) then
      moved = true
    end
  end
  return moved
end

-- Shows a channel, cooldown or queue change on the Logic tick after its vars arrive, and counts the cast bar and
-- cooling tiles down each tick, filling the strip through the global cooldown and running the queued tile's
-- border. With nothing channelling, cooling, queued or in the global cooldown it makes no client calls.
Event.Logic.Subscribe("hud", function()
  logicTicks = logicTicks + 1
  if channelTracker.changed() then
    channelTracker.read(adapter.iconStruct)
    elements.castbar.update(channelTracker.model())
  end
  elements.castbar.step(LOGIC_SECONDS)
  if tracker.changed() and updateGroups() then
    optionsWindow.placeAll()
  end
  local since = logicTicks * LOGIC_SECONDS
  elements.resource.step(since)
  for _, name in ipairs(GROUP_NAMES) do
    elements[name].step(since)
  end
end)
Event.InventoryAdded.Subscribe("lantern", adapter.inventoryChanged)
Event.InventoryUpdated.Subscribe("lantern", adapter.inventoryChanged)

-- The src/style look every element shows, rebuilt only after an appearance change or a weapon swap.
local look = nil
local lookVersion = nil
local lookStyle = nil

-- Gives every element the current look. Returns whether a unit frame's bounds changed.
local function restyle()
  local equipped = tracker.style()
  if look ~= nil and lookVersion == saved.appearanceVersion() and lookStyle == equipped then
    return false
  end
  look = styling.look(saved.appearance(), equipped)
  lookVersion = saved.appearanceVersion()
  lookStyle = equipped
  return view.setLook(elements, look)
end

-- Redraws the player frame, target frame and resource bar from the client. Returns the target model and
-- whether an element's bounds changed.
local function updateFrames(appearance)
  elements.player.update(frames.player(adapter.playerReads(), appearance.lifepoints))
  local targetReads = adapter.targetReads(effectsTracker.debuffs())
  local target = frames.target(targetReads, appearance.lifepoints)
  elements.target.update(target)
  effectsTracker.observe(targetReads.target, target.debuffs or {})
  local reads = adapter.resourceReads(frames.SPENDERS)
  reads.necromancy = tracker.style() == "necromancy"
  local resource = frames.resource(reads, saved.markers())
  stacks = resource.byAbility
  local moved = elements.resource.update(resource)
  if elements.player.showSpenders(resource.spenders) then
    moved = true
  end
  return target, moved
end

-- Redraws the cast bar and cooldown groups from the trackers and the action bars. Returns whether a group's
-- bounds changed.
local function updateCooldowns()
  -- This redraw covers any change waiting for the next Logic tick.
  channelTracker.changed()
  tracker.changed()
  elements.castbar.update(channelTracker.model())
  slots = adapter.barSlots()
  return updateGroups()
end

-- Redraws each aura row for the target shown. Returns whether a row's bounds changed.
local function updateAuras(target, bars)
  local targetDebuffs = target.debuffs or {}
  auraFilters.hasTarget = not target.hidden
  -- Listing each debuff seen puts it on the Buffs page; seeDebuff saves only a new one.
  for _, sprite in ipairs(targetDebuffs) do
    saved.seeDebuff("target", sprite)
  end
  local moved = false
  for name, models in pairs(auraTracker.rows(saved.auras(), targetDebuffs, auraFilters, effectsTracker.timers())) do
    if elements[name].update(models, bars) then
      moved = true
    end
  end
  return moved
end

-- Redraws the whole HUD from the client, each server tick and after a settings change.
local function refresh()
  local appearance = saved.appearance()
  gameui.apply(appearance)
  local moved = restyle()
  local target, framesMoved = updateFrames(appearance)
  moved = moved or framesMoved
  moved = updateCooldowns() or moved
  moved = updateAuras(target, appearance.auraBars) or moved
  hasTarget = not target.hidden
  showHud()
  -- Anchored elements follow an element whose shown bounds changed.
  if moved then
    optionsWindow.placeAll()
  end
  optionsWindow.redrawBuffs()
end

optionsWindow = options.create(top, {
  saved = saved,
  tracker = tracker,
  elements = elements,
  view = view,
  auraInfo = auraNames.info,
  describe = adapter.structInfo,
  refresh = refresh,
  configured = function()
    showHud()
  end,
})

Event.ServerLogic.Subscribe("refresh", function()
  logicTicks = 0
  channelTracker.onTick()
  effectsTracker.onTick(adapter.iconStruct)
  channelTracker.read(adapter.iconStruct)
  -- The var sends no changes, so it is read each tick, and only while the Out of combat setting uses it.
  inCombat = autohide.reads(saved.appearance()) and adapter.playerVar("COMBATV2_PLAYER_IS_IN_COMBAT") or nil
  local learned = tracker.onTick(adapter.justUsed)
  if learned ~= nil then
    saved.learn(learned.key, learned.name, learned.icon)
  end
  local auraReads = adapter.auraReads()
  for _, found in ipairs(auraTracker.onTick(auraReads)) do
    saved.learnAura(found.sprite, found.category)
  end
  for _, read in ipairs(auraReads.debuffs) do
    saved.seeDebuff("player", read.sprite)
  end
  refresh()
end)
refresh()

function PluginShutdown()
  gameui.restore()
  optionsWindow.shutdown()
  for _, element in pairs(elements) do
    element.layer:Destroy()
  end
  tooltip.destroy()
end

log("loaded")
