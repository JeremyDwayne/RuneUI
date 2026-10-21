-- Saved settings: element positions and anchors, cooldown groups, marker percents, appearance (bar texture,
-- aura bars, and whether the default target panel and buff bars are hidden), edit mode snapping, learned
-- ability names and icons, aura names by icon, the aura row each buff icon belongs to, which debuffs each
-- debuff row tracks, the upkeep buffs kept up, and the order of each kind of aura icon.
-- Pure: reads and writes go through a store with get(key) and set(key, table), so specs use a fake.
local layout = require("src/layout")

local settings = {}

-- Offsets from the bottom center of the game window with a full rotation row. The frames sit flush either
-- side of the rotation row with their bottoms level, and the bars stack flush and centered above it.
settings.DEFAULT_POSITIONS = {
  player = { x = -469, y = -404, anchorX = 0.5, anchorY = 1 },
  target = { x = 219, y = -404, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -443, anchorX = 0.5, anchorY = 1 },
  rotation = { x = -219, y = -396, anchorX = 0.5, anchorY = 1 },
  cooldowns = { x = -189, y = -484, anchorX = 0.5, anchorY = 1 },
  targetDebuffs = { x = 188, y = -437, anchorX = 0.5, anchorY = 1 },
  playerDebuffs = { x = -472, y = -437, anchorX = 0.5, anchorY = 1 },
  upkeepBuffs = { x = -472, y = -350, anchorX = 0.5, anchorY = 1 },
  combatBuffs = { x = -192, y = -529, anchorX = 0.5, anchorY = 1 },
}
-- src/layout anchors that keep the frames beside the rotation row, the bars stacked above it, and the aura
-- rows on the frames and above the cooldowns row, matching DEFAULT_POSITIONS with full rows. Dragging the
-- rotation row moves them all.
settings.DEFAULT_ANCHORS = {
  player = { target = "rotation", side = "left", align = "bottom", gap = 0, offset = 0 },
  target = { target = "rotation", side = "right", align = "bottom", gap = 0, offset = 0 },
  resource = { target = "rotation", side = "top", align = "center", gap = 0, offset = 0 },
  cooldowns = { target = "resource", side = "top", align = "center", gap = 0, offset = 0 },
  targetDebuffs = { target = "target", side = "top", align = "right", gap = 4, offset = 0 },
  playerDebuffs = { target = "player", side = "top", align = "left", gap = 4, offset = 0 },
  upkeepBuffs = { target = "player", side = "bottom", align = "left", gap = 2, offset = 0 },
  combatBuffs = { target = "cooldowns", side = "top", align = "center", gap = 6, offset = 0 },
}
-- The default rotation row's top sits this fraction of the window height above its bottom, below the
-- player's character, which the camera keeps near the middle of the window at any size.
local ROTATION_HEIGHT = 0.315
local DEFAULT_MARKERS = { threshold = 50, ultimate = 100 }
-- Bar fills: one flat colour, or a gradient from top to bottom or across the bar.
settings.TEXTURES = { "flat", "vertical", "horizontal" }
local GROUP_NAMES = { "rotation", "cooldowns" }
-- Aura rows a buff icon can be sorted into.
local AURA_CATEGORIES = { combat = true, upkeep = true, hidden = true }
-- Saved keys of each debuff row's tracked choices, by kind.
local TRACKED_KEYS = { target = "trackedTarget", player = "trackedPlayer" }
-- Saved keys of each aura kind's icon order.
local ORDER_KEYS = { buffs = "orderBuffs", target = "orderTarget", player = "orderPlayer" }
-- The rule src/icons names auras by; saved names from an older rule are dropped once on load.
local NAMES_VERSION = 3
local POSITION_FIELDS = { "x", "y", "anchorX", "anchorY" }

-- PersistentDB hands numbers back as floats, so -427 returns as -427.0; whole numbers become integers again.
local function whole(n)
  return math.tointeger(n) or n
end

local function copyPosition(pos)
  if type(pos) ~= "table" then return nil end
  local copy = {}
  for _, field in ipairs(POSITION_FIELDS) do
    if type(pos[field]) ~= "number" then return nil end
    copy[field] = whole(pos[field])
  end
  return copy
end

