-- Names debuff icons by scanning the client's structs in the background, a slice per tick, only while an
-- unnamed icon is wanted. Pure: src/adapter supplies lookup(id) and settings keeps what it finds.
local icons = {}

-- Struct ids run below this; 35711 of 0 to 80000 exist.
icons.STRUCT_COUNT = 80000

local function isDebuff(configName)
  return configName:sub(1, 16) == "COMBATV2_DEBUFF_"
end

-- saved: { [tostring(sprite)] = { name, info } } from settings. count overrides STRUCT_COUNT for specs.
-- info(sprite) returns { name, info } or nil, wanting the icon when unknown. step(lookup, budget) scans
-- budget struct ids, where lookup(id) returns { configName, icon, name, info } or nil, and returns the
-- icons it named as { sprite, name, info } for saving.
function icons.index(saved, count)
  count = count or icons.STRUCT_COUNT
  local known = {}
  for sprite, entry in pairs(saved) do known[tonumber(sprite)] = entry end
  -- Unnamed icons being scanned for: ids left to scan and the lowest-id non-debuff match so far.
  local wanted = {}
  local missing = {}
  local nextID = 0

  local index = {}

  function index.info(sprite)
    local entry = known[sprite]
    if entry == nil and not missing[sprite] and wanted[sprite] == nil then
      wanted[sprite] = { left = count }
    end
    return entry
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
            missing[sprite] = true
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
