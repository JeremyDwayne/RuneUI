-- Tracks the player's current channel, such as Asphyxiate or Rapid Fire, for the cast bar.
-- Pure: main.lua feeds it var changes and server ticks, and src/adapter reads the channelled ability's struct.
local cooldowns = require("src/cooldowns")

local channel = {}

-- END_REASON while a channel runs, and once it finished on its last hit. Any other value, such as 2, cancelled it.
local RUNNING, FINISHED = -1, 1
-- Vars a new channel sends no change for when it repeats the last channel's value.
local HELD = { "COMBATV2_CHANNEL_ABILITY_STRUCT", "COMBATV2_CHANNEL_ABILITY_ITERATIONS" }

-- Returns a tracker. seed takes a function returning a var's value at load. onVar takes every var change, onTick
-- runs once per server tick, and changed() reports once whether a channel var changed since the last call. read
-- takes a function returning { configName, name, icon } for a struct id, or nil, and calls it until it returns the
-- current channel's info. model() returns { start, name, icon, style, duration, ticksLeft, hits } while the game's
-- own cast bar shows the channel, else nil: start is its first server tick, style its ability's src/cooldowns
-- combat style or nil, duration (END - START + 1) x 0.6 s, as the game's label first reads, ticksLeft the ticks its
-- label counts down from that, and hits the seconds after START of each hit, one on START and one every RATE ticks
-- after up to END, or nil when the iterations are unknown. On the tick a channel is cancelled, model() returns
-- { start, cancelled = true }.
function channel.tracker()
  local start, finish, struct, iterations, reason = nil, nil, nil, nil, nil
  -- Server ticks since START, and the count when the channel was cancelled. The channel's vars arrive right after
  -- the server tick of START.
  local elapsed, cancelledAt = 0, nil
  local changed = false
  -- The ability's info and combat style, read once per channel: the struct changes on some channels' last hit.
  local info, infoStart, style = nil, nil, nil

  local tracker = {}

  -- START and END hold the channel's first and last server tick and change together when one starts.
  function tracker.onVar(name, old, new)
    if old == new then
      return
    end
    if name == "COMBATV2_CHANNEL_START" then
      start, elapsed = new, 0
    elseif name == "COMBATV2_CHANNEL_END" then
      finish = new
    elseif name == "COMBATV2_CHANNEL_ABILITY_STRUCT" then
      struct = new
    elseif name == "COMBATV2_CHANNEL_ABILITY_ITERATIONS" then
      iterations = new
    elseif name == "COMBATV2_CHANNEL_END_REASON" then
      reason = new
      cancelledAt = (new ~= RUNNING and new ~= FINISHED) and elapsed or nil
    else
      return
    end
    changed = true
  end

  function tracker.seed(read)
    for _, name in ipairs(HELD) do
      tracker.onVar(name, nil, read(name))
    end
  end

  function tracker.onTick()
    elapsed = elapsed + 1
  end

  function tracker.changed()
    local was = changed
    changed = false
    return was
  end

  function tracker.read(readStruct)
    if reason == RUNNING and struct ~= nil and start ~= nil and infoStart ~= start then
      info = readStruct(struct)
      if info ~= nil then
        infoStart = start
        style = cooldowns.styleOf((tostring(info.configName):gsub("^COMBATV2_ABILITY_", "")))
      end
    end
  end

  -- Seconds after START of each of iterations + 1 hits spread evenly over ticks, or nil.
  local function hitTimes(ticks)
    if iterations == nil or iterations < 1 then
      return nil
    end
    local times = {}
    for k = 0, iterations do
      times[k + 1] = k * ticks * 6 / (iterations * 10)
    end
    return times
  end

  -- An END from the previous channel sits before the new START until the new END arrives. The game finishes a
  -- channel on its last hit, at END, and its cast bar shows 0.6s for one more tick.
  function tracker.model()
    if start == nil then
      return nil
    end
    if cancelledAt ~= nil then
      return cancelledAt == elapsed and { start = start, cancelled = true } or nil
    end
    if (reason ~= RUNNING and reason ~= FINISHED) or finish == nil or finish <= start then
      return nil
    end
    local total = finish - start + 1
    if elapsed >= total then
      return nil
    end
    local found = infoStart == start and info or nil
    return {
      start = start,
      name = found and found.name,
      icon = found and found.icon,
      style = found and style,
      duration = total * 6 / 10,
      ticksLeft = total - elapsed,
      hits = hitTimes(finish - start),
    }
  end

  return tracker
end

return channel