local function copyAnchor(anchor)
  if type(anchor) ~= "table" or settings.DEFAULT_POSITIONS[anchor.target] == nil then return nil end
  local aligns = layout.ALIGNS[anchor.side]
  if aligns == nil or type(anchor.gap) ~= "number" or type(anchor.offset) ~= "number" then return nil end
  for _, align in ipairs(aligns) do
    if anchor.align == align then
      return { target = anchor.target, side = anchor.side, align = align, gap = whole(anchor.gap),
        offset = whole(anchor.offset) }
    end
  end
end

local function copyAnchors(saved)
  local anchors = {}
  for name in pairs(settings.DEFAULT_POSITIONS) do anchors[name] = copyAnchor(saved[name]) end
  return anchors
end

-- Whether following targets from name leads back to name.
local function cyclic(anchors, name)
  local seen, at = {}, anchors[name]
  while at ~= nil and not seen[at.target] do
    if at.target == name then return true end
    seen[at.target] = true
    at = anchors[at.target]
  end
  return false
end

-- Saved anchors without malformed entries or cycles, or the defaults when none were ever saved. An element
-- with neither a saved anchor nor a saved position has never been placed, such as one added since anchors
-- were saved, so it takes its default anchor; removing an anchor saves a position.
local function readAnchors(saved, positions)
  if type(saved) ~= "table" then return copyAnchors(settings.DEFAULT_ANCHORS) end
  local anchors = copyAnchors(saved)
  for name, default in pairs(settings.DEFAULT_ANCHORS) do
    if saved[name] == nil and positions[name] == nil then anchors[name] = copyAnchor(default) end
  end
  local looped = {}
  for name in pairs(anchors) do looped[name] = cyclic(anchors, name) end
  for name, dropped in pairs(looped) do
    if dropped then anchors[name] = nil end
  end
  return anchors
end

