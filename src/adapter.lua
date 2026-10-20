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
-- The target panel's static IDs run to :71; dynamic children of some hold its border and background.
local TARGET_LAST_STATIC = 80
local TARGET_NAME = 21
-- config.Inv.WORN, the worn-equipment inventory.
local WORN_INV = 94
-- Ability struct params read into justUsed()'s result.
local STRUCT_FIELDS = { COMBATV2_ABILITY_NAME = "name", COMBATV2_ABILITY_ICON = "icon" }

-- Reads a field from a game proxy, returning nil when the proxy does not expose it. Always one value, so
-- it is safe as a tostring argument.
local function read(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
  return nil
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

local equipmentWarned = false

-- Whether a Soulbound lantern, augmented or not, is equipped. The inventory proxy's valid reads nil,
-- so a nil result from Find is the only failure check.
local function lanternEquipped()
  local ok, result = pcall(function()
    local inv = Inventory.Find(WORN_INV)
    if inv == nil then return false end
    for _, slot in ipairs(inv:GetSlots() or {}) do
      local name = read(slot.obj, "name")
      if type(name) == "string" and name:lower():find("soulbound lantern", 1, true) then return true end
    end
    return false
  end)
  if not ok and not equipmentWarned then
    equipmentWarned = true
    log("cannot read equipment:", result)
  end
  return ok and result
end

-- Cached lanternEquipped() result; nil until the next read rescans.
local lantern = nil

-- Takes InventoryAdded and InventoryUpdated payloads; a worn gear change makes the next read rescan.
-- An inventory without a readable id also rescans, so a misread never leaves the cache stale.
function adapter.inventoryChanged(e)
  local id = read(e.inv, "id")
  if id == nil or id == WORN_INV then lantern = nil end
end

-- Original alpha of each target panel component while RuneUI holds it transparent, keyed "static" or
-- "static:category:dynamic".
local panelAlpha = nil

-- Calls fn(key, component) for every target panel component, dynamic children included, since a
-- component's alpha does not reach its children.
local function eachPanelComponent(fn)
  for staticID = 0, TARGET_LAST_STATIC do
    local c = ui.Interfaces:GetComponent(TARGET_PANEL, staticID)
    if c ~= nil then
      fn(tostring(staticID), c)
      pcall(function()
        c:IterateDynamicComponents(function(child)
          fn(staticID .. ":" .. tostring(read(child, "categoryID")) .. ":" .. tostring(read(child, "dynamicID")), child)
          return false
        end)
      end)
    end
  end
end

local function setPanelAlpha(transparent)
  eachPanelComponent(function(key, c)
    if transparent and panelAlpha[key] == nil then panelAlpha[key] = read(c, "alpha") or 1 end
    local alpha = transparent and 0 or panelAlpha[key] or 1
    pcall(function() c.alpha = alpha end)
  end)
end

-- Runs each tick with whether the native target panel should be hidden. Hiding sets alpha 0, because
-- hidden stops the panel filling its debuff slots, which targetReads relies on. A visible name label
-- means the panel reloaded, so it is made transparent again; false restores the original alphas.
function adapter.hideTargetPanel(hidden)
  if hidden then
    panelAlpha = panelAlpha or {}
    local alpha = read(ui.Interfaces:GetComponent(TARGET_PANEL, TARGET_NAME), "alpha")
    if alpha ~= nil and alpha > 0 then setPanelAlpha(true) end
  elseif panelAlpha ~= nil then
    setPanelAlpha(false)
    panelAlpha = nil
  end
end

-- spenders: the frames.SPENDERS list; each is read by its var name.
function adapter.resourceReads(spenders)
  local counts = {}
  for _, spender in ipairs(spenders) do
    counts[spender.var] = varValue("VarPlayer", spender.var)
  end
  if lantern == nil then lantern = lanternEquipped() end
  return { adrenaline = varValue("VarPlayer", "SA_ENERGY"), spenders = counts, lantern = lantern }
end

return adapter
