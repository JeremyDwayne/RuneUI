-- Names buff and debuff icons by scanning the client's structs in the background, a slice per tick, only
-- while an unnamed icon is wanted. Until the scan names an icon, or when no struct matches it, a label made
-- from its sprite name stands in. An item icon, minus its item id, takes the item's name with no scan. A
-- named icon's description is read from its struct when first asked for. Pure: src/adapter supplies the client
-- lookups, and settings keeps what the scan finds.
local icons = {}

-- Struct ids run below this; 35711 of 0 to 80000 exist.
icons.STRUCT_COUNT = 80000

-- Combat style words that spriteLabel drops from the start of a label.
local STYLES = {
  ATTACK = true,
  COMBAT = true,
  CONSTITUTION = true,
  DEFENCE = true,
  MAGIC = true,
  MELEE = true,
  NECROMANCY = true,
  RANGED = true,
  STRENGTH = true,
}

-- A sprite config name as a title case label of the words after its first ICON, or nil when nothing is
-- left: DEBUFF_ICON_NECROMANCY_HAUNTED becomes "Haunted" and SPELL_ANCIENT_MAGICKS_ICON_SMOKE_CLOUD
-- becomes "Smoke Cloud".
function icons.spriteLabel(configName)
  local rest = configName:match("_ICON_(.*)$") or configName
  local words = {}
  for word in rest:gmatch("[^_]+") do
    if #words > 0 or not STYLES[word] then
      words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower()
    end
  end
  return #words > 0 and table.concat(words, " ") or nil
end

-- A struct name of the form "Name<br>text", "Name - text" or "Name: text" as the name and the text, or the
-- whole name alone: "Drenched - Each stack slows you." gives "Drenched" and "Each stack slows you.". The text
-- starts with a capital. A colon splits only before text of four words or more, so "Imbue: Shadows" stays whole.
function icons.split(name)
  local short, rest = name:match("^(.-)<br>(.+)$")
  if short ~= nil then
    while rest:sub(1, 4) == "<br>" do
      rest = rest:sub(5)
    end
  else
    short, rest = name:match("^(.-) %- (.+)$")
  end
  if short == nil then
    short, rest = name:match("^(.-): (.+)$")
    if short ~= nil and select(2, rest:gsub("%S+", "")) < 4 then
      short = nil
    end
  end
  if short == nil or short == "" or rest == "" then
    return name
  end
  return short, (rest:gsub("^%l", string.upper))
end

-- What info returns for an icon with no name and no sprite label once the scan gives up.
local NO_NAME = {}

-- Lowercase words of a sprite config name, as a set: DEBUFF_ICON_POISONED gives debuff, icon and poisoned.
local function spriteWords(configName)
  local words = {}
  for word in configName:lower():gmatch("[^_]+") do
    words[word] = true
  end
  return words
end

-- How well struct fits a sprite with words, lower is better: 1 when every word of its name is a sprite word,
-- as "Poisoned" for DEBUFF_ICON_POISONED, 2 for a debuff struct, 3 for any other.
local function rank(struct, words)
  local any = false
  local all = true
  for word in icons.split(tostring(struct.name)):lower():gmatch("%a+") do
    any = true
    if not words[word] then
      all = false
    end
  end
  if any and all then
    return 1
  end
  return struct.configName:sub(1, 16) == "COMBATV2_DEBUFF_" and 2 or 3
end

-- saved: { [tostring(sprite)] = { name, struct } or { unmatched = true } } from settings, each name shown up to
-- any " - ". client: { spriteName,
-- itemName, describe }, where spriteName(sprite) returns the sprite's config name, itemName(objID) an item's
-- name and describe(structID) a struct's description, each or nil. count overrides STRUCT_COUNT for specs.
-- info(sprite) returns { name, info }, its sprite label as { name }, {} once no struct matches an icon with no
-- label, or nil while one is looked up, and wants the icon when unknown. step(lookup, budget) scans budget
-- struct ids, where lookup(id) returns { configName, icon, name } or nil, and returns what it settled for
-- saving: { sprite, name, struct } for a named icon, { sprite } for one no struct matches. learn(sprite, name,
-- struct) names an icon not yet named at once, as a scan match does, and returns whether it did, so the caller
-- saves it.
function icons.index(saved, client, count)
  count = count or icons.STRUCT_COUNT
  local known = {}
  -- Named icons whose description is not read yet, to their struct id.
  local undescribed = {}
  -- Icons a full scan found no struct for, which are never scanned for again.
  local unmatched = {}
  for key, entry in pairs(saved) do
    local sprite = tonumber(key)
    if entry.unmatched then
      unmatched[sprite] = true
    else
      known[sprite] = { name = (icons.split(entry.name)) }
      undescribed[sprite] = entry.struct
    end
  end
  -- Unnamed icons being scanned for: ids left to scan, the sprite's words, and the best match so far with its
  -- rank and id.
  local wanted = {}
  -- Every unnamed icon asked for, to its sprite label as { name }, or false when it has none.
  local labels = {}
  local nextID = 0

  local index = {}

  function index.info(sprite)
    local entry = known[sprite]
    if entry ~= nil then
      local structID = undescribed[sprite]
      if structID ~= nil then
        undescribed[sprite] = nil
        entry.info = client.describe(structID)
      end
      return entry
    end
    if labels[sprite] == nil and sprite < 0 then
      local item = client.itemName(-sprite)
      labels[sprite] = item ~= nil and { name = (item:gsub(" %(%d+%)$", "")) } or NO_NAME
    elseif labels[sprite] == nil then
      local configName = client.spriteName(sprite) or ""
      local label = icons.spriteLabel(configName)
      labels[sprite] = label ~= nil and { name = label } or false
      if not unmatched[sprite] then
        wanted[sprite] = { left = count, words = spriteWords(configName) }
      end
    end
    return labels[sprite] or (unmatched[sprite] and NO_NAME) or nil
  end

  local function name(sprite, struct, structID)
    local short = icons.split(struct.name)
    known[sprite] = { name = short }
    undescribed[sprite] = structID
    wanted[sprite] = nil
    return { sprite = sprite, name = short, struct = structID }
  end

  function index.learn(sprite, newName, structID)
    if known[sprite] ~= nil then
      return false
    end
    name(sprite, { name = newName }, structID)
    unmatched[sprite] = nil
    return true
  end

  function index.step(lookup, budget)
    local found = {}
    if next(wanted) == nil then
      return found
    end
    -- Scan no further than the icon with the most ids left needs. Ids past an icon's own full cycle are ones
    -- it already saw, so they leave its match unchanged.
    local scan = 0
    for _, w in pairs(wanted) do
      scan = math.max(scan, w.left)
    end
    scan = math.min(scan, budget)
    for _ = 1, scan do
      local id = nextID
      nextID = (nextID + 1) % count
      local struct = lookup(id)
      local want = struct and wanted[struct.icon]
      if want ~= nil then
        local r = rank(struct, want.words)
        if r == 1 then
          found[#found + 1] = name(struct.icon, struct, id)
        elseif want.best == nil or r < want.bestRank or (r == want.bestRank and id < want.bestID) then
          want.best = struct
          want.bestRank = r
          want.bestID = id
        end
      end
      if next(wanted) == nil then
        break
      end
    end
    for sprite, w in pairs(wanted) do
      w.left = w.left - scan
      if w.left <= 0 then
        if w.best ~= nil then
          found[#found + 1] = name(sprite, w.best, w.bestID)
        else
          unmatched[sprite], wanted[sprite] = true, nil
          found[#found + 1] = { sprite = sprite }
        end
      end
    end
    return found
  end

  return index
end

return icons