local function stringsOnly(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, key in ipairs(list) do
    if type(key) == "string" then out[#out + 1] = key end
  end
  return out
end

local function readLayout(saved)
  local positions = {}
  if type(saved) ~= "table" then return positions end
  for name in pairs(settings.DEFAULT_POSITIONS) do positions[name] = copyPosition(saved[name]) end
  return positions
end

local function readGroups(saved)
  if type(saved) ~= "table" then return nil end
  local groups = {}
  for _, name in ipairs(GROUP_NAMES) do groups[name] = stringsOnly(saved[name]) end
  return groups
end

local function readMarkers(saved)
  local markers = {}
  for name, default in pairs(DEFAULT_MARKERS) do
    local value = type(saved) == "table" and saved[name] or nil
    markers[name] = type(value) == "number" and whole(value) or default
  end
  return markers
end

local function readAppearance(saved)
  saved = type(saved) == "table" and saved or {}
  local appearance = {
    texture = "flat",
    hideTargetPanel = saved.hideTargetPanel == true,
    hideBuffBars = saved.hideBuffBars == true,
    auraBars = saved.auraBars == true,
  }
  for _, known in ipairs(settings.TEXTURES) do
    if saved.texture == known then appearance.texture = known end
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
  if type(saved) ~= "table" then return debuffs end
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
  if type(saved) ~= "table" then return out end
  for sprite, choice in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and (type(choice) == "boolean" or choice == "seen") then out[key] = choice end
  end
  return out
end

-- An icon order: a list of whole numbers, each once.
local function readOrder(saved)
  local out, seen = {}, {}
  if type(saved) ~= "table" then return out end
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
  if type(saved) ~= "table" then return out end
  for sprite, on in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and on == true then out[key] = true end
  end
  return out
end

local function readAuras(saved)
  local out = {}
  if type(saved) ~= "table" then return out end
  for sprite, category in pairs(saved) do
    local key = iconKey(sprite)
    if key ~= nil and AURA_CATEGORIES[category] then out[key] = category end
  end
  return out
end

local function readKnown(saved)
  local known = {}
  if type(saved) ~= "table" then return known end
  for key, info in pairs(saved) do
    if type(key) == "string" and type(info) == "table" then
      local icon = type(info.icon) == "number" and whole(info.icon) or nil
      known[key] = { name = type(info.name) == "string" and info.name or nil, icon = icon }
    end
  end
  return known
end

-- Group name and index of key, or nil.
local function find(groups, key)
  for _, name in ipairs(GROUP_NAMES) do
    for i, k in ipairs(groups[name]) do
      if k == key then return name, i end
    end
  end
end

-- DEFAULT_POSITIONS raised or lowered together so the rotation row sits ROTATION_HEIGHT of windowHeight
-- above the bottom. With no windowHeight they are DEFAULT_POSITIONS as written.
local function defaultPositions(windowHeight)
  if windowHeight == nil then return settings.DEFAULT_POSITIONS end
  local shift = -math.floor(windowHeight * ROTATION_HEIGHT + 0.5) - settings.DEFAULT_POSITIONS.rotation.y
  local out = {}
  for name, pos in pairs(settings.DEFAULT_POSITIONS) do
    out[name] = { x = pos.x, y = pos.y + shift, anchorX = pos.anchorX, anchorY = pos.anchorY }
  end
  return out
end

-- Loads saved settings from store, dropping unknown keys and malformed values. windowHeight, the game
-- window's height in UI units, places the default HUD; specs leave it out.
function settings.load(store, windowHeight)
  local defaults = defaultPositions(windowHeight)
  local positions = readLayout(store.get("layout"))
  local anchors = readAnchors(store.get("anchors"), positions)
  local savedEditMode = store.get("editMode")
  local editMode = { snap = type(savedEditMode) ~= "table" or savedEditMode.snap ~= false }
  local groups = readGroups(store.get("groups"))
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
  for kind, key in pairs(TRACKED_KEYS) do tracked[kind] = readTracked(store.get(key)) end
  local keepUp = readKeepUp(store.get("keepUp"))
  local orders = {}
  for kind, key in pairs(ORDER_KEYS) do orders[kind] = readOrder(store.get(key)) end
  -- Counts changes to aura rows, tracking and order, so callers rebuild what depends on them only after one.
  local auraVersion = 0

  local function saveGroups() store.set("groups", groups) end

  local s = {}

  -- Every element's position, saved or default.
  function s.positions()
    local out = {}
    for name, default in pairs(defaults) do out[name] = positions[name] or default end
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

  -- { rotation = { key }, cooldowns = { key } }, or nil while groups fill automatically.
  function s.groups()
    return groups
  end

  -- Saves the automatically filled groups as the user's own, before their first edit. No-op once saved.
  function s.adopt(current)
    if groups ~= nil then return end
    groups = readGroups(current)
    saveGroups()
  end

  function s.add(groupName, key)
    s.remove(key)
    table.insert(groups[groupName], key)
    saveGroups()
  end

  function s.remove(key)
    local name, i = find(groups, key)
    if name ~= nil then table.remove(groups[name], i) end
    saveGroups()
  end

  -- Inserts key at index in groupName, taking it out of wherever it was.
  function s.move(key, groupName, index)
    s.remove(key)
    local list = groups[groupName]
    table.insert(list, math.max(1, math.min(index, #list + 1)), key)
    saveGroups()
  end

  function s.swap(a, b)
    local groupA, indexA = find(groups, a)
    local groupB, indexB = find(groups, b)
    if groupA == nil or groupB == nil then return end
    groups[groupA][indexA], groups[groupB][indexB] = b, a
    saveGroups()
  end

  function s.markers()
    return { threshold = markers.threshold, ultimate = markers.ultimate }
  end

  function s.setMarker(name, percent)
    markers[name] = math.max(0, math.min(100, percent))
    store.set("markers", markers)
  end

  function s.texture()
    return appearance.texture
  end

  -- texture is one of settings.TEXTURES.
  function s.setTexture(value)
    appearance.texture = value
    store.set("appearance", appearance)
  end

  function s.hideTargetPanel()
    return appearance.hideTargetPanel
  end

  function s.setHideTargetPanel(hidden)
    appearance.hideTargetPanel = hidden
    store.set("appearance", appearance)
  end

  function s.hideBuffBars()
    return appearance.hideBuffBars
  end

  function s.setHideBuffBars(hidden)
    appearance.hideBuffBars = hidden
    store.set("appearance", appearance)
  end

  -- Whether aura icons draw a draining bar under them.
  function s.auraBars()
    return appearance.auraBars
  end

  function s.setAuraBars(on)
    appearance.auraBars = on
    store.set("appearance", appearance)
  end

  -- { [tostring(sprite)] = "combat" | "upkeep" | "hidden" }: the aura row each buff icon seen so far joins.
  function s.auras()
    return auras
  end

  -- Saves the category of a buff icon seen for the first time. No-op once the icon has one.
  function s.learnAura(sprite, category)
    local key = tostring(sprite)
    if auras[key] ~= nil then return end
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
    if tracked[kind][key] ~= nil then return end
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
    if info ~= nil and info.name == name and info.icon == icon then return end
    known[key] = { name = name, icon = icon }
    store.set("known", known)
  end

  return s
end

return settings
