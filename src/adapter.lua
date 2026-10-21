-- The only module that reads the RS3 client. Returns plain tables in the shapes src/frames expects.
local adapter = {}

local MAIN_BAR = 1430
local TARGET_PANEL = 1490
-- The game's cast bar, with its highest static ID and its time left label.
local CAST_BAR, CAST_BAR_LAST_STATIC, CAST_BAR_DURATION = 764, 37, 5
-- Target debuff icon sprites sit every 3 static IDs from :38 to :71. A slot is empty when its sprite is -1
-- or it reads not visibleGlobal: an expired or switched-away debuff keeps its sprite while invisible.
local DEBUFF_FIRST, DEBUFF_LAST, DEBUFF_STEP = 38, 71, 3
-- Native action bars: first slot background ID per interface. Slots are 13 IDs apart, with the icon
-- sprite at +2 and the keybind label at +9. The client tints the icon SLOT_DIM while its ability can't be cast.
local BAR_FIRST_SLOTS = { [1430] = 64, [1670] = 19, [1671] = 17, [1672] = 14, [1673] = 14 }
local SLOTS_PER_BAR, SLOT_STRIDE, SLOT_ICON, SLOT_KEYBIND = 14, 13, 2, 9
local SLOT_DIM = 0x333333
-- The target panel's static IDs run to :71; dynamic children of some hold its border and background.
local TARGET_LAST_STATIC = 80
local TARGET_NAME = 21
-- The panel's background sprite, dynamic child :25:0:0, which the client can rebuild opaque on its own.
local TARGET_BACKGROUND = 25
-- The buff bar and debuff bar share a layout: slot :<n>:0:0 holds the icon sprite, :<n>:0:1 the label,
-- :<n>:0:2 and :<n>:0:3 its frame. An icon showing an item reads sprite -1, and a slot the player's buff
-- settings hide reads its label not visibleGlobal. lastStatic is each bar's highest static ID, and watchLast
-- the last slot a buff can fill next, as auraReads last saw the bar.
local BUFF_BARS = {
  buffs = { id = 284, first = 19, last = 68, lastStatic = 80 },
  debuffs = { id = 291, first = 2, last = 51, lastStatic = 60 },
}
-- Empty slots in a row after which a bar holds no more icons.
local EMPTY_RUN = 4
-- Rendered frames after each server tick in which a buff bar can fill a slot.
local FILL_FRAMES = 8
-- Slots past the last filled one that a buff can fill at once, such as a potion's several effects.
local FILL_AHEAD = 8
-- config.Inv.WORN, the worn-equipment inventory.
local WORN_INV = 94
-- Ability struct params read into justUsed()'s result.
local STRUCT_FIELDS = { COMBATV2_ABILITY_NAME = "name", COMBATV2_ABILITY_ICON = "icon" }

local function index(obj, field)
  return obj[field]
end

-- Reads a field from a game proxy, returning nil when the proxy does not expose it. Always one value, so
-- it is safe as a tostring argument. Runs many times a tick, so it passes index to pcall rather than
-- building a closure per read.
local function read(obj, field)
  local ok, value = pcall(index, obj, field)
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

