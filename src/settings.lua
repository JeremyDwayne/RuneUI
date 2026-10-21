-- Saved settings: element positions and anchors, cooldown groups with their display settings and ability
-- lists, marker percents, appearance (HUD text, unit frame colours, border and size, bar texture, aura bars,
-- and whether the default target panel, buff bars and cast bar are hidden), edit mode
-- snapping, learned ability names and icons, aura names by icon, the aura row each buff icon belongs to, which
-- debuffs each debuff row tracks, the upkeep buffs kept up, and the order of each kind of aura icon.
-- Pure: reads and writes go through a store with get(key) and set(key, table), so specs use a fake.
local cooldowns = require("src/cooldowns")
local frames = require("src/frames")
local layout = require("src/layout")
local presets = require("src/presets")
local styling = require("src/style")

local settings = {}

-- Offsets from the bottom center of the game window with full first rows: 6 major, 6 rotation, 8 utility and 8
-- Defensives tiles, and no spender rows. The major group sits on top, the rotation row under it with a frame either
-- side, then the adrenaline bar, the cast bar, utility and the custom groups stack centred below.
settings.DEFAULT_POSITIONS = {
  major = { x = -110, y = -396, anchorX = 0.5, anchorY = 1 },
  rotation = { x = -140, y = -357, anchorX = 0.5, anchorY = 1 },
  player = { x = -390, y = -362, anchorX = 0.5, anchorY = 1 },
  target = { x = 140, y = -362, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -332, anchorX = 0.5, anchorY = 1 },
  castbar = { x = -139, y = -292, anchorX = 0.5, anchorY = 1 },
  utility = { x = -127, y = -254, anchorX = 0.5, anchorY = 1 },
  custom1 = { x = -127, y = -224, anchorX = 0.5, anchorY = 1 },
  custom2 = { x = -151, y = -188, anchorX = 0.5, anchorY = 1 },
  custom3 = { x = -151, y = -146, anchorX = 0.5, anchorY = 1 },
  custom4 = { x = -151, y = -104, anchorX = 0.5, anchorY = 1 },
  targetDebuffs = { x = 109, y = -395, anchorX = 0.5, anchorY = 1 },
  playerDebuffs = { x = -393, y = -395, anchorX = 0.5, anchorY = 1 },
  upkeepBuffs = { x = -393, y = -308, anchorX = 0.5, anchorY = 1 },
  combatBuffs = { x = -192, y = -445, anchorX = 0.5, anchorY = 1 },
}
-- src/layout anchors matching DEFAULT_POSITIONS with full rows: everything hangs off the major group, so
-- dragging it moves them all. Utility hangs under the cast bar, so spender rows below the adrenaline bar push it
-- and the custom groups down.
settings.DEFAULT_ANCHORS = {
  rotation = { target = "major", side = "bottom", align = "center", gap = 4, offset = 0 },
  player = { target = "rotation", side = "left", align = "center", gap = 0, offset = 0 },
  target = { target = "rotation", side = "right", align = "center", gap = 0, offset = 0 },
  resource = { target = "rotation", side = "bottom", align = "center", gap = 0, offset = 0 },
  castbar = { target = "resource", side = "bottom", align = "center", gap = 0, offset = 0 },
  utility = { target = "castbar", side = "bottom", align = "center", gap = 16, offset = 0 },
  custom1 = { target = "utility", side = "bottom", align = "center", gap = 0, offset = 0 },
  custom2 = { target = "custom1", side = "bottom", align = "center", gap = 6, offset = 0 },
  custom3 = { target = "custom2", side = "bottom", align = "center", gap = 6, offset = 0 },
  custom4 = { target = "custom3", side = "bottom", align = "center", gap = 6, offset = 0 },
  targetDebuffs = { target = "target", side = "top", align = "right", gap = 4, offset = 0 },
  playerDebuffs = { target = "player", side = "top", align = "left", gap = 4, offset = 0 },
  upkeepBuffs = { target = "player", side = "bottom", align = "left", gap = 2, offset = 0 },
  combatBuffs = { target = "major", side = "top", align = "center", gap = 10, offset = 0 },
}
-- The default major group's top sits this fraction of the window height above its bottom, below the
-- player's character, which the camera keeps near the middle of the window at any size.
local MAJOR_HEIGHT = 0.315
-- Saved positions and anchors from an older default layout are dropped once, on the first load of this one.
settings.LAYOUT_VERSION = 3
local DEFAULT_MARKERS = { threshold = 50, ultimate = 100 }
-- Bar fills: one flat colour, or a gradient from top to bottom or across the bar.
settings.TEXTURES = { "flat", "vertical", "horizontal" }
-- Points every HUD text role moves from its size, and unit frame, adrenaline bar and cast bar sizes.
settings.TEXT_STEP_MIN = -3
settings.TEXT_STEP_MAX = 6
settings.FRAME_WIDTH = { min = 180, max = 400 }
settings.FRAME_HEIGHT = { min = 30, max = 80 }
settings.BAR_WIDTH = { min = 120, max = 500 }
settings.BAR_HEIGHT = { min = 12, max = 40 }
settings.CAST_WIDTH = { min = 150, max = 500 }
settings.CAST_HEIGHT = { min = 14, max = 40 }

