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
-- A seconds label unchanged for this many ticks after it first shows is a count, such as stacks, not a timer.
local COUNT_REPEATS = 3

-- A slot label such as "20<br>(5)", "20(5)", "6m" or "47%" as { seconds, low, text, stacks }: the most and
-- least time left the label can mean. The bars show seconds up to 60 and whole minutes above, so "6m" means
-- 360 to 419 seconds. A label with no timer, such as a percent, a count or an empty one, reads {}.
function auras.parse(label)
  if type(label) ~= "string" then
    return {}
  end
  local n, unit, rest = label:match("^(%d+)([mh]?)(.*)$")
  local stacks = rest and (rest:match("^<br>%((%d+)%)$") or rest:match("^%((%d+)%)$"))
  if n == nil or (rest ~= "" and stacks == nil) then
    return {}
  end
  local size = UNITS[unit]
  if size == nil then
    return { seconds = tonumber(n), low = tonumber(n) - 1, text = n, stacks = stacks }
  end
  return { seconds = tonumber(n) * size + size - 1, low = tonumber(n) * size, text = n .. unit, stacks = stacks }
end

-- The row a buff joins when first seen: "combat", "upkeep", or "hidden" when it has no timer.
local function category(seconds)
  if seconds == nil then
    return "hidden"
  end
  return seconds <= COMBAT_SECONDS and "combat" or "upkeep"
end

-- The aura row each buff category shows in; hidden buffs show in none.
local ROWS = { combat = "combatBuffs", upkeep = "upkeepBuffs" }

