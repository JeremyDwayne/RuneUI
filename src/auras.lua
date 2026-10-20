-- Tracks buffs and debuffs from the native bars' slot labels and builds the four aura rows.
-- Pure: main.lua feeds it src/adapter's slot reads once per server tick.
local auras = {}

-- Buffs with a first time left of at most this many seconds default to the combat row.
local COMBAT_SECONDS = 60
local MAX_ICONS = 10
-- Time is kept in tenths of a second, so a 0.6 s server tick is a whole number.
local TICK = 6
local UNITS = { m = 60, h = 3600 }
-- An icon is highlighted in the last 10% of its full length, and never later than its last 3 seconds.
local HIGHLIGHT_SECONDS = 3

-- A slot label such as "20<br>(5)", "20(5)", "6m" or "47%" as { seconds, low, text, stacks }: the most and
-- least time left the label can mean. The bars show seconds up to 60 and whole minutes above, so "6m" means
-- 360 to 419 seconds. A label with no timer, such as a percent, a count or an empty one, reads {}.
function auras.parse(label)
  if type(label) ~= "string" then return {} end
  local n, unit, rest = label:match("^(%d+)([mh]?)(.*)$")
  local stacks = rest and (rest:match("^<br>%((%d+)%)$") or rest:match("^%((%d+)%)$"))
  if n == nil or (rest ~= "" and stacks == nil) then return {} end
  local size = UNITS[unit]
  if size == nil then return { seconds = tonumber(n), low = tonumber(n) - 1, text = n, stacks = stacks } end
  return { seconds = tonumber(n) * size + size - 1, low = tonumber(n) * size, text = n .. unit, stacks = stacks }
end

-- The row a buff joins when first seen: "combat", "upkeep", or "hidden" when it has no timer.
local function category(seconds)
  if seconds == nil then return "hidden" end
  return seconds <= COMBAT_SECONDS and "combat" or "upkeep"
end

-- The aura row each buff category shows in; hidden buffs show in none.
local ROWS = { combat = "combatBuffs", upkeep = "upkeepBuffs" }

-- Returns a tracker. onTick takes { buffs, debuffs }, each a list of { sprite, label } in bar order, once
-- per server tick, and returns the buffs it saw appear as { sprite, category }. rows builds the display
-- models.
function auras.tracker()
  local tick = 0
  -- Per bar, { [sprite] = state } for every aura on it last tick, and the sprites in bar order.
  local bars = { buffs = { states = {}, order = {} }, debuffs = { states = {}, order = {} } }

  -- Moves state to what label shows: a time above the label's last starts the swipe again, a lower one
  -- resyncs it, and an unchanged one counts down a tick, no further than the least time the label can mean.
  local function follow(state, label)
    if label == state.label then
      if state.left ~= nil then state.left = math.max(state.left - TICK, state.low * 10) end
      return
    end
    local parsed = auras.parse(label)
    state.label, state.text, state.stacks = label, parsed.text, parsed.stacks
    if parsed.seconds == nil then
      state.seconds, state.left = nil, nil
      return
    end
    local left = parsed.seconds * 10
    if state.left == nil or parsed.seconds > state.seconds then
      state.full, state.started = math.max(state.full or 0, left), tick
    end
    state.seconds, state.low, state.left = parsed.seconds, parsed.low, left
  end

  local function update(bar, reads, appeared)
    local states, order = {}, {}
    for _, read in ipairs(reads) do
      local state = states[read.sprite]
      if state == nil then
        state = bar.states[read.sprite]
        if state == nil then
          state = { sprite = read.sprite }
          follow(state, read.label)
          state.category = category(state.seconds)
          if appeared ~= nil then appeared[#appeared + 1] = { sprite = read.sprite, category = state.category } end
        else
          follow(state, read.label)
        end
        states[read.sprite] = state
        order[#order + 1] = read.sprite
      end
    end
    bar.states, bar.order = states, order
  end

  local tracker = {}

  function tracker.onTick(reads)
    tick = tick + 1
    local appeared = {}
    update(bars.buffs, reads.buffs, appeared)
    update(bars.debuffs, reads.debuffs)
    return appeared
  end

  -- { sprite, text, stacks, left, full, started, fill, highlight } for state. left and full are seconds, and
  -- started changes only when its swipe restarts. A buff with no timer has only sprite, text and stacks.
  local function model(state)
    local m = { sprite = state.sprite, text = state.text, stacks = state.stacks, highlight = false }
    if state.left ~= nil then
      m.left, m.full, m.started = state.left / 10, state.full / 10, state.started
      m.fill = state.full > 0 and state.left / state.full or 0
      m.highlight = state.left * 10 <= state.full or state.left <= HIGHLIGHT_SECONDS * 10
    end
    return m
  end

  local function add(row, item)
    if #row < MAX_ICONS then row[#row + 1] = item end
  end

  -- categories: { [tostring(sprite)] = "combat" | "upkeep" | "hidden" } from settings; a buff missing from it
  -- goes where its first time left put it. targetDebuffs: target debuff sprites. Returns { targetDebuffs,
  -- playerDebuffs, upkeepBuffs, combatBuffs }, keyed by HUD element, each a list of up to 10 models in bar
  -- order. Target debuffs carry only their sprite.
  function tracker.rows(categories, targetDebuffs)
    local rows = { targetDebuffs = {}, playerDebuffs = {}, upkeepBuffs = {}, combatBuffs = {} }
    for _, sprite in ipairs(targetDebuffs) do add(rows.targetDebuffs, { sprite = sprite }) end
    for _, sprite in ipairs(bars.debuffs.order) do add(rows.playerDebuffs, model(bars.debuffs.states[sprite])) end
    for _, sprite in ipairs(bars.buffs.order) do
      local state = bars.buffs.states[sprite]
      local row = rows[ROWS[categories[tostring(sprite)] or state.category]]
      if row ~= nil then add(row, model(state)) end
    end
    return rows
  end

  return tracker
end

return auras
