-- Tracks ability cooldown windows from var changes and builds cooldown group tiles.
-- Pure: main.lua feeds it var changes and server ticks, and src/adapter supplies the just-used ability.
local cooldowns = {}

-- Cooldown key prefixes that name a combat style. Melee abilities are split by skill, such as
-- STRENGTH_DESTROY, and Dismember's cooldown is MELEE_DISMEMBER; DEFENCE and CONSTITUTION abilities belong to
-- no style.
local STYLES = {
  MAGIC = "magic",
  NECROMANCY = "necromancy",
  RANGED = "ranged",
  ATTACK = "melee",
  STRENGTH = "melee",
  MELEE = "melee",
}

-- Combat style by COMBATV2_MAINHAND_STYLE, the main-hand weapon's attack type: 1 magic, 5 and 6 melee, 8 to 10
-- ranged, 37 necromancy. 7, an empty main hand, keeps the current style, since it shows for a tick between two
-- weapons.
cooldowns.ATTACK_STYLES =
  { [1] = "magic", [5] = "melee", [6] = "melee", [8] = "ranged", [9] = "ranged", [10] = "ranged", [37] = "necromancy" }
local BARE_HANDED = 7
local NO_FORMS = {}
local NO_STACKS = {}

-- Just-used struct keys shared by many abilities, which lend their icon but not their name: every weapon
-- special reports the special attack, whose icon its action bar slot shows.
local GENERIC_STRUCTS = { CONSTITUTION_SPECIAL_ATTACK = true }

-- Abilities with two charges, each recharging on its own timer of RECHARGE_TICKS. The base var pair ends when
-- the first charge returns and the _CHARGE2 pair when the second does.
local CHARGES = { MAGIC_SURGE = true, RANGED_ESCAPE = true }
local RECHARGE_TICKS = 17

-- Abilities cast in stages, by stage count. Each recast opens with COMBATV2_ABILITY_<KEY>_RECAST_<n>_ACTIVE
-- and a short lockout var pair, while the base pair holds the cooldown after the last stage.
local RECASTS = { NECROMANCY_SPECTRAL_SCYTHE = 3, MELEE_DISMEMBER = 3 }

-- Ticks the global cooldown runs after COMBATV2_GLOBAL_COOLDOWN_START, unless COMBATV2_GLOBAL_COOLDOWN_END
-- names a later tick.
local GLOBAL_TICKS = 3

-- "MAGIC_SUNSHINE" -> "magic": the combat style a cooldown key belongs to, or nil for a style-free one.
function cooldowns.styleOf(key)
  return STYLES[key:match("^(%u+)_")]
end

-- "MAGIC_SURGE_CHARGE2" -> "MAGIC_SURGE", "MELEE_DISMEMBER_RECAST_1" -> "MELEE_DISMEMBER": the ability a second
-- charge's or recast stage's cooldown key belongs to. Other keys come back unchanged.
function cooldowns.baseKey(key)
  return key:match("^(.+)_CHARGE2$") or key:match("^(.+)_RECAST_%d+$") or key
end

-- "MAGIC_DRAGON_BREATH" -> "Dragon Breath": drops the combat style and title-cases the rest.
local function nameFromKey(key)
  local words = {}
  for word in key:gmatch("[^_]+") do
    words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower()
  end
  table.remove(words, 1)
  return table.concat(words, " ")
end

