-- Tracks the player's current channel, such as Asphyxiate or Rapid Fire, for the cast bar.
-- Pure: main.lua feeds it var changes, and src/adapter reads the channelled ability's struct.
local channel = {}

-- Returns a tracker. onVar takes every var change, and changed() reports once whether a channel var changed
-- since the last call. read takes a function returning { name, icon } for a struct id, or nil, and calls it
-- until it returns the current channel's info. model() returns { start, name, icon, duration, hits } while a
-- channel runs, else nil: start is its first server tick, duration (END - START + 1) x 0.6 s, as the game's own
-- cast bar reads, and hits the seconds after START of each hit, one on START and one every RATE ticks after up to
-- END, or nil when the iterations are unknown.
function channel.tracker()
  local start, finish, struct, iterations = nil, nil, nil, nil
  -- END_REASON reads -1 while a channel runs.
  local running = false
  local changed = false
  local info, infoFor = nil, nil

  local tracker = {}

  -- START and END hold the channel's first and last server tick and change together when one starts.
  function tracker.onVar(name, old, new)
    if old == new then return end
    if name == "COMBATV2_CHANNEL_START" then
      start = new
    elseif name == "COMBATV2_CHANNEL_END" then
      finish = new
    elseif name == "COMBATV2_CHANNEL_ABILITY_STRUCT" then
      struct = new
    elseif name == "COMBATV2_CHANNEL_ABILITY_ITERATIONS" then
      iterations = new
    elseif name == "COMBATV2_CHANNEL_END_REASON" then
      running = new == -1
    else
      return
    end
    changed = true
  end

  function tracker.changed()
    local was = changed
    changed = false
    return was
  end

  function tracker.read(readStruct)
    if running and struct ~= nil and infoFor ~= struct then
      info = readStruct(struct)
      if info ~= nil then infoFor = struct end
    end
  end

  -- Seconds after START of each of iterations + 1 hits spread evenly over ticks, or nil.
  local function hitTimes(ticks)
    if iterations == nil or iterations < 1 then return nil end
    local times = {}
    for k = 0, iterations do times[k + 1] = k * ticks * 6 / (iterations * 10) end
    return times
  end

  -- An END from the previous channel sits before the new START until the new END arrives.
  function tracker.model()
    if not running or start == nil or finish == nil or finish <= start then return nil end
    local found = infoFor == struct and info or nil
    return {
      start = start,
      name = found and found.name,
      icon = found and found.icon,
      duration = (finish - start + 1) * 6 / 10,
      hits = hitTimes(finish - start),
    }
  end

  return tracker
end

return channel
