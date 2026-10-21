-- Tracks ability cooldown windows from var changes and builds cooldown group tiles.
-- Pure: main.lua feeds it var changes and server ticks, and src/adapter supplies the just-used ability.
local cooldowns = {}

-- Abilities with a cooldown of at least this many ticks, 30 seconds, default to the major group.
local LONG_COOLDOWN_TICKS = 50

-- Cooldown key prefixes that name a combat style. Melee abilities are split by skill, such as
-- STRENGTH_DESTROY; DEFENCE and CONSTITUTION abilities belong to no style.
local STYLES = { MAGIC = "magic", NECROMANCY = "necromancy", RANGED = "ranged", ATTACK = "melee", STRENGTH = "melee" }

-- Combat style by COMBATV2_MAINHAND_STYLE, the main-hand weapon's attack type: 1 magic, 5 and 6 melee, 8 to 10
-- ranged, 37 necromancy. 7, an empty main hand, keeps the current style, since it shows for a tick between two
-- weapons.
cooldowns.ATTACK_STYLES = { [1] = "magic", [5] = "melee", [6] = "melee", [8] = "ranged", [9] = "ranged",
  [10] = "ranged", [37] = "necromancy" }
local BARE_HANDED = 7

-- Cooldown key prefixes of defensive and utility abilities, which default to the shared utility group.
local UTILITY_PREFIXES = { DEFENCE = true, CONSTITUTION = true }

-- Just-used struct keys shared by many abilities, which lend their icon but not their name: every weapon
-- special reports the special attack, whose icon its action bar slot shows.
local GENERIC_STRUCTS = { CONSTITUTION_SPECIAL_ATTACK = true }

-- "MAGIC_SUNSHINE" -> "magic": the combat style a cooldown key belongs to, or nil for a style-free one.
function cooldowns.styleOf(key)
  return STYLES[key:match("^(%u+)_")]
end

-- "MAGIC_DRAGON_BREATH" -> "Dragon Breath": drops the combat style and title-cases the rest.
local function nameFromKey(key)
  local words = {}
  for word in key:gmatch("[^_]+") do words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower() end
  table.remove(words, 1)
  return table.concat(words, " ")
end