-- "Greater Concentrated Blast" -> "GCB", shown on tiles with no icon. Cached by name, since tiles rebuild
-- every tick.
local initialsOf = {}
local function initials(name)
  local cached = initialsOf[name]
  if cached ~= nil then
    return cached
  end
  local letters = {}
  for word in name:gmatch("%S+") do
    letters[#letters + 1] = word:match("%a")
  end
  cached = table.concat(letters):sub(1, 3):upper()
  initialsOf[name] = cached
  return cached
end

-- Seconds left, rounded up so a cooling tile never reads 0. Integer maths avoids 0.6 float error.
local function secondsLeft(ticks)
  return math.ceil(ticks * 6 / 10)
end

-- Returns a tracker. onVar takes every numeric var change, onTick runs once per server tick with a
-- function returning the just-used ability as { key, name, icon } or nil, and returns what it learned.
-- changed() reports once whether a cooldown, the global cooldown, the queued ability or the weapon style changed
-- since the last call.
function cooldowns.tracker()
  local abilities = {}
  local order = {}
  local now = nil
  local startedThisTick = {}
  local justUsedChanged = false
  local changed = false
  -- The style of the latest styled cooldown to start, and of the worn main-hand weapon.
  local abilityStyle = nil
  local weaponStyle = nil
  -- The global cooldown's start and end ticks, and the queued ability's bar and slot as the game sends them.
  local globalStart = nil
  local globalEnd = nil
  local queuedBar = 0
  local queuedSlot = 0

  local fired = {}

  local function ability(key)
    abilities[key] = abilities[key] or {}
    if not fired[key] then
      fired[key] = true
      order[#order + 1] = key
    end
    return abilities[key]
  end

  local function started(key)
    for _, seen in ipairs(startedThisTick) do
      if seen == key then
        return
      end
    end
    startedThisTick[#startedThisTick + 1] = key
  end

  local tracker = {}

  -- A _START var holds the server tick its ability fired, which also keeps the clock in step. Weapon
  -- specials such as Instability use COMBATV2_ABILITY_WEAPON_COOLDOWN_<NAME> vars and take the key
  -- WEAPON_<NAME>. A second charge's and a recast stage's vars fold into their ability's key, and a stage's
  -- start does not count as the ability starting. COMBATV2_MAINHAND_STYLE sets the weapon's style. The global
  -- cooldown's START keeps the clock in step too, and COMBATV2_QUEUED_BAR and _SLOT name the queued ability.
  function tracker.onVar(name, old, new)
    if old == new then
      return
    end
    if name == "COMBATV2_JUST_USED_ABILITY" then
      justUsedChanged = true
      return
    end
    if name == "COMBATV2_GLOBAL_COOLDOWN_START" then
      globalStart = new
      now = new
      changed = true
      return
    end
    if name == "COMBATV2_GLOBAL_COOLDOWN_END" then
      globalEnd = new
      changed = true
      return
    end
    if name == "COMBATV2_QUEUED_BAR" or name == "COMBATV2_QUEUED_SLOT" then
      if name == "COMBATV2_QUEUED_BAR" then
        queuedBar = new
      else
        queuedSlot = new
      end
      changed = true
      return
    end
    if name == "COMBATV2_MAINHAND_STYLE" then
      if new ~= BARE_HANDED then
        weaponStyle = cooldowns.ATTACK_STYLES[new]
      end
      changed = true
      return
    end
    local recastKey, stage = name:match("^COMBATV2_ABILITY_(.+)_RECAST_(%d+)_ACTIVE$")
    if recastKey ~= nil then
      local a = ability(recastKey)
      stage = tonumber(stage)
      if new == 1 then
        a.stage = stage
      elseif a.stage == stage then
        a.stage = nil
      end
      changed = true
      return
    end
    local key, edge = name:match("^COMBATV2_COOLDOWN_(.+)_(%u+)$")
    if key == nil then
      key, edge = name:match("^COMBATV2_ABILITY_WEAPON_COOLDOWN_(.+)_(%u+)$")
      key = key and "WEAPON_" .. key
    end
    if edge ~= "START" and edge ~= "END" then
      return
    end
    changed = true
    local base = cooldowns.baseKey(key)
    local recast = key:match("_RECAST_%d+$") ~= nil
    local a = ability(base)
    if edge == "START" then
      now = new
      abilityStyle = cooldowns.styleOf(base) or abilityStyle
      if key == base then
        a.start = new
      end
      if not recast then
        started(base)
      end
    elseif recast then
      a.lockout = new
    elseif key == base then
      a.finish = new
    else
      a.charged = new
    end
  end

  -- The cooldown that started this tick for the just-used ability: the only one, or the one whose key
  -- matches the struct's when an ability starts several, such as a conjure and its command.
  local function startedBy(info)
    if #startedThisTick == 1 then
      return startedThisTick[1]
    end
    for _, key in ipairs(startedThisTick) do
      if key == info.key then
        return key
      end
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
      if not GENERIC_STRUCTS[info.key] then
        a.name = info.name
      end
      a.icon = info.icon
      learned = { key = key, name = a.name, icon = a.icon }
    end
    startedThisTick = {}
    justUsedChanged = false
    if now ~= nil then
      now = now + 1
    end
    return learned
  end

  function tracker.changed()
    local was = changed
    changed = false
    return was
  end

  -- The queued ability's bar and slot as COMBATV2_QUEUED_BAR and _SLOT hold them, or nil with none queued.
  function tracker.queued()
    if queuedSlot == nil or queuedSlot <= 0 then
      return nil
    end
    return queuedBar, queuedSlot
  end

  -- The worn weapon's combat style as a STYLES value, else that of the latest started cooldown that has one,
  -- or nil before either.
  function tracker.style()
    return weaponStyle or abilityStyle
  end

  -- Restores names and icons, { [key] = { name, icon, forms } }, without adding to known(). A missing field
  -- keeps the one seeded before, so learned names can follow src/presets. forms lists { name, icon } for
  -- every form the ability's bar slot can show, such as Greater Sunshine.
  function tracker.seed(saved)
    for key, info in pairs(saved) do
      local a = abilities[key] or {}
      abilities[key] = a
      a.name = info.name or a.name
      a.icon = info.icon or a.icon
      a.forms = info.forms or a.forms
    end
  end

  -- Ability keys such as "MAGIC_DRAGON_BREATH" in the order they first fired.
  function tracker.known()
    return { table.unpack(order) }
  end

  -- Ticks from now until tick, 0 before the clock starts or with no tick.
  local function ticksTo(tick)
    return (now ~= nil and tick ~= nil) and tick - now or 0
  end

  -- Ticks left and length of the global cooldown, or nil while none runs.
  local function globalCooldown()
    if globalStart == nil then
      return nil
    end
    local finish = (globalEnd ~= nil and globalEnd > globalStart) and globalEnd or globalStart + GLOBAL_TICKS
    local left = ticksTo(finish)
    if left <= 0 then
      return nil
    end
    return left, finish - globalStart
  end

  -- Seconds left and length of the global cooldown at the current server tick, or nil while none runs.
  function tracker.globalCooldown()
    local left, length = globalCooldown()
    if left == nil then
      return nil
    end
    return left * 6 / 10, length * 6 / 10
  end

  -- keys: ability keys in display order. slots: { [iconSpriteID] = { keybind, usable } } from the native
  -- bars. A tile whose icon no slot shows takes the name, icon and slot of the first form a slot does show.
  -- A tile with no matching slot counts as usable. A charge ability's tile is ready while a charge is left,
  -- with charges and count its charges left and, below two, recharge = { remaining, length } in seconds for
  -- the next charge. A recast ability's tile counts down its stage lockout while a stage is open, with count such as
  -- "2/3". stacks: a src/frames resource model's byAbility, whose row a spender ability's tile shows as count
  -- and stacks.
  -- queuedIcon: the icon of the action bar slot whose ability is queued, which marks its tile queued.
  function tracker.tiles(keys, slots, stacks, queuedIcon)
    stacks = stacks or NO_STACKS
    local tiles = {}
    for _, key in ipairs(keys) do
      local a = abilities[key] or {}
      local name = a.name or nameFromKey(key)
      local icon = a.icon
      local left = ticksTo(a.finish)
      local cooldown = (a.start ~= nil and a.finish ~= nil) and secondsLeft(a.finish - a.start) or nil
      local count = nil
      local charges = nil
      local recharge = nil
      local spender = stacks[key]
      if spender ~= nil then
        count = tostring(spender.count)
      elseif CHARGES[key] then
        local second = ticksTo(a.charged)
        charges = 2
        if left > 0 then
          charges = 0
        elseif second > 0 then
          charges = 1
        end
        count = tostring(charges)
        if charges < 2 then
          local returning = charges == 0 and left or second
          recharge = { remaining = returning * 6 / 10, length = RECHARGE_TICKS * 6 / 10 }
        end
        cooldown = secondsLeft(RECHARGE_TICKS)
      elseif RECASTS[key] and a.stage ~= nil then
        left = ticksTo(a.lockout)
        count = (a.stage + 1) .. "/" .. RECASTS[key]
      end
      local slot = icon and slots[icon]
      for _, form in ipairs(slot == nil and a.forms or NO_FORMS) do
        if slots[form.icon] ~= nil then
          name = form.name
          icon = form.icon
          slot = slots[form.icon]
          break
        end
      end
      tiles[#tiles + 1] = {
        key = key,
        name = name,
        initials = initials(name),
        icon = icon,
        keybind = slot and slot.keybind,
        usable = not slot or slot.usable,
        ready = left <= 0,
        remaining = left > 0 and left * 6 / 10 or nil,
        cooldown = cooldown,
        count = count,
        charges = charges,
        recharge = recharge,
        stacks = spender,
        queued = queuedIcon ~= nil and icon == queuedIcon,
      }
    end
    return tiles
  end

  return tracker
end

return cooldowns