-- Combat styles a cooldown group keeps a separate ability list for, and the directions a group grows in.
settings.STYLES = { "necromancy", "magic", "ranged", "melee" }
settings.GROWS = { "up", "down", "left", "right" }
-- The most abilities one group list holds, the range of a group's icon size, and its title length.
settings.MAX_GROUP_KEYS = 20
settings.SIZE_MIN = 24
settings.SIZE_MAX = 56
local TITLE_MAX = 20
-- Built-in cooldown groups in list order, with their default title and display settings. A shared group
-- shows one ability list with every style; the others keep one list per style.
settings.GROUPS = {
  { name = "major", title = "Major", size = 35, perRow = 6, grow = "down", shared = false },
  { name = "rotation", title = "Rotation", size = 45, perRow = 6, grow = "down", shared = false },
  { name = "utility", title = "Utility", size = 30, perRow = 8, grow = "down", shared = true },
}
-- The first custom group a new install starts with, holding the defensive abilities.
local DEFENSIVES = { name = "custom1", title = "Defensives", size = 30, perRow = 8, grow = "down", shared = true }
-- Element names of the groups a player can add, in the order they fill, and a new one's display settings.
settings.CUSTOM_GROUPS = { "custom1", "custom2", "custom3", "custom4" }
local CUSTOM_DEFAULT = { size = 36, perRow = 8, grow = "down", shared = true }
-- Aura rows a buff icon can be sorted into.
local AURA_CATEGORIES = { combat = true, upkeep = true, hidden = true }
-- Saved keys of each debuff row's tracked choices, by kind.
local TRACKED_KEYS = { target = "trackedTarget", player = "trackedPlayer" }
-- Saved keys of each aura kind's icon order.
local ORDER_KEYS = { buffs = "orderBuffs", target = "orderTarget", player = "orderPlayer" }
-- The rule src/icons names auras by; saved names from an older rule are dropped once on load.
local NAMES_VERSION = 3
local POSITION_FIELDS = { "x", "y", "anchorX", "anchorY" }
-- The list a per-style group shows before any combat style is known.
local NO_KEYS = {}

-- PersistentDB hands numbers back as floats, so -427 returns as -427.0; whole numbers become integers again.
local function whole(n)
  return math.tointeger(n) or n
end

local function copyPosition(pos)
  if type(pos) ~= "table" then
    return nil
  end
  local copy = {}
  for _, field in ipairs(POSITION_FIELDS) do
    if type(pos[field]) ~= "number" then
      return nil
    end
    copy[field] = whole(pos[field])
  end
  return copy
end

local function copyAnchor(anchor)
  if type(anchor) ~= "table" or settings.DEFAULT_POSITIONS[anchor.target] == nil then
    return nil
  end
  local aligns = layout.ALIGNS[anchor.side]
  if aligns == nil or type(anchor.gap) ~= "number" or type(anchor.offset) ~= "number" then
    return nil
  end
  for _, align in ipairs(aligns) do
    if anchor.align == align then
      return {
        target = anchor.target,
        side = anchor.side,
        align = align,
        gap = whole(anchor.gap),
        offset = whole(anchor.offset),
      }
    end
  end
end

local function copyAnchors(saved)
  local anchors = {}
  for name in pairs(settings.DEFAULT_POSITIONS) do
    anchors[name] = copyAnchor(saved[name])
  end
  return anchors
end

