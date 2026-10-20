-- Names debuff icons by scanning the client's structs in the background, a slice per tick, only while an
-- unnamed icon is wanted. Until the scan names an icon, a label made from its sprite name stands in. Pure:
-- src/adapter supplies spriteName(sprite) and lookup(id), and settings keeps what the scan finds.
local icons = {}

-- Struct ids run below this; 35711 of 0 to 80000 exist.
icons.STRUCT_COUNT = 80000

-- Combat style words that spriteLabel drops from the start of a label.
local STYLES = {
  ATTACK = true, COMBAT = true, CONSTITUTION = true, DEFENCE = true, MAGIC = true, MELEE = true,
  NECROMANCY = true, RANGED = true, STRENGTH = true,
}

-- A sprite config name as a title case label of the words after its first ICON, or nil when nothing is
-- left: DEBUFF_ICON_NECROMANCY_HAUNTED becomes "Haunted" and SPELL_ANCIENT_MAGICKS_ICON_SMOKE_CLOUD
-- becomes "Smoke Cloud".
function icons.spriteLabel(configName)
  local rest = configName:match("_ICON_(.*)$") or configName
  local words = {}
  for word in rest:gmatch("[^_]+") do
    if #words > 0 or not STYLES[word] then words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower() end
  end
  return #words > 0 and table.concat(words, " ") or nil
end

local function isDebuff(configName)
  return configName:sub(1, 16) == "COMBATV2_DEBUFF_"
end

-- saved: { [tostring(sprite)] = { name, info } } from settings. spriteName(sprite) returns the sprite's
-- config name or nil. count overrides STRUCT_COUNT for specs. info(sprite) returns { name, info }, its
-- sprite label as { name }, or nil, and wants the icon when unknown. step(lookup, budget) scans budget
-- struct ids, where lookup(id) returns { configName, icon, name, info } or nil, and returns the icons it
-- named as { sprite, name, info } for saving.
function icons.index(saved, spriteName, count)
  count = count or icons.STRUCT_COUNT
  local known = {}
  for sprite, entry in pairs(saved) do known[tonumber(sprite)] = entry end
  -- Unnamed icons being scanned for: ids left to scan and the lowest-id non-debuff match so far.
  local wanted = {}
  -- Every unnamed icon asked for, to its sprite label as { name }, or false when it has none.
  local labels = {}
  local nextID = 0

  local index = {}

  function index.info(sprite)
    local entry = known[sprite]
    if entry ~= nil then return entry end
    if labels[sprite] == nil then
      local label = icons.spriteLabel(spriteName(sprite) or "")
      labels[sprite] = label ~= nil and { name = label } or false
      wanted[sprite] = { left = count }
    end
    return labels[sprite] or nil
  end

  local function name(sprite, struct)
    known[sprite] = { name = struct.name, info = struct.info }
    wanted[sprite] = nil
    return { sprite = sprite, name = struct.name, info = struct.info }
  end

  function index.step(lookup, budget)
    local found = {}
    if next(wanted) == nil then return found end
    for _ = 1, budget do
      local id = nextID
      nextID = (nextID + 1) % count
      local struct = lookup(id)
      local want = struct and wanted[struct.icon]
      if want ~= nil then
        if isDebuff(struct.configName) then
          found[#found + 1] = name(struct.icon, struct)
        elseif want.fallback == nil or want.fallbackID > id then
          want.fallback, want.fallbackID = struct, id
        end
      end
      for sprite, w in pairs(wanted) do
        w.left = w.left - 1
        if w.left <= 0 then
          if w.fallback ~= nil then
            found[#found + 1] = name(sprite, w.fallback)
          else
            wanted[sprite] = nil
          end
        end
      end
      if next(wanted) == nil then break end
    end
    return found
  end

  return index
end

return icons
