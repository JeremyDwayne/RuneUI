-- Saved appearance: HUD text, unit frame colours, border and size, bar texture, aura bars and their sizes,
-- action bar fading, whether the game's target panel, buff bars and cast bar are hidden, how the HUD shows out
-- of combat, and the adrenaline bar's marker percents. Pure: reads and writes go through a store with get(key)
-- and set(key, table), so specs use a fake.
local autohide = require("src/autohide")
local frames = require("src/frames")
local styling = require("src/style")
local util = require("src/util")

local savedappearance = {}

local whole = util.whole

-- Bar fills: one flat colour, or a gradient from top to bottom or across the bar.
savedappearance.TEXTURES = { "flat", "vertical", "horizontal" }
-- Points every HUD text role moves from its size, and unit frame, adrenaline bar and cast bar sizes.
savedappearance.TEXT_STEP_MIN = -3
savedappearance.TEXT_STEP_MAX = 6
savedappearance.FRAME_WIDTH = { min = 180, max = 400 }
savedappearance.FRAME_HEIGHT = { min = 30, max = 80 }
savedappearance.BAR_WIDTH = { min = 120, max = 500 }
savedappearance.BAR_HEIGHT = { min = 12, max = 40 }
savedappearance.CAST_WIDTH = { min = 150, max = 500 }
savedappearance.CAST_HEIGHT = { min = 14, max = 40 }
-- An own text size in points, for the cast bar and the aura rows.
savedappearance.TEXT_SIZE = {
  min = styling.ROLES.body + savedappearance.TEXT_STEP_MIN,
  max = styling.ROLES.body + savedappearance.TEXT_STEP_MAX,
}
-- Each aura row's default icon size, and the range of one.
savedappearance.AURA_ICONS = { combatBuffs = 36, upkeepBuffs = 26, playerDebuffs = 26, targetDebuffs = 26 }
savedappearance.AURA_ICON = { min = 18, max = 56 }
-- The game's action bars, numbered 1 for the main bar to 5, and the percent their faded opacity moves by.
savedappearance.ACTION_BARS = 5
savedappearance.OPACITY_STEP = 5
-- The HUD's faded opacity out of combat, in percent. Above 0, since a transparent component still takes clicks.
savedappearance.HUD_OPACITY = { min = 10, max = 90 }
local DEFAULT_MARKERS = { threshold = 50, ultimate = 100 }

-- Whether value is a whole number from low to high.
local function wholeIn(value, low, high)
  value = type(value) == "number" and whole(value)
  return math.type(value) == "integer" and value >= low and value <= high
end

-- Checks a saved colour: an id from presets or a 0xRRGGBB number.
local function colour(list)
  return function(value)
    if type(value) == "string" then
      return styling.find(list, value) ~= nil
    end
    return wholeIn(value, 0, 0xFFFFFF)
  end
end

local function option(list)
  return function(value)
    return styling.find(list, value) ~= nil
  end
end

local function oneOf(list)
  return function(value)
    return util.indexOf(list, value) ~= nil
  end
end

local function range(low, high)
  return function(value)
    return wholeIn(value, low, high)
  end
end

local function isBoolean(value)
  return type(value) == "boolean"
end

-- Checks a saved text size: "hud" to follow the HUD text, or a size in points.
local function textSize(value)
  return value == "hud" or wholeIn(value, savedappearance.TEXT_SIZE.min, savedappearance.TEXT_SIZE.max)
end

local function isOpacity(value)
  return wholeIn(value, 0, 100) and whole(value) % savedappearance.OPACITY_STEP == 0
end

local function isHudOpacity(value)
  local range_ = savedappearance.HUD_OPACITY
  return isOpacity(value) and value >= range_.min and value <= range_.max
end

