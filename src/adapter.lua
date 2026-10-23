-- Reads the game client for the rest of RuneUI: vars, the labels and slots of the game's interfaces, ability
-- and effect structs, worn gear and PersistentDB. Every read goes through pcall and comes back as a plain
-- table or value that the pure modules take, and any read can be nil: interfaces unload, and vars are nil
-- before login. src/gameui restyles the game's interfaces; this module only reads them.
local icons = require("src/icons")
local interfaces = require("src/interfaces")

local adapter = {}

local read = interfaces.read
local component = interfaces.component
local label = interfaces.label
local MAIN_BAR = interfaces.MAIN_BAR
local TARGET_PANEL = interfaces.TARGET_PANEL
local ACTION_BARS = interfaces.ACTION_BARS
local BUFF_BARS = interfaces.BUFF_BARS
-- Empty slots in a row after which a buff bar holds no more icons.
local EMPTY_RUN = 4
-- Slots past the last filled one that a buff can fill at once, such as a potion's several effects.
local FILL_AHEAD = 8
-- Server ticks between reads of every action bar keybind label. A slot's label is also read when its icon
-- changes, so a bar swap shows at once and a rebind within a few seconds.
local KEYBIND_TICKS = 8

local function varValue(domain, name)
  local v = read(var[domain], name)
  if v ~= nil then
    return read(v, "value")
  end
end

-- The value of the VarPlayer var name, such as COMBATV2_MAINHAND_STYLE, or nil before login.
function adapter.playerVar(name)
  return varValue("VarPlayer", name)
end

-- Name, old value and new value of an Event.VarTransmit payload.
function adapter.varChange(e)
  return read(e.var, "configName") or "", e.oldValue, e.newValue
end

-- Player ----------------------------------------------------------------------------------------------------

-- What src/frames builds the player frame from. The maximum lifepoints and prayer come from the main action
-- bar's stat labels, since no var holds them.
function adapter.playerReads()
  local available = Player.IsAvailable()
  local entity = available and Player.GetEntity() or nil
  return {
    available = available,
    name = entity and read(entity, "displayName"),
    lifepoints = varValue("VarPlayer", "LIFEPOINTS"),
    lifepointsLabel = label(MAIN_BAR, table.unpack(interfaces.LIFEPOINTS_LABEL)),
    prayerValue = varValue("VarPlayer", "PRAYER_POINTS_VAR"),
    prayerLabel = label(MAIN_BAR, table.unpack(interfaces.PRAYER_LABEL)),
  }
end

local equipmentWarned = false

