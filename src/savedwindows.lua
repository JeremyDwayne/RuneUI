-- Saved window opacity: the game windows given their own background opacity in percent, over the appearance's
-- windowOpacity, keyed by src/windowframes name. A held frame, whose alpha the action bar fade or the group
-- window hold owns, takes none. Pure: reads and writes go through a store with get(key) and set(key, table), so
-- specs use a fake.
local savedappearance = require("src/savedappearance")
local util = require("src/util")
local windowframes = require("src/windowframes")

local savedwindows = {}

-- Frame names that take an opacity.
local FADES = {}
for _, frame in ipairs(windowframes) do
  FADES[frame.name] = not frame.held
end

-- percent as a whole step of savedappearance.OPACITY_STEP from 0 to 100, or nil.
local function opacity(percent)
  percent = type(percent) == "number" and util.whole(percent)
  if math.type(percent) == "integer" and percent >= 0 and percent <= 100 then
    return percent % savedappearance.OPACITY_STEP == 0 and percent or nil
  end
end

-- Loads the opacities from store, dropping unknown windows and malformed values.
function savedwindows.load(store)
  local opacities = {}
  local saved = store.get("windows")
  for name, percent in pairs(type(saved) == "table" and saved or {}) do
    if FADES[name] then
      opacities[name] = opacity(percent)
    end
  end

  local s = {}

  -- { [name] = percent } for every window with its own opacity. Read-only.
  function s.windowOpacities()
    return opacities
  end

  -- Saves name's own opacity, nil dropping it, when it changed and the window takes one.
  function s.setWindowOpacity(name, percent)
    local value = opacity(percent)
    if not FADES[name] or opacities[name] == value or (value == nil and percent ~= nil) then
      return
    end
    opacities[name] = value
    store.set("windows", opacities)
  end

  return s
end

return savedwindows
