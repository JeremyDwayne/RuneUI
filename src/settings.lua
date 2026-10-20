-- Saved settings: element positions, cooldown groups, marker percents, appearance (bar texture and whether
-- the default target panel is hidden), learned ability names and icons, and debuff names by icon.
-- Pure: reads and writes go through a store with get(key) and set(key, table), so specs use a fake.
local settings = {}

-- Offsets from the bottom centre of the game window, clear of the native bottom panel. The frames sit
-- either side of the rotation row with their bottoms level, and the bars stack centred above it.
settings.DEFAULT_POSITIONS = {
  player = { x = -477, y = -409, anchorX = 0.5, anchorY = 1 },
  target = { x = 227, y = -432, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -496, anchorX = 0.5, anchorY = 1 },
  rotation = { x = -219, y = -396, anchorX = 0.5, anchorY = 1 },
  cooldowns = { x = -189, y = -539, anchorX = 0.5, anchorY = 1 },
}
local DEFAULT_MARKERS = { threshold = 50, ultimate = 100 }
-- Bar fills: one flat colour, or a gradient from top to bottom or across the bar.
settings.TEXTURES = { "flat", "vertical", "horizontal" }
local GROUP_NAMES = { "rotation", "cooldowns" }
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

local function stringsOnly(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, key in ipairs(list) do
    if type(key) == "string" then out[#out + 1] = key end
  end
  return out
end

local function readLayout(saved)
  local layout = {}
  if type(saved) ~= "table" then return layout end
  for name in pairs(settings.DEFAULT_POSITIONS) do layout[name] = copyPosition(saved[name]) end
  return layout
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
    markers[name] = type(value) == "number" and value or default
  end
  return markers
end

local function readAppearance(saved)
  saved = type(saved) == "table" and saved or {}
  local appearance = { texture = "flat", hideTargetPanel = saved.hideTargetPanel == true }
  for _, known in ipairs(settings.TEXTURES) do
    if saved.texture == known then appearance.texture = known end
  end
  return appearance
end

local function readDebuffs(saved)
  local debuffs = {}
  if type(saved) ~= "table" then return debuffs end
  for sprite, entry in pairs(saved) do
    if type(entry) == "table" and type(entry.name) == "string" then
      debuffs[tostring(sprite)] = { name = entry.name, info = type(entry.info) == "string" and entry.info or nil }
    end
  end
  return debuffs
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

-- Loads saved settings from store, dropping unknown keys and malformed values.
function settings.load(store)
  local layout = readLayout(store.get("layout"))
  local groups = readGroups(store.get("groups"))
  local markers = readMarkers(store.get("markers"))
  local known = readKnown(store.get("known"))
  local appearance = readAppearance(store.get("appearance"))
  local debuffs = readDebuffs(store.get("debuffs"))

  local function saveGroups() store.set("groups", groups) end

  local s = {}

  -- Every element's position, saved or default.
  function s.positions()
    local positions = {}
    for name, default in pairs(settings.DEFAULT_POSITIONS) do positions[name] = layout[name] or default end
    return positions
  end

  function s.setPosition(name, pos)
    layout[name] = copyPosition(pos)
    store.set("layout", layout)
  end

  function s.resetPositions()
    layout = {}
    store.set("layout", layout)
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

  -- { [tostring(sprite)] = { name, info } } for every debuff icon src/icons has named.
  function s.debuffs()
    return debuffs
  end

  function s.learnDebuff(sprite, name, info)
    debuffs[tostring(sprite)] = { name = name, info = info }
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