-- Whether following targets from name leads back to name.
local function cyclic(anchors, name)
  local seen = {}
  local at = anchors[name]
  while at ~= nil and not seen[at.target] do
    if at.target == name then
      return true
    end
    seen[at.target] = true
    at = anchors[at.target]
  end
  return false
end

-- Saved anchors without malformed entries or cycles, or the defaults when none were ever saved. An element
-- with neither a saved anchor nor a saved position has never been placed, such as one added since anchors
-- were saved, so it takes its default anchor; removing an anchor saves a position.
local function readAnchors(saved, positions)
  if type(saved) ~= "table" then
    return copyAnchors(settings.DEFAULT_ANCHORS)
  end
  local anchors = copyAnchors(saved)
  for name, default in pairs(settings.DEFAULT_ANCHORS) do
    if saved[name] == nil and positions[name] == nil then
      anchors[name] = copyAnchor(default)
    end
  end
  local looped = {}
  for name in pairs(anchors) do
    looped[name] = cyclic(anchors, name)
  end
  for name, dropped in pairs(looped) do
    if dropped then
      anchors[name] = nil
    end
  end
  return anchors
end

local function stringsOnly(list)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  for _, key in ipairs(list) do
    if type(key) == "string" then
      out[#out + 1] = key
    end
  end
  return out
end

local function readLayout(saved)
  local positions = {}
  if type(saved) ~= "table" then
    return positions
  end
  for name in pairs(settings.DEFAULT_POSITIONS) do
    positions[name] = copyPosition(saved[name])
  end
  return positions
end

local function clamp(n, low, high)
  return math.max(low, math.min(high, n))
end

local function isGrow(value)
  for _, grow in ipairs(settings.GROWS) do
    if value == grow then
      return true
    end
  end
  return false
end

-- value cut to TITLE_MAX characters without surrounding spaces, or nil when that leaves nothing.
local function title(value)
  if type(value) ~= "string" then
    return nil
  end
  local cut = value:sub(1, TITLE_MAX):match("^%s*(.-)%s*$")
  if cut ~= "" then
    return cut
  end
end

-- A group record from saved, a stored table or nil, with default's title and display settings for anything
-- missing or malformed: { title, size, perRow, grow, shared, keys, styles = { [style] = { key } } }. keys is
-- the shared list.
local function readGroup(saved, default)
  saved = type(saved) == "table" and saved or {}
  local styles = type(saved.styles) == "table" and saved.styles or {}
  local group = {
    title = title(saved.title) or default.title,
    size = type(saved.size) == "number" and clamp(whole(saved.size), settings.SIZE_MIN, settings.SIZE_MAX)
      or default.size,
    perRow = type(saved.perRow) == "number" and clamp(whole(saved.perRow), 1, settings.MAX_GROUP_KEYS)
      or default.perRow,
    grow = isGrow(saved.grow) and saved.grow or default.grow,
    shared = default.shared,
    keys = stringsOnly(saved.keys),
    styles = {},
  }
  if type(saved.shared) == "boolean" then
    group.shared = saved.shared
  end
  for _, style in ipairs(settings.STYLES) do
    group.styles[style] = stringsOnly(styles[style])
  end
  return group
end

local function customDefault(name)
  local default = { title = "Group " .. name:match("%d+$") }
  for field, value in pairs(CUSTOM_DEFAULT) do
    default[field] = value
  end
  return default
end

local function indexOf(list, key)
  for i, k in ipairs(list) do
    if k == key then
      return i
    end
  end
end

local function append(list, key)
  if indexOf(list, key) == nil then
    list[#list + 1] = key
  end
end

-- Whether any list that shows with style holds key.
local function held(groups, key, style)
  for _, group in pairs(groups) do
    if indexOf(group.shared and group.keys or group.styles[style], key) ~= nil then
      return true
    end
  end
  return false
end

-- Whether any list held with any style holds key.
local function heldAnywhere(groups, key)
  for _, style in ipairs(settings.STYLES) do
    if held(groups, key, style) then
      return true
    end
  end
  return false
end

-- Fills each style whose per-style lists are all empty with its src/presets lists, an empty utility list with
-- the utility preset, and an unused first custom group with the Defensives preset, once each, skipping keys
-- another list already shows. seeded records which are done, so a list emptied or a group deleted on purpose
-- stays so. Returns whether anything was done.
local function seed(groups, seeded)
  local changed = false
  for _, style in ipairs(settings.STYLES) do
    if not seeded[style] then
      seeded[style], changed = true, true
      local empty = true
      for _, group in pairs(groups) do
        if #group.styles[style] > 0 then
          empty = false
        end
      end
      for name, keys in pairs(empty and presets.STYLES[style] or {}) do
        for _, key in ipairs(keys) do
          if not held(groups, key, style) then
            append(groups[name].styles[style], key)
          end
        end
      end
    end
  end
  if not seeded.utility then
    seeded.utility = true
    changed = true
    for _, key in ipairs(#groups.utility.keys == 0 and presets.UTILITY or {}) do
      if not heldAnywhere(groups, key) then
        append(groups.utility.keys, key)
      end
    end
  end
  if not seeded.defensives then
    seeded.defensives = true
    changed = true
    if groups[DEFENSIVES.name] == nil then
      local group = readGroup(nil, DEFENSIVES)
      for _, key in ipairs(presets.DEFENSIVES) do
        if not heldAnywhere(groups, key) then
          append(group.keys, key)
        end
      end
      groups[DEFENSIVES.name] = group
    end
  end
  return changed
end

-- Splits groups saved as { rotation, cooldowns } across the styles: each style's rotation and major take its
-- own abilities, weapon specials go to every style, and other style-free abilities to the shared utility.
local function migrateGroups(old, groups)
  for _, pair in ipairs({ { "rotation", "rotation" }, { "cooldowns", "major" } }) do
    local oldName = pair[1]
    local newName = pair[2]
    for _, key in ipairs(stringsOnly(old[oldName])) do
      local style = cooldowns.styleOf(key)
      if style ~= nil then
        append(groups[newName].styles[style], key)
      elseif key:match("^WEAPON_") then
        for _, s in ipairs(settings.STYLES) do
          append(groups[newName].styles[s], key)
        end
      else
        append(groups.utility.keys, key)
      end
    end
  end
end

-- { seeded = { [style, "utility" or "defensives"] = true }, groups = { [name] = group record } } from the saved
-- cooldownGroups, or from groups saved by an older version, then seeded from src/presets, and whether it
-- changed. Every built-in group is present; a custom one only once added.
local function readCooldownGroups(saved, old)
  local stored = type(saved) == "table" and type(saved.groups) == "table" and saved.groups or {}
  local groups = {}
  for _, default in ipairs(settings.GROUPS) do
    groups[default.name] = readGroup(stored[default.name], default)
  end
  for _, name in ipairs(settings.CUSTOM_GROUPS) do
    if type(stored[name]) == "table" then
      groups[name] = readGroup(stored[name], customDefault(name))
    end
  end
  local seeded = {}
  local savedSeeded = type(saved) == "table" and type(saved.seeded) == "table" and saved.seeded or {}
  for _, name in ipairs({ "utility", "defensives", table.unpack(settings.STYLES) }) do
    seeded[name] = savedSeeded[name] == true
  end
  local migrated = type(saved) ~= "table" and type(old) == "table"
  if migrated then
    migrateGroups(old, groups)
  end
  local changed = seed(groups, seeded)
  return { seeded = seeded, groups = groups }, migrated or changed
end

local function readMarkers(saved)
  local markers = {}
  for name, default in pairs(DEFAULT_MARKERS) do
    local value = type(saved) == "table" and saved[name] or nil
    markers[name] = type(value) == "number" and whole(value) or default
  end
  return markers
end

-- Whether value is a whole number from low to high.
local function wholeIn(value, low, high)
  value = type(value) == "number" and whole(value)
  return math.type(value) == "integer" and value >= low and value <= high
end

-- Checks a saved colour: an id from presets or a 0xRRGGBB number.
local function colour(list)
  return function(value)
    if type(value) == "string" then
      return styling.find(list, value) ~= nil
    end
    return wholeIn(value, 0, 0xFFFFFF)
  end
end

local function option(list)
  return function(value)
    return styling.find(list, value) ~= nil
  end
end

local function oneOf(list)
  return function(value)
    for _, known in ipairs(list) do
      if value == known then
        return true
      end
    end
    return false
  end
end

local function range(low, high)
  return function(value)
    return wholeIn(value, low, high)
  end
end

local function isBoolean(value)
  return type(value) == "boolean"
end

-- Each appearance field's default and the check a saved value must pass.
local APPEARANCE = {
  texture = { "flat", oneOf(settings.TEXTURES) },
  hideTargetPanel = { false, isBoolean },
  hideBuffBars = { false, isBoolean },
  hideCastBar = { true, isBoolean },
  auraBars = { false, isBoolean },
  font = { "museo", option(styling.FAMILIES) },
  textStep = { 0, range(settings.TEXT_STEP_MIN, settings.TEXT_STEP_MAX) },
  edge = { "shadow", option(styling.EDGES) },
  textColour = { "auto", option(styling.TEXT_COLOURS) },
  playerColour = { "runeui", colour(styling.PRESETS) },
  targetColour = { "runeui", colour(styling.PRESETS) },
  border = { "runeui", option(styling.BORDERS) },
  lifepoints = { "short", option(frames.LIFEPOINTS) },
  frameWidth = { 250, range(settings.FRAME_WIDTH.min, settings.FRAME_WIDTH.max) },
  frameHeight = { 55, range(settings.FRAME_HEIGHT.min, settings.FRAME_HEIGHT.max) },
  barWidth = { 278, range(settings.BAR_WIDTH.min, settings.BAR_WIDTH.max) },
  barHeight = { 20, range(settings.BAR_HEIGHT.min, settings.BAR_HEIGHT.max) },
  castWidth = { 278, range(settings.CAST_WIDTH.min, settings.CAST_WIDTH.max) },
  castHeight = { 22, range(settings.CAST_HEIGHT.min, settings.CAST_HEIGHT.max) },
  castMatchWidth = { false, isBoolean },
  castColour = { "ability", colour(styling.CAST_PRESETS) },
  castFont = {
    "hud",
    function(value)
      return value == "hud" or styling.find(styling.FAMILIES, value) ~= nil
    end,
  },
  spenders = { "below", option(styling.SPENDER_PLACES) },
  castTextSize = {
    "hud",
    function(value)
      return value == "hud"
        or wholeIn(value, styling.ROLES.body + settings.TEXT_STEP_MIN, styling.ROLES.body + settings.TEXT_STEP_MAX)
    end,
  },
}

-- A saved appearance field's value, or its default when unknown or malformed.
local function readField(field, value)
  local default = APPEARANCE[field][1]
  local valid = APPEARANCE[field][2]
  if not valid(value) then
    return default
  end
  return type(value) == "number" and whole(value) or value
end

local function readAppearance(saved)
  saved = type(saved) == "table" and saved or {}
  local appearance = {}
  for field in pairs(APPEARANCE) do
    appearance[field] = readField(field, saved[field])
  end
  return appearance
end

-- An icon map's key as the string of a whole number, a sprite id or minus an item id, or nil.
local function iconKey(key)
  local n = math.tointeger(tonumber(key))
  return n and tostring(n)
end

local function readDebuffs(saved)
  local debuffs = {}
  if type(saved) ~= "table" then
    return debuffs
  end
  for sprite, entry in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and type(entry) == "table" then
      if type(entry.name) == "string" then
        debuffs[key] = { name = entry.name, struct = math.tointeger(entry.struct) }
      elseif entry.unmatched == true then
        debuffs[key] = { unmatched = true }
      end
    end
  end
  return debuffs
end

-- A debuff kind's choices, { [tostring(sprite)] = true | false | "seen" }.
local function readTracked(saved)
  local out = {}
  if type(saved) ~= "table" then
    return out
  end
  for sprite, choice in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and (type(choice) == "boolean" or choice == "seen") then
      out[key] = choice
    end
  end
  return out
end

-- An icon order: a list of whole numbers, each once.
local function readOrder(saved)
  local out = {}
  local seen = {}
  if type(saved) ~= "table" then
    return out
  end
  for _, sprite in ipairs(saved) do
    local n = math.tointeger(sprite)
    if n ~= nil and not seen[n] then
      seen[n] = true
      out[#out + 1] = n
    end
  end
  return out
end

local function readKeepUp(saved)
  local out = {}
  if type(saved) ~= "table" then
    return out
  end
  for sprite, on in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and on == true then
      out[key] = true
    end
  end
  return out
end

local function readAuras(saved)
  local out = {}
  if type(saved) ~= "table" then
    return out
  end
  for sprite, category in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and AURA_CATEGORIES[category] then
      out[key] = category
    end
  end
  return out
end

local function readKnown(saved)
  local known = {}
  if type(saved) ~= "table" then
    return known
  end
  for key, info in pairs(saved) do
    if type(key) == "string" and type(info) == "table" then
      local icon = type(info.icon) == "number" and whole(info.icon) or nil
      known[key] = { name = type(info.name) == "string" and info.name or nil, icon = icon }
    end
  end
  return known
end

-- DEFAULT_POSITIONS raised or lowered together so the major group sits MAJOR_HEIGHT of windowHeight above the
-- bottom. With no windowHeight they are DEFAULT_POSITIONS as written.
local function defaultPositions(windowHeight)
  if windowHeight == nil then
    return settings.DEFAULT_POSITIONS
  end
  local shift = -math.floor(windowHeight * MAJOR_HEIGHT + 0.5) - settings.DEFAULT_POSITIONS.major.y
  local out = {}
  for name, pos in pairs(settings.DEFAULT_POSITIONS) do
    out[name] = { x = pos.x, y = pos.y + shift, anchorX = pos.anchorX, anchorY = pos.anchorY }
  end
  return out
end

-- Every appearance field at its default, the look of a HUD element before src/main gives it one.
function settings.defaultAppearance()
  return readAppearance(nil)
end

-- Loads saved settings from store, dropping unknown keys and malformed values. windowHeight, the game
-- window's height in UI units, places the default HUD; specs leave it out.
function settings.load(store, windowHeight)
  local defaults = defaultPositions(windowHeight)
  local positions = readLayout(store.get("layout"))
  local anchors = readAnchors(store.get("anchors"), positions)
  local version = store.get("version")
  if type(version) ~= "table" or version.layout ~= settings.LAYOUT_VERSION then
    positions = {}
    anchors = copyAnchors(settings.DEFAULT_ANCHORS)
    store.set("layout", positions)
    store.set("anchors", anchors)
    store.set("version", { layout = settings.LAYOUT_VERSION })
  end
  local savedEditMode = store.get("editMode")
  local editMode = { snap = type(savedEditMode) ~= "table" or savedEditMode.snap ~= false }
  local cooldownGroups, changed = readCooldownGroups(store.get("cooldownGroups"), store.get("groups"))
  local groups = cooldownGroups.groups
  local markers = readMarkers(store.get("markers"))
  local known = readKnown(store.get("known"))
  local appearance = readAppearance(store.get("appearance"))
  local debuffs = readDebuffs(store.get("debuffs"))
  local namesVersion = store.get("namesVersion")
  if type(namesVersion) ~= "table" or namesVersion.version ~= NAMES_VERSION then
    debuffs = {}
    store.set("debuffs", debuffs)
    store.set("namesVersion", { version = NAMES_VERSION })
  end
  local auras = readAuras(store.get("auras"))
  local tracked = {}
  for kind, key in pairs(TRACKED_KEYS) do
    tracked[kind] = readTracked(store.get(key))
  end
  local keepUp = readKeepUp(store.get("keepUp"))
  local orders = {}
  for kind, key in pairs(ORDER_KEYS) do
    orders[kind] = readOrder(store.get(key))
  end
  -- Counts changes to aura rows, tracking and order, so callers rebuild what depends on them only after one.
  local auraVersion = 0
  local appearanceVersion = 0

  local function saveGroups()
    store.set("cooldownGroups", cooldownGroups)
  end
  if changed then
    saveGroups()
  end

  -- The list of name's group that shows with style: its shared list, or style's own.
  local function listFor(name, style)
    local group = groups[name]
    return group.shared and group.keys or group.styles[style]
  end

  -- Takes key out of every list that shows with style.
  local function removeKey(key, style)
    for name in pairs(groups) do
      local list = listFor(name, style)
      local i = indexOf(list, key)
      if i ~= nil then
        table.remove(list, i)
      end
    end
  end

  local s = {}

  -- Every element's position, saved or default.
  function s.positions()
    local out = {}
    for name, default in pairs(defaults) do
      out[name] = positions[name] or default
    end
    return out
  end

  function s.setPosition(name, pos)
    positions[name] = copyPosition(pos)
    store.set("layout", positions)
  end

  -- Restores the default positions and anchors.
  function s.resetPositions()
    positions = {}
    anchors = copyAnchors(settings.DEFAULT_ANCHORS)
    store.set("layout", positions)
    store.set("anchors", anchors)
  end

  -- { [name] = src/layout anchor } for every anchored element.
  function s.anchors()
    return anchors
  end

  -- Anchors name by a src/layout anchor. The caller checks layout.canAnchor first.
  function s.setAnchor(name, anchor)
    anchors[name] = copyAnchor(anchor)
    store.set("anchors", anchors)
  end

  function s.removeAnchor(name)
    anchors[name] = nil
    store.set("anchors", anchors)
  end

  -- Whether edit mode snaps drags and draws its grid.
  function s.snap()
    return editMode.snap
  end

  function s.setSnap(on)
    editMode.snap = on
    store.set("editMode", editMode)
  end

  -- Names of the groups in use, built-in ones first, then custom ones in slot order.
  function s.groupNames()
    local names = {}
    for _, default in ipairs(settings.GROUPS) do
      names[#names + 1] = default.name
    end
    for _, name in ipairs(settings.CUSTOM_GROUPS) do
      if groups[name] ~= nil then
        names[#names + 1] = name
      end
    end
    return names
  end

  -- name's group as { title, size, perRow, grow, shared }, or nil for a custom group not in use. Read only.
  function s.group(name)
    return groups[name]
  end

  -- Saves one of name's display settings: size and perRow clamped to their ranges, grow one of settings.GROWS,
  -- shared a boolean, or a title cut to 20 characters and trimmed. Any other value changes nothing.
  function s.setGroup(name, field, value)
    local group = groups[name]
    if group == nil then
      return
    end
    if field == "size" and type(value) == "number" then
      group.size = clamp(value, settings.SIZE_MIN, settings.SIZE_MAX)
    elseif field == "perRow" and type(value) == "number" then
      group.perRow = clamp(value, 1, settings.MAX_GROUP_KEYS)
    elseif field == "grow" and isGrow(value) then
      group.grow = value
    elseif field == "shared" and type(value) == "boolean" then
      group.shared = value
    elseif field == "title" and title(value) ~= nil then
      group.title = title(value)
    else
      return
    end
    saveGroups()
  end

  -- Adds a custom group in the first free slot and returns its name, or nil when all are in use.
  function s.addGroup()
    for _, name in ipairs(settings.CUSTOM_GROUPS) do
      if groups[name] == nil then
        groups[name] = readGroup(nil, customDefault(name))
        saveGroups()
        return name
      end
    end
  end

  -- Deletes a custom group with its abilities. Built-in groups stay.
  function s.deleteGroup(name)
    if groups[name] == nil or indexOf(settings.CUSTOM_GROUPS, name) == nil then
      return
    end
    groups[name] = nil
    saveGroups()
  end

  -- The keys name's group shows with style, empty for a per-style group while style is nil, or nil when name
  -- is not in use. Read only.
  function s.keys(name, style)
    local group = groups[name]
    if group == nil then
      return nil
    end
    if not group.shared and style == nil then
      return NO_KEYS
    end
    return listFor(name, style)
  end

  -- Adds key to the end of name's list for style, taking it out of every other list that shows with style.
  -- Returns false, changing nothing, when that list is full.
  function s.add(name, style, key)
    local list = listFor(name, style)
    if indexOf(list, key) == nil and #list >= settings.MAX_GROUP_KEYS then
      return false
    end
    removeKey(key, style)
    table.insert(list, key)
    saveGroups()
    return true
  end

  -- Takes key out of every list that shows with style.
  function s.remove(key, style)
    removeKey(key, style)
    saveGroups()
  end

  -- Moves key to index within name's list for style.
  function s.move(key, name, style, index)
    local list = listFor(name, style)
    local from = indexOf(list, key)
    if from == nil then
      return
    end
    table.remove(list, from)
    table.insert(list, clamp(index, 1, #list + 1), key)
    saveGroups()
  end

  -- Swaps keys a and b within name's list for style.
  function s.swap(a, b, name, style)
    local list = listFor(name, style)
    local i = indexOf(list, a)
    local j = indexOf(list, b)
    if i == nil or j == nil then
      return
    end
    list[i], list[j] = b, a
    saveGroups()
  end

  function s.markers()
    return { threshold = markers.threshold, ultimate = markers.ultimate }
  end

  function s.setMarker(name, percent)
    markers[name] = math.max(0, math.min(100, percent))
    store.set("markers", markers)
  end

  -- { texture, hideTargetPanel, hideBuffBars, hideCastBar, auraBars, font, textStep, edge, textColour,
  -- playerColour, targetColour, border, lifepoints, frameWidth, frameHeight, barWidth, barHeight, castWidth,
  -- castHeight, castMatchWidth, castColour, castFont, castTextSize, spenders }. spenders is a src/style
  -- SPENDER_PLACES id. castFont and castTextSize are "hud" to
  -- follow the HUD text or a family id and a size in points. The game's own cast bar is
  -- hidden until chosen otherwise, since RuneUI draws one; auraBars draws a draining bar under each aura icon.
  -- Read-only.
  function s.appearance()
    return appearance
  end

  -- Saves one appearance field, reading a value it does not accept as the field's default.
  function s.setAppearance(field, value)
    appearance[field] = readField(field, value)
    appearanceVersion = appearanceVersion + 1
    store.set("appearance", appearance)
  end

  -- A number that changes with every appearance change.
  function s.appearanceVersion()
    return appearanceVersion
  end

  -- { [tostring(sprite)] = "combat" | "upkeep" | "hidden" }: the aura row each buff icon seen so far joins.
  function s.auras()
    return auras
  end

  -- Saves the category of a buff icon seen for the first time. No-op once the icon has one.
  function s.learnAura(sprite, category)
    local key = tostring(sprite)
    if auras[key] ~= nil then
      return
    end
    auras[key] = category
    auraVersion = auraVersion + 1
    store.set("auras", auras)
  end

  -- Moves a buff icon to another aura row.
  function s.setAuraCategory(sprite, category)
    auras[tostring(sprite)] = category
    auraVersion = auraVersion + 1
    store.set("auras", auras)
  end

  -- { [tostring(sprite)] = true | false | "seen" }: the debuffs of kind, "target" or "player", seen or chosen.
  function s.tracked(kind)
    return tracked[kind]
  end

  -- Lists a debuff of kind seen for the first time, with no choice. No-op once listed.
  function s.seeDebuff(kind, sprite)
    local key = tostring(sprite)
    if tracked[kind][key] ~= nil then
      return
    end
    tracked[kind][key] = "seen"
    auraVersion = auraVersion + 1
    store.set(TRACKED_KEYS[kind], tracked[kind])
  end

  function s.setTracked(kind, sprite, on)
    tracked[kind][tostring(sprite)] = on
    auraVersion = auraVersion + 1
    store.set(TRACKED_KEYS[kind], tracked[kind])
  end

  -- { buffs, target, player }: each kind's icons in the order sorted on the Buffs page.
  function s.orders()
    return orders
  end

  function s.setOrder(kind, list)
    orders[kind] = list
    auraVersion = auraVersion + 1
    store.set(ORDER_KEYS[kind], list)
  end

  -- A number that changes with every aura row, tracking or order change.
  function s.auraVersion()
    return auraVersion
  end

  -- { [tostring(sprite)] = true } for each upkeep buff that keeps a tile while missing.
  function s.keepUp()
    return keepUp
  end

  function s.setKeepUp(sprite, on)
    keepUp[tostring(sprite)] = on or nil
    store.set("keepUp", keepUp)
  end

  -- { [tostring(sprite)] = { name, struct } } for every aura icon src/icons has named, and
  -- { unmatched = true } for each one it found no struct for.
  function s.debuffs()
    return debuffs
  end

  -- Saves an aura icon's name and the id of the struct it came from, or with no name, that no struct matches
  -- it.
  function s.learnDebuff(sprite, name, struct)
    debuffs[tostring(sprite)] = name and { name = name, struct = math.tointeger(struct) } or { unmatched = true }
    store.set("debuffs", debuffs)
  end

  -- { [key] = { name, icon } } for every ability whose struct has been seen.
  function s.known()
    return known
  end

  function s.learn(key, name, icon)
    local info = known[key]
    if info ~= nil and info.name == name and info.icon == icon then
      return
    end
    known[key] = { name = name, icon = icon }
    store.set("known", known)
  end

  return s
end

return settings
