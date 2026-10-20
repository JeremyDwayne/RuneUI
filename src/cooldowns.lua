-- Tracks ability cooldown windows from var changes and builds cooldown group tiles.
-- Pure: main.lua feeds it var changes and server ticks, and src/adapter supplies the just-used ability.
local cooldowns = {}

-- Abilities with a cooldown of at least this many ticks, 30 seconds, default to the cooldowns group.
local LONG_COOLDOWN_TICKS = 50

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

  -- A _START var holds the server tick its ability fired, which also keeps the clock in step.
  function tracker.onVar(name, old, new)
    if old == new then return end
    if name == "COMBATV2_JUST_USED_ABILITY" then
      justUsedChanged = true
      return
    end
    local key, edge = name:match("^COMBATV2_COOLDOWN_(.+)_(%u+)$")
    if edge == "START" then
      ability(key).start = new
      now = new
      startedThisTick[#startedThisTick + 1] = key
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
      abilities[key].name, abilities[key].icon = info.name, info.icon
      learned = { key = key, name = info.name, icon = info.icon }
    end
    startedThisTick = {}
    justUsedChanged = false
    if now ~= nil then now = now + 1 end
    return learned
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

  function tracker.defaultGroups()
    local groups = { rotation = {}, cooldowns = {} }
    for _, key in ipairs(order) do
      local a = abilities[key]
      local long = a.start ~= nil and a.finish ~= nil and a.finish - a.start >= LONG_COOLDOWN_TICKS
      table.insert(long and groups.cooldowns or groups.rotation, key)
    end
    return groups
  end

  -- keys: ability keys in display order. keybinds: { [iconSpriteID] = "Q" } from the native bars.
  function tracker.tiles(keys, keybinds)
    local tiles = {}
    for _, key in ipairs(keys) do
      local a = abilities[key] or {}
      local name = a.name or nameFromKey(key)
      local left = (now ~= nil and a.finish ~= nil) and a.finish - now or 0
      tiles[#tiles + 1] = {
        key = key,
        name = name,
        initials = initials(name),
        icon = a.icon,
        keybind = a.icon and keybinds[a.icon],
        ready = left <= 0,
        seconds = left > 0 and secondsLeft(left) or nil,
      }
    end
    return tiles
  end

  return tracker
end

return cooldowns