-- Each appearance field's default and the check a saved value must pass.
local FIELDS = {
  texture = { "flat", oneOf(savedappearance.TEXTURES) },
  hideTargetPanel = { false, isBoolean },
  hideBuffBars = { false, isBoolean },
  hideCastBar = { true, isBoolean },
  auraBars = { false, isBoolean },
  font = { "museo", option(styling.FAMILIES) },
  textStep = { 0, range(savedappearance.TEXT_STEP_MIN, savedappearance.TEXT_STEP_MAX) },
  edge = { "shadow", option(styling.EDGES) },
  textColour = { "auto", option(styling.TEXT_COLOURS) },
  playerColour = { "runeui", colour(styling.PRESETS) },
  targetColour = { "runeui", colour(styling.PRESETS) },
  border = { "runeui", option(styling.BORDERS) },
  lifepoints = { "short", option(frames.LIFEPOINTS) },
  frameWidth = { 250, range(savedappearance.FRAME_WIDTH.min, savedappearance.FRAME_WIDTH.max) },
  frameHeight = { 55, range(savedappearance.FRAME_HEIGHT.min, savedappearance.FRAME_HEIGHT.max) },
  barWidth = { 278, range(savedappearance.BAR_WIDTH.min, savedappearance.BAR_WIDTH.max) },
  barHeight = { 20, range(savedappearance.BAR_HEIGHT.min, savedappearance.BAR_HEIGHT.max) },
  castWidth = { 278, range(savedappearance.CAST_WIDTH.min, savedappearance.CAST_WIDTH.max) },
  castHeight = { 22, range(savedappearance.CAST_HEIGHT.min, savedappearance.CAST_HEIGHT.max) },
  castMatchWidth = { false, isBoolean },
  castColour = { "ability", colour(styling.CAST_PRESETS) },
  castFont = {
    "hud",
    function(value)
      return value == "hud" or styling.find(styling.FAMILIES, value) ~= nil
    end,
  },
  spenders = { "below", option(styling.SPENDER_PLACES) },
  castTextSize = { "hud", textSize },
  debuffEdge = { "orange", option(styling.DEBUFF_EDGES) },
  hoverAllBars = { false, isBoolean },
  outOfCombat = { "show", option(autohide.MODES) },
  outOfCombatOpacity = { 30, isHudOpacity },
  showWithTarget = { true, isBoolean },
}
for bar = 1, savedappearance.ACTION_BARS do
  FIELDS["barOpacity" .. bar] = { 25, isOpacity }
  FIELDS["fadeBar" .. bar] = { false, isBoolean }
  FIELDS["hoverBar" .. bar] = { true, isBoolean }
end
for row, size in pairs(savedappearance.AURA_ICONS) do
  FIELDS[row .. "Icon"] = { size, range(savedappearance.AURA_ICON.min, savedappearance.AURA_ICON.max) }
  FIELDS[row .. "Text"] = { "hud", textSize }
end

-- A saved appearance field's value, or its default when unknown or malformed.
local function readField(field, value)
  local default = FIELDS[field][1]
  local valid = FIELDS[field][2]
  if not valid(value) then
    return default
  end
  return type(value) == "number" and whole(value) or value
end

local function readAppearance(saved)
  saved = type(saved) == "table" and saved or {}
  local appearance = {}
  for field in pairs(FIELDS) do
    appearance[field] = readField(field, saved[field])
  end
  return appearance
end

local function readMarkers(saved)
  local markers = {}
  for name, default in pairs(DEFAULT_MARKERS) do
    local value = type(saved) == "table" and saved[name] or nil
    markers[name] = type(value) == "number" and whole(value) or default
  end
  return markers
end

-- Every appearance field at its default, the look of a HUD element before main.lua gives it one.
function savedappearance.defaults()
  return readAppearance(nil)
end

-- Loads the appearance and markers from store, reading an unknown or malformed value as its default.
function savedappearance.load(store)
  local appearance = readAppearance(store.get("appearance"))
  local markers = readMarkers(store.get("markers"))
  local appearanceVersion = 0

  local s = {}

  -- { texture, hideTargetPanel, hideBuffBars, hideCastBar, auraBars, font, textStep, edge, textColour,
  -- playerColour, targetColour, border, lifepoints, frameWidth, frameHeight, barWidth, barHeight, castWidth,
  -- castHeight, castMatchWidth, castColour, castFont, castTextSize, spenders, and barOpacity, fadeBar and
  -- hoverBar for each action bar 1 to 5, such as fadeBar1, hoverAllBars, outOfCombat, outOfCombatOpacity and
  -- showWithTarget }. spenders is a src/style SPENDER_PLACES id. castFont and castTextSize are "hud" to follow
  -- the HUD text or a family id and a size in points. The game's own cast bar is hidden until chosen otherwise,
  -- since RuneUI draws one; auraBars draws a draining bar under each aura icon.
  -- An action bar with fadeBar<n> set draws at barOpacity<n> percent, and hoverBar<n> shows it at full while
  -- the mouse is over it, or over any faded bar while hoverAllBars is on. Each aura row in AURA_ICONS has
  -- <row>Icon, its icon size, and <row>Text, "hud" or its text size, such as combatBuffsIcon. debuffEdge is a
  -- src/style DEBUFF_EDGES id. outOfCombat is a src/autohide MODES id, outOfCombatOpacity the faded percent,
  -- and showWithTarget keeps the HUD at full while the player has a target. Read-only.
  function s.appearance()
    return appearance
  end

  -- Saves one appearance field, reading a value it does not accept as the field's default.
  function s.setAppearance(field, value)
    appearance[field] = readField(field, value)
    appearanceVersion = appearanceVersion + 1
    store.set("appearance", appearance)
  end

  -- A number that changes with every appearance change.
  function s.appearanceVersion()
    return appearanceVersion
  end

  -- { threshold, ultimate }: the adrenaline bar's marker percents.
  function s.markers()
    return { threshold = markers.threshold, ultimate = markers.ultimate }
  end

  function s.setMarker(name, percent)
    markers[name] = util.clamp(percent, 0, 100)
    store.set("markers", markers)
  end

  return s
end

return savedappearance