-- "Greater Concentrated Blast" -> "GCB", shown on tiles with no icon.
local function initials(name)
  local letters = {}
  for word in name:gmatch("%S+") do letters[#letters + 1] = word:match("%a") end
  return table.concat(letters):sub(1, 3):upper()
end

-- Seconds left, rounded up so a cooling tile never reads 0. Integer maths avoids 0.6 float error.
local function secondsLeft(ticks)
  return math.ceil(ticks * 6 / 10)
end

-- Returns a tracker. onVar takes every numeric var change, onTick runs once per server tick with a
-- function returning the just-used ability as { key, name, icon } or nil, and returns what it learned.
function cooldowns.tracker()
  local abilities = {}
  local order = {}
  local now = nil
  local startedThisTick = {}
  local justUsedChanged = false
  -- The style of the latest styled cooldown to start, and of the worn main-hand weapon.
  local abilityStyle, weaponStyle = nil, nil
  -- The style current when each style-free key, such as a weapon special, last started.
  local firedStyle = {}

  local fired = {}

  local function ability(key)
    abilities[key] = abilities[key] or {}
    if not fired[key] then
      fired[key] = true
      order[#order + 1] = key
    end
    return abilities[key]
  end

  local tracker = {}

  -- A _START var holds the server tick its ability fired, which also keeps the clock in step. Weapon
  -- specials such as Instability use COMBATV2_ABILITY_WEAPON_COOLDOWN_<NAME> vars and take the key
  -- WEAPON_<NAME>. COMBATV2_MAINHAND_STYLE sets the weapon's style.
  function tracker.onVar(name, old, new)
    if old == new then return end
    if name == "COMBATV2_JUST_USED_ABILITY" then
      justUsedChanged = true
      return
    end
    if name == "COMBATV2_MAINHAND_STYLE" then
      if new ~= BARE_HANDED then weaponStyle = cooldowns.ATTACK_STYLES[new] end
      return
    end
    local key, edge = name:match("^COMBATV2_COOLDOWN_(.+)_(%u+)$")
    if key == nil then
      key, edge = name:match("^COMBATV2_ABILITY_WEAPON_COOLDOWN_(.+)_(%u+)$")
      key = key and "WEAPON_" .. key
    end
    if edge == "START" then
      ability(key).start = new
      now = new
      startedThisTick[#startedThisTick + 1] = key
      local keyStyle = cooldowns.styleOf(key)
      abilityStyle = keyStyle or abilityStyle
      if keyStyle == nil then firedStyle[key] = tracker.style() end
    elseif edge == "END" then
      ability(key).finish = new
    end
  end

  -- The cooldown that started this tick for the just-used ability: the only one, or the one whose key
  -- matches the struct's when an ability starts several, such as a conjure and its command.
  local function startedBy(info)
    if #startedThisTick == 1 then return startedThisTick[1] end
    for _, key in ipairs(startedThisTick) do
      if key == info.key then return key end
    end
  end

  -- Names a cooldown that started this tick from the just-used ability, read here because its change
  -- can arrive after the _START change. An unchanged just-used var is stale, so a repeat use keeps the
  -- earlier name. Returns { key, name, icon } when it named one, for saving.
  function tracker.onTick(readJustUsed)
    local info = justUsedChanged and #startedThisTick > 0 and readJustUsed() or nil
    local key = info and startedBy(info)
    local learned = nil
    if key ~= nil then
      local a = abilities[key]
      if not GENERIC_STRUCTS[info.key] then a.name = info.name end
      a.icon = info.icon
      learned = { key = key, name = a.name, icon = a.icon }
    end
    startedThisTick = {}
    justUsedChanged = false
    if now ~= nil then now = now + 1 end
    return learned
  end

  -- The worn weapon's combat style as a STYLES value, else that of the latest started cooldown that has one,
  -- or nil before either.
  function tracker.style()
    return weaponStyle or abilityStyle
  end

  -- Restores saved names and icons, { [key] = { name, icon } }, without adding to known().
  function tracker.seed(saved)
    for key, info in pairs(saved) do
      abilities[key] = abilities[key] or {}
      abilities[key].name, abilities[key].icon = info.name, info.icon
    end
  end

  -- Ability keys such as "MAGIC_DRAGON_BREATH" in the order they first fired.
  function tracker.known()
    return { table.unpack(order) }
  end

  -- { major, rotation, utility } key lists for style, filled in firing order: defensive and utility
  -- abilities of any style in utility, then this style's weapon specials and 30 s cooldowns in major and the
  -- rest in rotation. A style-free key counts as the style that was current when it fired.
  function tracker.defaultGroups(style)
    local groups = { major = {}, rotation = {}, utility = {} }
    for _, key in ipairs(order) do
      local a = abilities[key]
      if UTILITY_PREFIXES[key:match("^(%u+)_")] then
        table.insert(groups.utility, key)
      elseif (cooldowns.styleOf(key) or firedStyle[key]) == style then
        local long = a.start ~= nil and a.finish ~= nil and a.finish - a.start >= LONG_COOLDOWN_TICKS
        table.insert((long or key:match("^WEAPON_")) and groups.major or groups.rotation, key)
      end
    end
    return groups
  end

  -- keys: ability keys in display order. slots: { [iconSpriteID] = { keybind, usable } } from the native
  -- bars. A tile with no matching slot counts as usable.
  function tracker.tiles(keys, slots)
    local tiles = {}
    for _, key in ipairs(keys) do
      local a = abilities[key] or {}
      local name = a.name or nameFromKey(key)
      local left = (now ~= nil and a.finish ~= nil) and a.finish - now or 0
      local slot = a.icon and slots[a.icon]
      tiles[#tiles + 1] = {
        key = key,
        name = name,
        initials = initials(name),
        icon = a.icon,
        keybind = slot and slot.keybind,
        usable = not slot or slot.usable,
        ready = left <= 0,
        seconds = left > 0 and secondsLeft(left) or nil,
        cooldown = (a.start ~= nil and a.finish ~= nil) and secondsLeft(a.finish - a.start) or nil,
      }
    end
    return tiles
  end

  return tracker
end

return cooldowns
