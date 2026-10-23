-- Saved cooldown groups: each group's title and display settings, its ability list per combat style or shared,
-- and the name and icon learned for each ability. Pure: reads and writes go through a store with get(key) and
-- set(key, table), so specs use a fake.
local cooldowns = require("src/cooldowns")
local presets = require("src/presets")
local util = require("src/util")

local savedgroups = {}

local whole = util.whole
local clamp = util.clamp
local indexOf = util.indexOf

-- Combat styles a cooldown group keeps a separate ability list for, and the directions a group grows in.
savedgroups.STYLES = { "necromancy", "magic", "ranged", "melee" }
savedgroups.GROWS = { "up", "down", "left", "right" }
-- The most abilities one group list holds, the range of a group's icon size, and its title length.
savedgroups.MAX_GROUP_KEYS = 20
savedgroups.SIZE_MIN = 24
savedgroups.SIZE_MAX = 56
local TITLE_MAX = 20
-- Built-in cooldown groups in list order, with their default title and display settings. A shared group
-- shows one ability list with every style; the others keep one list per style.
savedgroups.GROUPS = {
  { name = "major", title = "Major", size = 35, perRow = 6, grow = "down", shared = false },
  { name = "rotation", title = "Rotation", size = 45, perRow = 6, grow = "down", shared = false },
  { name = "utility", title = "Utility", size = 30, perRow = 8, grow = "down", shared = true },
}
-- The first custom group a new install starts with, holding the defensive abilities.
local DEFENSIVES = { name = "custom1", title = "Defensives", size = 30, perRow = 8, grow = "down", shared = true }
-- Element names of the groups a player can add, in the order they fill, and a new one's display settings.
savedgroups.CUSTOM_GROUPS = { "custom1", "custom2", "custom3", "custom4" }
local CUSTOM_DEFAULT = { size = 36, perRow = 8, grow = "down", shared = true }
-- The list a per-style group shows before any combat style is known.
local NO_KEYS = {}

-- The ability keys in a saved list, each mapped to its ability by cooldowns.baseKey and kept once, in order.
local function stringsOnly(list)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  local seen = {}
  for _, key in ipairs(list) do
    if type(key) == "string" then
      key = cooldowns.baseKey(key)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = key
      end
    end
  end
  return out
end

local function isGrow(value)
  return indexOf(savedgroups.GROWS, value) ~= nil
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
    size = type(saved.size) == "number" and clamp(whole(saved.size), savedgroups.SIZE_MIN, savedgroups.SIZE_MAX)
      or default.size,
    perRow = type(saved.perRow) == "number" and clamp(whole(saved.perRow), 1, savedgroups.MAX_GROUP_KEYS)
      or default.perRow,
    grow = isGrow(saved.grow) and saved.grow or default.grow,
    shared = default.shared,
    keys = stringsOnly(saved.keys),
    styles = {},
  }
  if type(saved.shared) == "boolean" then
    group.shared = saved.shared
  end
  for _, style in ipairs(savedgroups.STYLES) do
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
  for _, style in ipairs(savedgroups.STYLES) do
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
  for _, style in ipairs(savedgroups.STYLES) do
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

-- { seeded = { [style, "utility" or "defensives"] = true }, groups = { [name] = group record } } from the saved
-- cooldownGroups, seeded from src/presets, and whether seeding changed it. Every built-in group is present; a
-- custom one only once added.
local function readCooldownGroups(saved)
  local stored = type(saved) == "table" and type(saved.groups) == "table" and saved.groups or {}
  local groups = {}
  for _, default in ipairs(savedgroups.GROUPS) do
    groups[default.name] = readGroup(stored[default.name], default)
  end
  for _, name in ipairs(savedgroups.CUSTOM_GROUPS) do
    if type(stored[name]) == "table" then
      groups[name] = readGroup(stored[name], customDefault(name))
    end
  end
  local seeded = {}
  local savedSeeded = type(saved) == "table" and type(saved.seeded) == "table" and saved.seeded or {}
  for _, name in ipairs({ "utility", "defensives", table.unpack(savedgroups.STYLES) }) do
    seeded[name] = savedSeeded[name] == true
  end
  local changed = seed(groups, seeded)
  return { seeded = seeded, groups = groups }, changed
end

-- Saved names and icons by ability key. An entry under a second charge's key loads under its ability's, unless
-- the ability has its own entry. An entry under a recast stage's key names the stage, not the ability, so it is
-- dropped.
local function readKnown(saved)
  local known = {}
  if type(saved) ~= "table" then
    return known
  end
  for key, info in pairs(saved) do
    if type(key) == "string" and type(info) == "table" and not key:match("_RECAST_%d+$") then
      local base = cooldowns.baseKey(key)
      if key == base or known[base] == nil then
        local icon = type(info.icon) == "number" and whole(info.icon) or nil
        known[base] = { name = type(info.name) == "string" and info.name or nil, icon = icon }
      end
    end
  end
  return known
end

-- Loads the groups and known abilities from store, dropping malformed values, and seeds new groups from
-- src/presets.
function savedgroups.load(store)
  local cooldownGroups, changed = readCooldownGroups(store.get("cooldownGroups"))
  local groups = cooldownGroups.groups
  local known = readKnown(store.get("known"))

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

  -- Names of the groups in use, built-in ones first, then custom ones in slot order.
  function s.groupNames()
    local names = {}
    for _, default in ipairs(savedgroups.GROUPS) do
      names[#names + 1] = default.name
    end
    for _, name in ipairs(savedgroups.CUSTOM_GROUPS) do
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

  -- Saves one of name's display settings: size and perRow clamped to their ranges, grow one of GROWS, shared a
  -- boolean, or a title cut to 20 characters and trimmed. Any other value changes nothing.
  function s.setGroup(name, field, value)
    local group = groups[name]
    if group == nil then
      return
    end
    if field == "size" and type(value) == "number" then
      group.size = clamp(value, savedgroups.SIZE_MIN, savedgroups.SIZE_MAX)
    elseif field == "perRow" and type(value) == "number" then
      group.perRow = clamp(value, 1, savedgroups.MAX_GROUP_KEYS)
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
    for _, name in ipairs(savedgroups.CUSTOM_GROUPS) do
      if groups[name] == nil then
        groups[name] = readGroup(nil, customDefault(name))
        saveGroups()
        return name
      end
    end
  end

  -- Deletes a custom group with its abilities. Built-in groups stay.
  function s.deleteGroup(name)
    if groups[name] == nil or indexOf(savedgroups.CUSTOM_GROUPS, name) == nil then
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
    if indexOf(list, key) == nil and #list >= savedgroups.MAX_GROUP_KEYS then
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

  -- { [key] = { name, icon } } for every ability whose struct has been seen.
  function s.known()
    return known
  end

  -- Saves an ability's name and icon when either changed.
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

return savedgroups
