-- Saved aura choices: the row each buff icon belongs to, which debuffs each debuff row tracks, the upkeep buffs
-- kept up, and the order of each kind of aura icon. Pure: reads and writes go through a store with get(key) and
-- set(key, table), so specs use a fake.
local savedauras = {}

-- Aura rows a buff icon can be sorted into.
local AURA_CATEGORIES = { combat = true, upkeep = true, hidden = true }
-- Saved keys of each debuff row's tracked choices, by kind.
local TRACKED_KEYS = { target = "trackedTarget", player = "trackedPlayer" }
-- Saved keys of each aura kind's icon order.
local ORDER_KEYS = { buffs = "orderBuffs", target = "orderTarget", player = "orderPlayer" }

-- An icon map, { [tostring(sprite)] = value }, keeping entries whose key is a whole number, a sprite id or minus an
-- item id, and whose value passes valid.
local function readMap(saved, valid)
  local out = {}
  if type(saved) ~= "table" then
    return out
  end
  for sprite, value in pairs(saved) do
    local n = math.tointeger(tonumber(sprite))
    if n ~= nil and valid(value) then
      out[tostring(n)] = value
    end
  end
  return out
end

local function isChoice(value)
  return type(value) == "boolean" or value == "seen"
end

local function isTrue(value)
  return value == true
end

local function isCategory(value)
  return AURA_CATEGORIES[value] ~= nil
end

-- An icon order: a list of whole numbers, each once.
local function readOrder(saved)
  local out = {}
  local seen = {}
  if type(saved) ~= "table" then
    return out
  end
  for _, sprite in ipairs(saved) do
    local n = math.tointeger(sprite)
    if n ~= nil and not seen[n] then
      seen[n] = true
      out[#out + 1] = n
    end
  end
  return out
end

-- Loads the aura choices from store, dropping malformed entries.
function savedauras.load(store)
  local auras = readMap(store.get("auras"), isCategory)
  local tracked = {}
  for kind, key in pairs(TRACKED_KEYS) do
    tracked[kind] = readMap(store.get(key), isChoice)
  end
  local keepUp = readMap(store.get("keepUp"), isTrue)
  local orders = {}
  for kind, key in pairs(ORDER_KEYS) do
    orders[kind] = readOrder(store.get(key))
  end
  -- Counts changes to aura rows, tracking and order, so callers rebuild what depends on them only after one.
  local auraVersion = 0

  local s = {}

  -- { [tostring(sprite)] = "combat" | "upkeep" | "hidden" }: the aura row each buff icon seen so far joins.
  function s.auras()
    return auras
  end

  -- Saves the category of a buff icon seen for the first time. No-op once the icon has one.
  function s.learnAura(sprite, category)
    if auras[tostring(sprite)] == nil then
      s.setAuraCategory(sprite, category)
    end
  end

  -- Moves a buff icon to another aura row.
  function s.setAuraCategory(sprite, category)
    auras[tostring(sprite)] = category
    auraVersion = auraVersion + 1
    store.set("auras", auras)
  end

  -- { [tostring(sprite)] = true | false | "seen" }: the debuffs of kind, "target" or "player", seen or chosen.
  function s.tracked(kind)
    return tracked[kind]
  end

  -- Lists a debuff of kind seen for the first time, with no choice. No-op once listed.
  function s.seeDebuff(kind, sprite)
    if tracked[kind][tostring(sprite)] == nil then
      s.setTracked(kind, sprite, "seen")
    end
  end

  function s.setTracked(kind, sprite, on)
    tracked[kind][tostring(sprite)] = on
    auraVersion = auraVersion + 1
    store.set(TRACKED_KEYS[kind], tracked[kind])
  end

  -- { buffs, target, player }: each kind's icons in the order sorted on the Buffs page.
  function s.orders()
    return orders
  end

  function s.setOrder(kind, list)
    orders[kind] = list
    auraVersion = auraVersion + 1
    store.set(ORDER_KEYS[kind], list)
  end

  -- A number that changes with every aura row, tracking or order change.
  function s.auraVersion()
    return auraVersion
  end

  -- { [tostring(sprite)] = true } for each upkeep buff that keeps a tile while missing.
  function s.keepUp()
    return keepUp
  end

  function s.setKeepUp(sprite, on)
    keepUp[tostring(sprite)] = on or nil
    store.set("keepUp", keepUp)
  end

  return s
end

return savedauras
