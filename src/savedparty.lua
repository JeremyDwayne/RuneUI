-- Saved party choices: each name's default tag, the role presets and which is active, each tier's cell size,
-- cells per row and column and Show my frame, how the grid fills and grows, and the sidebar's state. Pure:
-- reads and writes go through a store with get(key) and set(key, table), so specs use a fake. Tags are keyed by
-- src/party's key of a name, and nothing here leaves the store.
local party = require("src/party")
local util = require("src/util")

local savedparty = {}

-- The store has no delete, so presets live in this many slots, each saved under its own key. An emptied slot
-- is free.
savedparty.MAX_ROLE_PRESETS = 8
savedparty.MAX_TAG = 10
savedparty.MAX_PRESET_NAME = 20
-- The range of each tier number a player can set.
savedparty.TIER_RANGES = { w = { 40, 200 }, h = { 16, 80 }, columns = { 1, 10 }, rows = { 1, 10 } }
-- The values each grid setting takes, its default first.
savedparty.GRID_CHOICES = { fill = { "rows", "columns" }, growX = { "right", "left" }, growY = { "down", "up" } }

local function presetKey(slot)
  return "partyPreset" .. slot
end

-- text without the spaces round it, when it then holds 1 to max characters, or nil.
local function trimmed(text, max)
  if type(text) ~= "string" then
    return nil
  end
  text = text:match("^%s*(.-)%s*$")
  if #text >= 1 and #text <= max then
    return text
  end
end

-- A saved { [key] = tag } map without malformed entries.
local function readTags(saved)
  local out = {}
  if type(saved) ~= "table" then
    return out
  end
  for key, tag in pairs(saved) do
    if type(key) == "string" then
      out[key] = trimmed(tag, savedparty.MAX_TAG)
    end
  end
  return out
end

-- A saved tier over its defaults, keeping each number in range and whole.
local function readTier(saved, default)
  local tier =
    { w = default.w, h = default.h, columns = default.columns, rows = default.rows, showSelf = default.showSelf }
  if type(saved) ~= "table" then
    return tier
  end
  for field, range in pairs(savedparty.TIER_RANGES) do
    local n = saved[field]
    if type(n) == "number" and n >= range[1] and n <= range[2] then
      tier[field] = util.whole(n)
    end
  end
  if type(saved.showSelf) == "boolean" then
    tier.showSelf = saved.showSelf
  end
  return tier
end

-- Loads the party choices from store, dropping malformed entries.
function savedparty.load(store)
  local saved = store.get("party")
  if type(saved) ~= "table" then
    saved = {}
  end
  local tiers = {}
  for id, default in pairs(party.TIER_DEFAULTS) do
    tiers[id] = readTier(type(saved.tiers) == "table" and saved.tiers[id], default)
  end
  local grid = {}
  for field, choices in pairs(savedparty.GRID_CHOICES) do
    local value = type(saved.grid) == "table" and saved.grid[field]
    grid[field] = util.indexOf(choices, value) and value or choices[1]
  end
  local sidebar = { on = saved.sidebar ~= false, collapsed = saved.collapsed == true }
  -- Each slot's { name, tags }, or nil for a free slot.
  local presets = {}
  for slot = 1, savedparty.MAX_ROLE_PRESETS do
    local preset = store.get(presetKey(slot))
    local name = type(preset) == "table" and trimmed(preset.name, savedparty.MAX_PRESET_NAME)
    if name then
      presets[slot] = { name = name, tags = readTags(preset.tags) }
    end
  end
  local active = type(saved.active) == "number" and math.tointeger(saved.active) or nil
  if presets[active] == nil then
    active = nil
  end
  -- What src/party's tag takes, kept as one table so callers hold it across changes.
  local roles = { defaults = readTags(store.get("partyRoles")), preset = active and presets[active].tags }

  local function saveParty()
    store.set("party", {
      tiers = tiers,
      grid = grid,
      active = active,
      sidebar = sidebar.on,
      collapsed = sidebar.collapsed,
    })
  end

  local s = {}

  -- { defaults, preset } as party.tag takes: preset is the active preset's tags, nil with none active.
  function s.roles()
    return roles
  end

  -- Gives name a tag of up to MAX_TAG characters, or none when tag is empty: in the active preset, or as the
  -- name's default with none active.
  function s.setRole(name, tag)
    local tags = roles.preset or roles.defaults
    tags[party.key(name)] = trimmed(tag, savedparty.MAX_TAG)
    if active then
      store.set(presetKey(active), presets[active])
    else
      store.set("partyRoles", roles.defaults)
    end
  end

  -- The presets in slot order, each { slot, name }.
  function s.rolePresets()
    local out = {}
    for slot = 1, savedparty.MAX_ROLE_PRESETS do
      if presets[slot] then
        out[#out + 1] = { slot = slot, name = presets[slot].name }
      end
    end
    return out
  end

  -- Adds an empty preset called name in the first free slot. Returns its slot, or nil when the name is
  -- malformed or every slot is taken.
  function s.addRolePreset(name)
    name = trimmed(name, savedparty.MAX_PRESET_NAME)
    for slot = 1, savedparty.MAX_ROLE_PRESETS do
      if name and presets[slot] == nil then
        presets[slot] = { name = name, tags = {} }
        store.set(presetKey(slot), presets[slot])
        return slot
      end
    end
  end

  -- Frees a preset's slot, turning it off first when it is the active one.
  function s.removeRolePreset(slot)
    if slot == active then
      s.setActiveRolePreset(nil)
    end
    presets[slot] = nil
    store.set(presetKey(slot), {})
  end

  -- The active preset's slot, or nil.
  function s.activeRolePreset()
    return active
  end

  -- Makes the preset in slot the active one, or none with nil.
  function s.setActiveRolePreset(slot)
    active = presets[slot] and slot or nil
    roles.preset = active and presets[active].tags
    saveParty()
  end

  -- { [tier id] = { w, h, columns, rows, showSelf } } for every src/party tier.
  function s.partyTiers()
    return tiers
  end

  -- Sets a tier's w, h, columns, rows or showSelf. The caller keeps numbers inside TIER_RANGES.
  function s.setPartyTier(id, field, value)
    tiers[id][field] = value
    saveParty()
  end

  -- { fill, growX, growY } as src/party's GRID_DEFAULTS.
  function s.partyGrid()
    return grid
  end

  -- Sets fill, growX or growY to one of its GRID_CHOICES.
  function s.setPartyGrid(field, value)
    grid[field] = value
    saveParty()
  end

  -- { on, collapsed }: whether the party grid and the sidebar stand in for the game's group window, and
  -- whether the sidebar is folded.
  function s.sidebar()
    return sidebar
  end

  function s.setSidebar(field, value)
    sidebar[field] = value
    saveParty()
  end

  return s
end

return savedparty