-- Returns a tracker. onTick takes { buffs, debuffs }, each a list of { sprite, label } in bar order, once
-- per server tick, and returns the buffs it saw appear as { sprite, category }. rows builds the display
-- models.
function auras.tracker()
  -- Per bar, { [sprite] = state } for every aura on it last tick, and the sprites in bar order.
  local bars = { buffs = { states = {}, order = {} }, debuffs = { states = {}, order = {} } }

  -- Moves state to what label shows: a new time replaces the count, raising full when it is the longest seen,
  -- and an unchanged label counts down a tick, no further than the least time the label can mean. A seconds
  -- label that holds for COUNT_REPEATS ticks marks the aura a count for good, and fell marks a time that dropped.
  local function follow(state, label)
    if label == state.label then
      state.still = state.still + 1
      if state.still >= COUNT_REPEATS and state.seconds ~= nil and state.low == state.seconds - 1 then
        state.count = true
      end
      if state.left ~= nil then
        state.left = math.max(state.left - TICK, state.low * 10)
      end
      return
    end
    local parsed = auras.parse(label)
    if parsed.seconds ~= nil and state.seconds ~= nil and parsed.seconds < state.seconds then
      state.fell = true
    end
    state.label = label
    state.text = parsed.text
    state.stacks = parsed.stacks
    state.still = 0
    if parsed.seconds == nil then
      state.seconds = nil
      state.left = nil
      return
    end
    local left = parsed.seconds * 10
    state.full = math.max(state.full or 0, left)
    state.seconds = parsed.seconds
    state.low = parsed.low
    state.left = left
  end

  local function update(bar, reads, appeared)
    local states = {}
    local order = {}
    for _, read in ipairs(reads) do
      local state = states[read.sprite]
      if state == nil then
        state = bar.states[read.sprite]
        if state == nil then
          state = { sprite = read.sprite, still = 0 }
          follow(state, read.label)
          state.category = category(state.seconds)
          if appeared ~= nil then
            appeared[#appeared + 1] = { sprite = read.sprite, category = state.category }
          end
        else
          follow(state, read.label)
        end
        states[read.sprite] = state
        order[#order + 1] = read.sprite
      end
    end
    bar.states = states
    bar.order = order
  end

  local tracker = {}

  function tracker.onTick(reads)
    local appeared = {}
    update(bars.buffs, reads.buffs, appeared)
    update(bars.debuffs, reads.debuffs)
    return appeared
  end

  -- { sprite, text, stacks, left, full, fill, highlight } for state. left and full are seconds, full the
  -- longest time left seen since the aura appeared. A buff with no timer, or a count, has only sprite, text and
  -- stacks. Only a time seen falling is highlighted.
  local function model(state)
    local m = { sprite = state.sprite, text = state.text, stacks = state.stacks, highlight = false }
    if state.left ~= nil and not state.count then
      m.left = state.left / 10
      m.full = state.full / 10
      m.fill = state.full > 0 and state.left / state.full or 0
      m.highlight = state.fell == true and (state.left * 10 <= state.full or state.left <= HIGHLIGHT_SECONDS * 10)
    end
    return m
  end

  -- Sorts row's models by rank, a { [sprite] = position } map, keeping the row's order among unranked ones,
  -- then drops all but the first MAX_ICONS.
  local function finish(row, rank)
    if #row < 2 then
      return
    end
    local at = {}
    for i, m in ipairs(row) do
      at[m] = i
    end
    local huge = math.huge
    table.sort(row, function(a, b)
      local ra = rank[a.sprite] or huge
      local rb = rank[b.sprite] or huge
      if ra ~= rb then
        return ra < rb
      end
      return at[a] < at[b]
    end)
    for i = #row, MAX_ICONS + 1, -1 do
      row[i] = nil
    end
  end

  -- categories: { [tostring(sprite)] = "combat" | "upkeep" | "hidden" } from settings; a buff missing from it
  -- goes where its first time left put it. targetDebuffs: target debuff sprites. filters: { tracked(kind,
  -- sprite), keepUp, hasTarget, rank(kind) }, where tracked says whether the "target" or "player" debuff row
  -- shows a sprite, keepUp is settings' { [tostring(sprite)] = true }, and rank returns the "buffs", "target"
  -- or "player" sorted order as { [sprite] = position }. Returns { targetDebuffs, playerDebuffs, upkeepBuffs,
  -- combatBuffs }, keyed by HUD element, each a list of up to 10 models in rank order, with unranked icons
  -- after in bar order. Target debuffs carry only their sprite. While hasTarget, each Keep up upkeep buff
  -- missing from the bar joins the upkeep row as { sprite, missing = true }.
  function tracker.rows(categories, targetDebuffs, filters)
    local rows = { targetDebuffs = {}, playerDebuffs = {}, upkeepBuffs = {}, combatBuffs = {} }
    for _, sprite in ipairs(targetDebuffs) do
      if filters.tracked("target", sprite) then
        rows.targetDebuffs[#rows.targetDebuffs + 1] = { sprite = sprite }
      end
    end
    for _, sprite in ipairs(bars.debuffs.order) do
      if filters.tracked("player", sprite) then
        rows.playerDebuffs[#rows.playerDebuffs + 1] = model(bars.debuffs.states[sprite])
      end
    end
    for _, sprite in ipairs(bars.buffs.order) do
      local state = bars.buffs.states[sprite]
      local row = rows[ROWS[categories[tostring(sprite)] or state.category]]
      if row ~= nil then
        row[#row + 1] = model(state)
      end
    end
    if filters.hasTarget then
      local missing = {}
      for key in pairs(filters.keepUp) do
        local sprite = tonumber(key)
        if categories[key] == "upkeep" and bars.buffs.states[sprite] == nil then
          missing[#missing + 1] = sprite
        end
      end
      table.sort(missing)
      local upkeep = rows.upkeepBuffs
      for _, sprite in ipairs(missing) do
        upkeep[#upkeep + 1] = { sprite = sprite, missing = true, highlight = false }
      end
    end
    finish(rows.targetDebuffs, filters.rank("target"))
    finish(rows.playerDebuffs, filters.rank("player"))
    finish(rows.upkeepBuffs, filters.rank("buffs"))
    finish(rows.combatBuffs, filters.rank("buffs"))
    return rows
  end

  return tracker
end

return auras