-- With no target, returns { target } alone and skips the panel's components.
function adapter.targetReads()
  local target = varValue("VarPlayer", "NPCTARGET")
  if target == nil or target == -1 then return { target = target } end
  local debuffs = {}
  for staticID = DEBUFF_FIRST, DEBUFF_LAST, DEBUFF_STEP do
    local c = ui.Interfaces:GetComponent(TARGET_PANEL, staticID)
    local sprite = c and read(c, "spriteID")
    if sprite ~= nil and sprite ~= -1 and read(c, "visibleGlobal") ~= false then debuffs[#debuffs + 1] = sprite end
  end
  return {
    target = target,
    name = labelText(TARGET_PANEL, TARGET_NAME),
    lifepointsLabel = labelText(TARGET_PANEL, 34),
    healthPercent = varValue("VarClient", "COMBATV2_TARGET_SIDE_PANEL_HEALTH"),
    debuffs = debuffs,
  }
end

-- { sprite, label } for each shown icon on bar, a BUFF_BARS entry, stopping after EMPTY_RUN empty slots.
local function barReads(bar)
  local list, empty, filled = {}, 0, bar.first - 1
  for staticID = bar.first, bar.last do
    local icon = ui.Interfaces:GetComponent(bar.id, staticID, 0, 0)
    local sprite = icon and read(icon, "spriteID")
    local label = ui.Interfaces:GetComponent(bar.id, staticID, 0, 1)
    local text = label and read(label, "content")
    if type(text) ~= "string" or text == "" then text = nil end
    if (sprite == nil or sprite == -1) and text == nil then
      empty = empty + 1
      if empty >= EMPTY_RUN then break end
    else
      empty, filled = 0, staticID
      if sprite ~= nil and sprite ~= -1 and read(label, "visibleGlobal") ~= false then
        list[#list + 1] = { sprite = sprite, label = text }
      end
    end
  end
  bar.watchLast = math.min(bar.last, filled + FILL_AHEAD)
  return list
end

-- The native buff and debuff bars as src/auras reads: { buffs, debuffs }, each a list of { sprite, label }.
function adapter.auraReads()
  return { buffs = barReads(BUFF_BARS.buffs), debuffs = barReads(BUFF_BARS.debuffs) }
end

-- Name, old value and new value of an Event.VarTransmit payload.
function adapter.varChange(e)
  return read(e.var, "configName") or "", e.oldValue, e.newValue
end

-- An ability struct as { key, name, icon }, or nil when it has no name or icon. key is the struct name
-- without "COMBATV2_ABILITY_", matching the cooldown var keys in src/cooldowns.
local function abilityInfo(struct)
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

-- The struct in COMBATV2_JUST_USED_ABILITY as abilityInfo describes it.
function adapter.justUsed()
  return abilityInfo(varValue("VarClient", "COMBATV2_JUST_USED_ABILITY"))
end

-- The value of the VarPlayer var name, such as COMBATV2_MAINHAND_STYLE, or nil before login.
function adapter.playerVar(name)
  return varValue("VarPlayer", name)
end

-- { [iconSpriteID] = { keybind, usable } } for every filled native action bar slot. keybind is nil on a slot
-- with none, and usable is false while the client dims the slot's icon.
function adapter.barSlots()
  local slots = {}
  for interfaceID, first in pairs(BAR_FIRST_SLOTS) do
    for slot = 0, SLOTS_PER_BAR - 1 do
      local base = first + slot * SLOT_STRIDE
      local icon = ui.Interfaces:GetComponent(interfaceID, base + SLOT_ICON)
      local sprite = icon and read(icon, "spriteID")
      if sprite ~= nil and sprite ~= -1 then
        local keybind = labelText(interfaceID, base + SLOT_KEYBIND)
        slots[sprite] = { keybind = keybind, usable = read(icon, "rgb") ~= SLOT_DIM }
      end
    end
  end
  return slots
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

-- Whether c reads an alpha above 0.
local function opaque(c)
  if c == nil then return false end
  local alpha = read(c, "alpha")
  return alpha ~= nil and alpha > 0
end

-- An interface RuneUI can hold transparent with alpha 0, since hiding its components stops them updating.
-- lastStatic is its highest static ID. watched lists { staticID, categoryID, dynamicID } addresses, without
-- the last two for a static, that read opaque once the client reloads or rebuilds the interface. Returns
-- { hide(hidden), keep() }: hide runs each server tick and false restores the original alphas; keep runs on
-- every rendered frame, reading only the watched components while hidden and nothing while shown.
local function transparency(interfaceID, lastStatic, watched)
  -- Original alpha of each component while held transparent, keyed "static" or "static:category:dynamic".
  local originals = nil

  -- Calls fn(key, component) for every component, dynamic children included, since a component's alpha
  -- does not reach its children.
  local function each(fn)
    for staticID = 0, lastStatic do
      local c = ui.Interfaces:GetComponent(interfaceID, staticID)
      if c ~= nil then
        fn(tostring(staticID), c)
        pcall(function()
          c:IterateDynamicComponents(function(child)
            fn(staticID .. ":" .. tostring(read(child, "categoryID")) .. ":" .. tostring(read(child, "dynamicID")),
              child)
            return false
          end)
        end)
      end
    end
  end

  local function setAlpha(transparent)
    each(function(key, c)
      if transparent and originals[key] == nil then originals[key] = read(c, "alpha") or 1 end
      local alpha = transparent and 0 or originals[key] or 1
      pcall(function() c.alpha = alpha end)
    end)
  end

  local t = {}

  function t.keep()
    if originals == nil then return end
    for _, at in ipairs(watched) do
      local c
      if at[2] ~= nil then
        c = ui.Interfaces:GetComponent(interfaceID, at[1], at[2], at[3])
      else
        c = ui.Interfaces:GetComponent(interfaceID, at[1])
      end
      if opaque(c) then
        setAlpha(true)
        return
      end
    end
  end

  function t.hide(hidden)
    if hidden then
      originals = originals or {}
      t.keep()
    elseif originals ~= nil then
      setAlpha(false)
      originals = nil
    end
  end

  return t
end

-- The target panel rebuilds its frame sprites opaque between server ticks. A visible name label means the
-- panel reloaded, and a visible background means its frame was rebuilt.
local targetPanel = transparency(TARGET_PANEL, TARGET_LAST_STATIC, { { TARGET_NAME }, { TARGET_BACKGROUND, 0, 0 } })

-- Runs on every rendered frame, making the target panel transparent again when the client rebuilt it.
adapter.keepTargetPanelHidden = targetPanel.keep

-- Runs each server tick with whether the native target panel should be hidden. Hiding sets alpha 0,
-- because hidden stops the panel filling its debuff slots, which targetReads relies on.
adapter.hideTargetPanel = targetPanel.hide

-- The game's cast bar, held transparent so the client's own showing and hiding of it is left alone and
-- restoring never shows a bar the client hid. A visible root or time label means the client rebuilt it.
local castBar = transparency(CAST_BAR, CAST_BAR_LAST_STATIC, { { 0 }, { CAST_BAR_DURATION } })

-- Runs on every rendered frame, making the game's cast bar transparent again when the client rebuilt it.
adapter.keepCastBarHidden = castBar.keep

-- Runs each server tick with whether the game's cast bar should be hidden. false restores its alphas.
adapter.hideCastBar = castBar.hide

-- Original alpha of each buff bar component while RuneUI hides the bars, keyed "bar:static" or
-- "bar:static:category:dynamic", and the keys of the icons it set hidden.
local barAlpha, barHidden = nil, nil
-- Rendered frames since the last server tick, counted up to FILL_FRAMES.
local framesSinceTick = FILL_FRAMES

-- Hides c: a slot's icon :0:0 and :0:2 take hidden, which the client undoes only when it fills the slot.
-- An icon already hidden is left alone, so restoring never shows one the client hid. Everything else takes
-- alpha 0, which the client resets every few frames on an icon but not on these.
local function hideBarComponent(key, c, icon)
  if icon then
    if read(c, "hidden") ~= false then return end
    barHidden[key] = true
    pcall(function() c.hidden = true end)
    return
  end
  if barAlpha[key] == nil then barAlpha[key] = read(c, "alpha") or 1 end
  pcall(function() c.alpha = 0 end)
end

-- Calls fn(key, child, icon) for each dynamic child of bar's static staticID.
local function eachSlotChild(bar, staticID, c, fn)
  local slot = staticID >= bar.first and staticID <= bar.last
  pcall(function()
    c:IterateDynamicComponents(function(child)
      local category, dynamic = read(child, "categoryID"), read(child, "dynamicID")
      fn(bar.id .. ":" .. staticID .. ":" .. tostring(category) .. ":" .. tostring(dynamic), child,
        slot and category == 0 and (dynamic == 0 or dynamic == 2))
      return false
    end)
  end)
end

-- Calls fn(key, component, icon) for every component of both buff bars, dynamic children included, since
-- a component's alpha does not reach its children.
local function eachBarComponent(fn)
  for _, bar in pairs(BUFF_BARS) do
    for staticID = 0, bar.lastStatic do
      local c = ui.Interfaces:GetComponent(bar.id, staticID)
      if c ~= nil then
        fn(bar.id .. ":" .. staticID, c, false)
        eachSlotChild(bar, staticID, c, fn)
      end
    end
  end
end

-- Runs on every rendered frame while the buff bars are hidden. For a few frames after each server tick it
-- reads the icon of each slot up to watchLast, and hides a slot again once the client fills it, which
-- shows its icon and makes its label and frame opaque. No reads otherwise.
function adapter.keepBuffBarsHidden()
  if barAlpha == nil or framesSinceTick >= FILL_FRAMES then return end
  framesSinceTick = framesSinceTick + 1
  for _, bar in pairs(BUFF_BARS) do
    for staticID = bar.first, bar.watchLast or bar.last do
      if read(ui.Interfaces:GetComponent(bar.id, staticID, 0, 0), "hidden") == false then
        eachSlotChild(bar, staticID, ui.Interfaces:GetComponent(bar.id, staticID), hideBarComponent)
      end
    end
  end
end

-- Runs each server tick with whether the native buff and debuff bars should be hidden. Their labels keep
-- counting and their slots keep filling while hidden, which auraReads relies on. A bar whose first static
-- reads opaque reloaded, so it is hidden again whole. false restores what RuneUI changed.
function adapter.hideBuffBars(hidden)
  if hidden then
    framesSinceTick = 0
    if barAlpha == nil then
      barAlpha, barHidden = {}, {}
      eachBarComponent(hideBarComponent)
      return
    end
    for _, bar in pairs(BUFF_BARS) do
      local root = ui.Interfaces:GetComponent(bar.id, 0)
      local alpha = root and read(root, "alpha")
      if alpha ~= nil and alpha > 0 then
        eachBarComponent(hideBarComponent)
        return
      end
    end
  elseif barAlpha ~= nil then
    eachBarComponent(function(key, c)
      if barHidden[key] then pcall(function() c.hidden = false end) end
      local alpha = barAlpha[key]
      if alpha ~= nil then pcall(function() c.alpha = alpha end) end
    end)
    barAlpha, barHidden = nil, nil
  end
end

local iconParams = nil

local function readIconStruct(structID)
  iconParams = iconParams or {
    icon = config.Param.COMBATV2_ABILITY_ICON,
    name = config.Param.COMBATV2_ABILITY_NAME,
    info = config.Param.COMBATV2_ABILITY_INFO,
  }
  local struct = config.Struct.FromID(structID)
  if struct == nil then return nil end
  local configName = struct.configName
  if type(configName) ~= "string" or configName:sub(1, 9) ~= "COMBATV2_" then return nil end
  if not struct:HasParam(iconParams.icon) or not struct:HasParam(iconParams.name) then return nil end
  return {
    configName = configName,
    icon = struct:GetParamValue(iconParams.icon),
    name = struct:GetParamValue(iconParams.name),
    info = iconParams.info ~= nil and struct:HasParam(iconParams.info) and struct:GetParamValue(iconParams.info) or nil,
  }
end

-- The COMBATV2_ struct at structID as { configName, icon, name, info }, or nil, for src/icons and the struct
-- id COMBATV2_CHANNEL_ABILITY_STRUCT holds. Reads only these params, since reading some others logs a
-- conversion error to the console.
function adapter.iconStruct(structID)
  local ok, struct = pcall(readIconStruct, structID)
  return ok and struct or nil
end

local function readSpriteName(sprite)
  return id.Sprite.FromID(sprite)
end

-- src/icons sprite names: the config name of a sprite id, or nil.
function adapter.spriteName(sprite)
  local ok, name = pcall(readSpriteName, sprite)
  return ok and type(name) == "string" and name or nil
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
