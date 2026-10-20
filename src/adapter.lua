-- The only module that reads the RS3 client. Returns plain tables in the shapes src/frames expects.
local adapter = {}

local MAIN_BAR = 1430
local TARGET_PANEL = 1490
-- Target debuff icon sprites sit every 3 static IDs from :38 to :71; -1 marks an empty slot.
local DEBUFF_FIRST, DEBUFF_LAST, DEBUFF_STEP = 38, 71, 3
-- Native action bars: first slot background ID per interface. Slots are 13 IDs apart, with the icon
-- sprite at +2 and the keybind label at +9.
local BAR_FIRST_SLOTS = { [1430] = 64, [1670] = 19, [1671] = 17, [1672] = 14, [1673] = 14 }
local SLOTS_PER_BAR, SLOT_STRIDE, SLOT_ICON, SLOT_KEYBIND = 14, 13, 2, 9
-- Ability struct params read into justUsed()'s result.
local STRUCT_FIELDS = { COMBATV2_ABILITY_NAME = "name", COMBATV2_ABILITY_ICON = "icon" }

-- Reads a field from a game proxy, returning nil when the proxy does not expose it.
local function read(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
end

local function varValue(domain, name)
  local v = read(var[domain], name)
  if v ~= nil then return read(v, "value") end
end

-- Text of a label component, or nil when it is missing or empty.
local function labelText(interfaceID, staticID, categoryID, dynamicID)
  local c
  if categoryID ~= nil then
    c = ui.Interfaces:GetComponent(interfaceID, staticID, categoryID, dynamicID)
  else
    c = ui.Interfaces:GetComponent(interfaceID, staticID)
  end
  local text = c and read(c, "content")
  if type(text) == "string" and text ~= "" then return text end
end

function adapter.playerReads()
  local available = Player.IsAvailable()
  local entity = available and Player.GetEntity() or nil
  return {
    available = available,
    name = entity and read(entity, "displayName"),
    lifepoints = varValue("VarPlayer", "LIFEPOINTS"),
    lifepointsLabel = labelText(MAIN_BAR, 9, 0, 8),
    prayerValue = varValue("VarPlayer", "PRAYER_POINTS_VAR"),
    prayerLabel = labelText(MAIN_BAR, 16, 0, 8),
  }
end

function adapter.targetReads()
  local debuffs = {}
  for staticID = DEBUFF_FIRST, DEBUFF_LAST, DEBUFF_STEP do
    local c = ui.Interfaces:GetComponent(TARGET_PANEL, staticID)
    local sprite = c and read(c, "spriteID")
    if sprite ~= nil and sprite ~= -1 then debuffs[#debuffs + 1] = sprite end
  end
  return {
    target = varValue("VarPlayer", "NPCTARGET"),
    name = labelText(TARGET_PANEL, 21),
    lifepointsLabel = labelText(TARGET_PANEL, 34),
    healthPercent = varValue("VarClient", "COMBATV2_TARGET_SIDE_PANEL_HEALTH"),
    debuffs = debuffs,
  }
end

-- Name, old value and new value of an Event.VarTransmit payload.
function adapter.varChange(e)
  return read(e.var, "configName") or "", e.oldValue, e.newValue
end

-- The struct in COMBATV2_JUST_USED_ABILITY as { key, name, icon }, or nil when it has no name or icon.
-- key is the struct name without "COMBATV2_ABILITY_", matching the cooldown var keys in src/cooldowns.
function adapter.justUsed()
  local struct = varValue("VarClient", "COMBATV2_JUST_USED_ABILITY")
  local params = struct and read(struct, "params")
  if params == nil then return nil end
  local info = { key = (tostring(read(struct, "configName")):gsub("^COMBATV2_ABILITY_", "")) }
  for _, param in ipairs(params) do
    local field = STRUCT_FIELDS[read(param, "configName")]
    if field ~= nil then
      local ok, value = pcall(function() return struct:GetParamValue(param) end)
      if ok then info[field] = value end
    end
  end
  if info.name ~= nil or info.icon ~= nil then return info end
end

-- { [iconSpriteID] = keybind } for every native action bar slot showing both.
function adapter.slotKeybinds()
  local keybinds = {}
  for interfaceID, first in pairs(BAR_FIRST_SLOTS) do
    for slot = 0, SLOTS_PER_BAR - 1 do
      local base = first + slot * SLOT_STRIDE
      local icon = ui.Interfaces:GetComponent(interfaceID, base + SLOT_ICON)
      local sprite = icon and read(icon, "spriteID")
      local keybind = labelText(interfaceID, base + SLOT_KEYBIND)
      if sprite ~= nil and sprite ~= -1 and keybind ~= nil then keybinds[sprite] = keybind end
    end
  end
  return keybinds
end

-- PersistentDB as a src/settings store, one structured table per key.
function adapter.store()
  return {
    get = function(key) return PersistentDB:GetStructuredData(key) end,
    set = function(key, value)
      if PersistentDB:SetStructuredData(key, value) == false then log("could not save", key) end
    end,
  }
end

-- spenders: the frames.SPENDERS list; each is read by its var name.
function adapter.resourceReads(spenders)
  local counts = {}
  for _, spender in ipairs(spenders) do
    counts[spender.var] = varValue("VarPlayer", spender.var)
  end
  return { adrenaline = varValue("VarPlayer", "SA_ENERGY"), spenders = counts }
end

return adapter