-- Whether a Soulbound lantern, augmented or not, is worn. The inventory proxy's valid reads nil, so a nil
-- result from Find is the only failure check.
local function lanternEquipped()
  local ok, result = pcall(function()
    local inv = Inventory.Find(interfaces.WORN_INV)
    if inv == nil then
      return false
    end
    for _, slot in ipairs(inv:GetSlots() or {}) do
      local name = read(slot.obj, "name")
      if type(name) == "string" and name:lower():find("soulbound lantern", 1, true) then
        return true
      end
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

-- Takes InventoryAdded and InventoryUpdated payloads; a worn gear change makes the next read rescan. An
-- inventory without a readable id also rescans, so a misread never leaves the cache stale.
function adapter.inventoryChanged(e)
  local id = read(e.inv, "id")
  if id == nil or id == interfaces.WORN_INV then
    lantern = nil
  end
end

-- What src/frames builds the resource bar from. spenders is frames.SPENDERS; each is read by its var name.
function adapter.resourceReads(spenders)
  local counts = {}
  for _, spender in ipairs(spenders) do
    counts[spender.var] = varValue("VarPlayer", spender.var)
  end
  if lantern == nil then
    lantern = lanternEquipped()
  end
  return { adrenaline = varValue("VarPlayer", "SA_ENERGY"), spenders = counts, lantern = lantern }
end

-- Target ----------------------------------------------------------------------------------------------------

-- The NPCTARGET last named from its entity, and that name.
local namedTarget = nil
local targetName = nil

-- The display name of the NPC NPCList.ByUID finds for target, or nil. A found name is kept until the target
-- changes, and a failed lookup is tried again on the next read.
local function npcName(target)
  if namedTarget ~= target then
    local ok, found = pcall(NPCList.ByUID, target)
    local npc = ok and type(found) == "table" and found[1] or nil
    local name = npc and read(npc, "displayName")
    if type(name) ~= "string" or name == "" then
      return nil
    end
    namedTarget = target
    targetName = name
  end
  return targetName
end

-- What src/frames builds the target frame from. With no target, returns { target } alone and skips the
-- panel's components. effects is the src/targeteffects debuffs() result: while it is complete the debuffs come
-- from it, else from the panel's debuff slots.
function adapter.targetReads(effects)
  local target = varValue("VarPlayer", "NPCTARGET")
  if target == nil or target == -1 then
    namedTarget = nil
    return { target = target }
  end
  local debuffs = effects.sprites
  if not effects.complete then
    debuffs = {}
    for staticID = interfaces.DEBUFF_FIRST, interfaces.DEBUFF_LAST, interfaces.DEBUFF_STEP do
      local c = component(TARGET_PANEL, staticID)
      local sprite = c and read(c, "spriteID")
      if sprite ~= nil and sprite ~= -1 and read(c, "visibleGlobal") ~= false then
        debuffs[#debuffs + 1] = sprite
      end
    end
  end
  return {
    target = target,
    name = npcName(target) or label(TARGET_PANEL, interfaces.TARGET_NAME),
    lifepointsLabel = label(TARGET_PANEL, interfaces.TARGET_LIFEPOINTS),
    healthPercent = varValue("VarClient", "COMBATV2_TARGET_SIDE_PANEL_HEALTH"),
    debuffs = debuffs,
  }
end

-- Buff bars -------------------------------------------------------------------------------------------------

-- { sprite, label } for each shown icon on bar, a BUFF_BARS entry, stopping after EMPTY_RUN empty slots. A slot
-- that shows an item, as an overload's does, reads as minus the item id. Sets the bar's watchLast.
local function barReads(bar)
  local list = {}
  local empty = 0
  local filled = bar.first - 1
  for staticID = bar.first, bar.last do
    local icon = component(bar.id, staticID, 0, 0)
    local sprite = icon and read(icon, "spriteID")
    if sprite == -1 then
      local objID = read(icon, "associatedObjectID")
      if objID ~= nil and objID >= 0 then
        sprite = -objID
      end
    end
    local slotLabel = component(bar.id, staticID, 0, 1)
    local text = slotLabel and read(slotLabel, "content")
    if type(text) ~= "string" or text == "" then
      text = nil
    end
    if (sprite == nil or sprite == -1) and text == nil then
      empty = empty + 1
      if empty >= EMPTY_RUN then
        break
      end
    else
      empty = 0
      filled = staticID
      if sprite ~= nil and sprite ~= -1 and read(slotLabel, "visibleGlobal") ~= false then
        list[#list + 1] = { sprite = sprite, label = text }
      end
    end
  end
  bar.watchLast = math.min(bar.last, filled + FILL_AHEAD)
  return list
end

-- The game's buff and debuff bars as src/auras reads them: { buffs, debuffs }, each a list of { sprite, label }.
function adapter.auraReads()
  return { buffs = barReads(BUFF_BARS.buffs), debuffs = barReads(BUFF_BARS.debuffs) }
end

-- Action bars -----------------------------------------------------------------------------------------------

-- Each bar's slots as last read, { [bar id] = { [slot] = { sprite, keybind } } }, and ticks since every
-- keybind label was read.
local slotCache = {}
local keybindTicks = KEYBIND_TICKS

-- { [iconSpriteID] = { keybind, usable } } for every filled action bar slot. keybind is nil on a slot with none,
-- and usable is false while the client dims the slot's icon. An ability on several bars reads from the first
-- bar, main bar first, whose slot has a keybind. Reads each slot's icon every tick, and its keybind label only
-- when the icon changed or every KEYBIND_TICKS ticks.
function adapter.barSlots()
  keybindTicks = keybindTicks + 1
  local rereadKeybinds = keybindTicks >= KEYBIND_TICKS
  if rereadKeybinds then
    keybindTicks = 0
  end
  local slots = {}
  for _, bar in ipairs(ACTION_BARS) do
    local cache = slotCache[bar.id]
    if cache == nil then
      cache = {}
      slotCache[bar.id] = cache
    end
    for slot = 0, interfaces.SLOTS_PER_BAR - 1 do
      local base = bar.first + slot * interfaces.SLOT_STRIDE
      local icon = component(bar.id, base + interfaces.SLOT_ICON)
      local sprite = icon and read(icon, "spriteID")
      if sprite == nil or sprite == -1 then
        cache[slot] = nil
      else
        local entry = cache[slot]
        if entry == nil or entry.sprite ~= sprite or rereadKeybinds then
          entry = { sprite = sprite, keybind = label(bar.id, base + interfaces.SLOT_KEYBIND) }
          cache[slot] = entry
        end
        if slots[sprite] == nil or slots[sprite].keybind == nil then
          slots[sprite] = { keybind = entry.keybind, usable = read(icon, "rgb") ~= interfaces.SLOT_DIM }
        end
      end
    end
  end
  return slots
end

-- Structs ---------------------------------------------------------------------------------------------------

-- The params an ability or effect struct names and draws itself by. Only these are read: reading some other
-- params logs a conversion error to the console.
local function nameParams()
  return config.Param.COMBATV2_ABILITY_NAME, config.Param.COMBATV2_ABILITY_ICON
end

-- struct's name and icon, each nil when it has none.
local function nameAndIcon(struct)
  local nameParam, iconParam = nameParams()
  local name = nil
  local icon = nil
  if struct:HasParam(nameParam) then
    name = struct:GetParamValue(nameParam)
  end
  if struct:HasParam(iconParam) then
    icon = struct:GetParamValue(iconParam)
  end
  return name, icon
end

local function readJustUsed()
  local struct = varValue("VarClient", "COMBATV2_JUST_USED_ABILITY")
  if struct == nil then
    return nil
  end
  local name, icon = nameAndIcon(struct)
  if name == nil and icon == nil then
    return nil
  end
  return { key = (tostring(read(struct, "configName")):gsub("^COMBATV2_ABILITY_", "")), name = name, icon = icon }
end

-- The ability in COMBATV2_JUST_USED_ABILITY as { key, name, icon }, or nil when it has neither a name nor an
-- icon. key is the struct name without COMBATV2_ABILITY_, matching the cooldown keys in src/cooldowns.
function adapter.justUsed()
  local ok, info = pcall(readJustUsed)
  return ok and info or nil
end

local function readIconStruct(structID)
  local struct = config.Struct.FromID(structID)
  if struct == nil then
    return nil
  end
  local configName = struct.configName
  if type(configName) ~= "string" or not (configName:sub(1, 9) == "COMBATV2_" or configName:sub(1, 6) == "MAGIC_") then
    return nil
  end
  local name, icon = nameAndIcon(struct)
  if name == nil or icon == nil then
    return nil
  end
  return { configName = configName, icon = icon, name = name }
end

-- The combat or spell struct at structID, named COMBATV2_ or MAGIC_ such as MAGIC_VULNERABILITY, as
-- { configName, icon, name }, or nil when it is another kind of struct or lacks either param. Names the
-- channelled ability for src/channel and the just-used ability for src/targeteffects.
function adapter.iconStruct(structID)
  local ok, struct = pcall(readIconStruct, structID)
  return ok and struct or nil
end

-- A struct's COMBATV2_ABILITY_INFO text, or the text after " - " in its name when it has none, or nil.
local function describe(struct)
  if struct == nil then
    return nil
  end
  local info = config.Param.COMBATV2_ABILITY_INFO
  if struct:HasParam(info) then
    return struct:GetParamValue(info)
  end
  local name = config.Param.COMBATV2_ABILITY_NAME
  if name ~= nil and struct:HasParam(name) then
    return select(2, icons.split(tostring(struct:GetParamValue(name))))
  end
end

local function readStructInfo(structID)
  return describe(config.Struct.FromID(structID))
end

-- The description of the struct at structID, for src/icons, or nil.
function adapter.structInfo(structID)
  local ok, info = pcall(readStructInfo, structID)
  return ok and type(info) == "string" and info or nil
end

local function readAbilityInfo(key)
  return describe(config.Struct["COMBATV2_ABILITY_" .. key])
end

-- Ability descriptions by cooldown key, read once; false when the struct is missing or has none.
local abilityInfo = {}

-- The description of the ability struct for a cooldown key such as MAGIC_FINGER_OF_DEATH, for cooldown
-- tooltips, or nil. Each key reads the client once, on its first hover.
function adapter.abilityInfo(key)
  if abilityInfo[key] == nil then
    local ok, info = pcall(readAbilityInfo, key)
    abilityInfo[key] = ok and type(info) == "string" and info or false
  end
  return abilityInfo[key] or nil
end

local function readItemName(objID)
  return config.Obj.FromID(objID).name
end

-- The name of an item id, for src/icons, or nil.
function adapter.itemName(objID)
  local ok, name = pcall(readItemName, objID)
  return ok and type(name) == "string" and name or nil
end

local function readSpriteName(sprite)
  return id.Sprite.FromID(sprite)
end

-- The config name of a sprite id, for src/icons, or nil.
function adapter.spriteName(sprite)
  local ok, name = pcall(readSpriteName, sprite)
  return ok and type(name) == "string" and name or nil
end

-- Saved data ------------------------------------------------------------------------------------------------

-- PersistentDB as the store src/settings loads from and saves to: one structured table per key.
function adapter.store()
  return {
    get = function(key)
      return PersistentDB:GetStructuredData(key)
    end,
    set = function(key, value)
      if PersistentDB:SetStructuredData(key, value) == false then
        log("could not save", key)
      end
    end,
  }
end

return adapter
