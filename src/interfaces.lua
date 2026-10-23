-- Where RuneUI finds what it reads and restyles in the game's own interfaces, and a guarded read of a game
-- component's field. src/adapter reads through this map and src/gameui restyles through it.
local interfaces = {}

-- The main action bar, whose stat labels hold the player's maximum lifepoints and prayer.
interfaces.MAIN_BAR = 1430
interfaces.LIFEPOINTS_LABEL = { 9, 0, 8 }
interfaces.PRAYER_LABEL = { 16, 0, 8 }
-- The main bar's stat bars, which a window resize rebuilds opaque.
interfaces.STAT_BARS = { 9, 16, 22, 57 }
-- The main bar's lock button, which takes hover without the bar's root seeing it.
interfaces.MAIN_LOCK = { 269, 270 }

-- Native action bars 1 to 5, the main bar first, each with its first slot background ID and highest static ID.
-- Slots are SLOT_STRIDE IDs apart, with the button at +1, the icon sprite at +2 and the keybind label at +9.
-- The client tints the icon SLOT_DIM while its ability can't be cast.
interfaces.ACTION_BARS = {
  { id = 1430, first = 64, last = 270 },
  { id = 1670, first = 19, last = 198 },
  { id = 1671, first = 17, last = 198 },
  { id = 1672, first = 14, last = 193 },
  { id = 1673, first = 14, last = 193 },
}
interfaces.SLOTS_PER_BAR = 14
interfaces.SLOT_STRIDE = 13
interfaces.SLOT_BUTTON = 1
interfaces.SLOT_ICON = 2
interfaces.SLOT_KEYBIND = 9
interfaces.SLOT_DIM = 0x333333

-- The window frames every action bar sits in: a bar root's parentStatic is its window's content static, with
-- the background two statics before it, the border one before and the settings button one after.
interfaces.WINDOWS = 1477

-- The target panel: its highest static ID, its name and lifepoints labels, its background sprite, dynamic
-- child :25:0:0, which the client rebuilds opaque on its own, and its debuff icon sprites every 3 static IDs
-- from :38 to :71. A slot is empty when its sprite is -1 or it reads not visibleGlobal: an expired or
-- switched-away debuff keeps its sprite while invisible.
interfaces.TARGET_PANEL = 1490
interfaces.TARGET_LAST_STATIC = 80
interfaces.TARGET_NAME = 21
interfaces.TARGET_LIFEPOINTS = 34
interfaces.TARGET_BACKGROUND = 25
interfaces.DEBUFF_FIRST = 38
interfaces.DEBUFF_LAST = 71
interfaces.DEBUFF_STEP = 3

-- The game's cast bar: its highest static ID, its time left label and the glow on its spark, whose alpha the
-- client animates.
interfaces.CAST_BAR = 764
interfaces.CAST_BAR_LAST_STATIC = 37
interfaces.CAST_BAR_DURATION = 5
interfaces.CAST_BAR_GLOW = 19

-- The buff bar and debuff bar share a layout: slot :<n>:0:0 holds the icon sprite, :<n>:0:1 the label,
-- :<n>:0:2 and :<n>:0:3 its frame. An icon showing an item reads sprite -1, and a slot the player's buff
-- settings hide reads its label not visibleGlobal. lastStatic is each bar's highest static ID. watchLast is
-- the last slot a buff can fill next: src/adapter sets it from the last filled slot each tick, and src/gameui
-- watches up to it after each tick while the bars are hidden.
interfaces.BUFF_BARS = {
  buffs = { id = 284, first = 19, last = 68, lastStatic = 80 },
  debuffs = { id = 291, first = 2, last = 51, lastStatic = 60 },
}

-- config.Inv.WORN, the worn-equipment inventory.
interfaces.WORN_INV = 94

local function index(obj, field)
  return obj[field]
end

-- Reads a field from a game proxy, returning nil when the proxy does not expose it. Always one value, so it is
-- safe as a tostring argument. Runs many times a tick, so it passes index to pcall rather than building a
-- closure per read.
function interfaces.read(obj, field)
  local ok, value = pcall(index, obj, field)
  if ok then
    return value
  end
  return nil
end

-- A static component, or a dynamic child when categoryID is given, or nil while the interface is unloaded.
function interfaces.component(interfaceID, staticID, categoryID, dynamicID)
  if categoryID ~= nil then
    return ui.Interfaces:GetComponent(interfaceID, staticID, categoryID, dynamicID)
  end
  return ui.Interfaces:GetComponent(interfaceID, staticID)
end

-- Text of a label component, or nil when it is missing or empty.
function interfaces.label(interfaceID, staticID, categoryID, dynamicID)
  local c = interfaces.component(interfaceID, staticID, categoryID, dynamicID)
  local text = c and interfaces.read(c, "content")
  if type(text) == "string" and text ~= "" then
    return text
  end
end

return interfaces
