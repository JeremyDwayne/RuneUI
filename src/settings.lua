-- Everything RuneUI saves, loaded as one table: the HUD layout from src/savedlayout, cooldown groups and
-- learned abilities from src/savedgroups, the appearance and adrenaline markers from src/savedappearance, and
-- aura rows, tracking and order from src/savedauras. Pure: reads and writes go through a store with get(key)
-- and set(key, table), so specs use a fake.
local savedappearance = require("src/savedappearance")
local savedauras = require("src/savedauras")
local savedgroups = require("src/savedgroups")
local savedlayout = require("src/savedlayout")

local settings = {}

-- Loads saved settings from store, dropping unknown keys and malformed values. windowHeight, the game window's
-- height in UI units, places the default HUD; specs leave it out. Returns the four parts' functions in one table.
function settings.load(store, windowHeight)
  local s = {}
  local parts = {
    savedlayout.load(store, windowHeight),
    savedgroups.load(store),
    savedappearance.load(store),
    savedauras.load(store),
  }
  for _, part in ipairs(parts) do
    for name, fn in pairs(part) do
      s[name] = fn
    end
  end
  return s
end

return settings
