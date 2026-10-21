-- Tracks the player's current channel, such as Asphyxiate or Rapid Fire, for the cast bar.
-- Pure: main.lua feeds it var changes and server ticks, and src/adapter reads the channelled ability's struct.
local channel = {}

-- Returns a tracker. onVar takes every var change; onTick runs once per server tick with a function returning
-- { name, icon } for a struct id, called once per channel. model() returns { name, icon, seconds, fill } while
-- a channel runs, else nil: seconds left, counting down 0.6 a tick from (END - START + 1) x 0.6 as the game's
-- own cast bar does, and fill, the share of the channel spent.
function channel.tracker()
  local start, finish, struct = nil, nil, nil
  -- END_REASON reads -1 while a channel runs.
  local running = false
  -- Ticks since the channel started, and whether it started on the current tick.
  local elapsed, fresh = 0, false
  local info, infoFor = nil, nil

  local tracker = {}

  -- START and END hold the channel's first and last server tick and change together when one starts.
  function tracker.onVar(name, old, new)
    if old == new then return end
    if name == "COMBATV2_CHANNEL_START" then
      start, elapsed, fresh = new, 0, true
    elseif name == "COMBATV2_CHANNEL_END" then
      finish = new
    elseif name == "COMBATV2_CHANNEL_ABILITY_STRUCT" then
      struct = new
    elseif name == "COMBATV2_CHANNEL_END_REASON" then
      running = new == -1
    end
  end

  function tracker.onTick(readStruct)
    if fresh then
      fresh = false
    else
      elapsed = elapsed + 1
    end
    if running and struct ~= nil and infoFor ~= struct then
      infoFor = struct
      info = readStruct(struct)
    end
  end

  function tracker.model()
    if not running or start == nil or finish == nil then return nil end
    local total = finish - start + 1
    if elapsed >= total then return nil end
    local found = infoFor == struct and info or nil
    return {
      name = found and found.name,
      icon = found and found.icon,
      seconds = (total - elapsed) * 6 / 10,
      fill = (elapsed + 1) / total,
    }
  end

  return tracker
end

return channel
