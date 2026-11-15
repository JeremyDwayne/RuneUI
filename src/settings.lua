-- Everything RuneUI saves, loaded as one table: the HUD layout from src/savedlayout, cooldown groups and
-- learned abilities from src/savedgroups, the appearance and adrenaline markers from src/savedappearance, aura
-- rows, tracking and order from src/savedauras, and party roles and tiers from src/savedparty. Pure: reads and
-- writes go through a store with get(key) and set(key, table), so specs use a fake.
local savedappearance = require("src/savedappearance")
local savedauras = require("src/savedauras")
local savedgroups = require("src/savedgroups")
local savedlayout = require("src/savedlayout")
local savedparty = require("src/savedparty")

local settings = {}

-- Loads saved settings from store, dropping unknown keys and malformed values. windowHeight and windowWidth,
-- the game window's size in UI units, place the default HUD; specs leave them out. Returns every part's
-- functions in one table.
function settings.load(store, windowHeight, windowWidth)
  local s = {}
  local parts = {
    savedlayout.load(store, windowHeight, windowWidth),
    savedgroups.load(store),
    savedappearance.load(store),
    savedauras.load(store),
    savedparty.load(store),
  }
  for _, part in ipairs(parts) do
    for name, fn in pairs(part) do
      assert(s[name] == nil, "two saved parts define " .. name)
      s[name] = fn
    end
  end
  return s
end

return settings
