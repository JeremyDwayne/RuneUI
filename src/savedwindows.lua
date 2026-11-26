-- Saved window opacity: each game window's background opacity in percent, keyed by its src/windowframes name,
-- for the windows below 100. A held frame, whose alpha the action bar fade or the group window hold owns, takes
-- none. Pure: reads and writes go through a store with get(key) and set(key, table), so specs use a fake.
local savedappearance = require("src/savedappearance")
local util = require("src/util")
local windowframes = require("src/windowframes")

local savedwindows = {}

-- Frame names that take an opacity.
local FADES = {}
for _, frame in ipairs(windowframes) do
  FADES[frame.name] = not frame.held
end

-- Whether percent is a whole step of savedappearance.OPACITY_STEP from 0 to 99.
local function isFaded(percent)
  percent = type(percent) == "number" and util.whole(percent)
  return math.type(percent) == "integer"
    and percent >= 0
    and percent < 100
    and percent % savedappearance.OPACITY_STEP == 0
end

-- Loads the opacities from store, dropping unknown windows and malformed values.
function savedwindows.load(store)
  local opacities = {}
  local saved = store.get("windows")
  for name, percent in pairs(type(saved) == "table" and saved or {}) do
    if FADES[name] and isFaded(percent) then
      opacities[name] = util.whole(percent)
    end
  end

  local s = {}

  -- { [name] = percent } for every window below 100. Read-only.
  function s.windowOpacities()
    return opacities
  end

  -- Saves name's opacity, 100 clearing it, when it changed and the window takes one.
  function s.setWindowOpacity(name, percent)
    local value = isFaded(percent) and util.whole(percent) or nil
    if not FADES[name] or opacities[name] == value or (value == nil and percent ~= 100) then
      return
    end
    opacities[name] = value
    store.set("windows", opacities)
  end

  return s
end

return savedwindows
