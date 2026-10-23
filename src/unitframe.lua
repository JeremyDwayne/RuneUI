-- The player and target frames: a health bar with the name and value on it, a prayer bar under the player's,
-- and spender rows under the player frame when the look puts them there.
local unitframe = {}

local draw = require("src/draw")
local frames = require("src/frames")
local hudparts = require("src/hudparts")
local style = require("src/style")
local set = draw.set
local pos = draw.pos
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS
local styleText = hudparts.styleText
local spenderRows = hudparts.spenderRows
local SPENDER_STEP = hudparts.SPENDER_STEP
local NO_SPENDERS = hudparts.NO_SPENDERS
local DEFAULT_LOOK = hudparts.DEFAULT_LOOK
local POWER_HEIGHT = 6
-- Game frame: the 2px window border the game draws round its action bars, from RS3_HUD_WINDOW_COMPACT_CORNER_TOP,
-- _TOP_TILE, _SIDE_TILE, _CORNER_BOTTOM and _BOTTOM_TILE. The right side is the left one flipped.
local GAME_EDGE = 2
local GAME_SPRITES = { cornerTop = 32990, side = 32991, cornerBottom = 32992, top = 32993, bottom = 32994 }

-- The eight sprites of a Game frame on layer, hidden. place(w, h) fits them to a w by h box.
local function gameFrame(layer)
  local parts = {}
  local function part(sprite, flipped, tiling)
    local c = ui.Sprite.new(layer)
    set(c, "sprite", sprite)
    set(c, "isTiling", tiling)
    set(c, "isFlippedHorizontally", flipped)
    set(c, "hidden", true)
    parts[#parts + 1] = c
    return c
  end
  local S = GAME_SPRITES
  local topLeft = part(S.cornerTop, false, false)
  local topRight = part(S.cornerTop, true, false)
  local bottomLeft = part(S.cornerBottom, false, false)
  local bottomRight = part(S.cornerBottom, true, false)
  local top = part(S.top, false, true)
  local bottom = part(S.bottom, false, true)
  local left = part(S.side, false, true)
  local right = part(S.side, true, true)
  local e = GAME_EDGE
  local frame = { parts = parts }

  function frame.place(w, h)
    for c, box in pairs({
      [topLeft] = { 0, 0, e, e },
      [topRight] = { w - e, 0, e, e },
      [bottomLeft] = { 0, h - e, e, e },
      [bottomRight] = { w - e, h - e, e, e },
      [top] = { e, 0, w - 2 * e, e },
      [bottom] = { e, h - e, w - 2 * e, e },
      [left] = { 0, e, e, h - 2 * e },
      [right] = { w - e, e, e, h - 2 * e },
    }) do
      pos(c, box[1], box[2])
      draw.size(c, box[3], box[4])
    end
  end

  return frame
end
-- The value label's width at the right of a unit frame, and the space the name leaves for it.
local VALUE_WIDTH = 95
local VALUE_SPACE = 110

-- A unit frame of look.frameWidth by look.frameHeight: a black border, the game's window border over it or none as
-- look.border picks, a health bar in the look's colour for
-- kind, "player" or "target", with the name on the left and the value on the right, and with power a 6px prayer
-- bar along the bottom. Both frames share one box height, whether or not a power bar shows in it. Auto text goes
-- dark over a bright fill once the fill reaches the label's right end. The player frame, built with power, also
-- hosts spender rows under it when look.spenders is "player": showSpenders(spenders) draws a src/frames resource
-- model's list there and returns whether the bounds, which span the frame and those rows, changed.
local function unitFrame(root, kind, power)
  local layer = ui.Layer.new(root)
  local rows = power and spenderRows(layer)
  local border = rect(layer, COLOURS.border, 0, 0, 0, 0)
  local track = rect(layer, COLOURS.healthTrack, 1, 1, 0, 0)
  local health = draw.bar(layer, style.FRAME_COLOURS[kind], COLOURS.healthTrack, 1, 1, 0, 0)
  local prayerTrack = power and rect(layer, COLOURS.healthTrack, 1, 0, 0, POWER_HEIGHT)
  local prayer = power and draw.bar(layer, COLOURS.prayer, COLOURS.healthTrack, 1, 0, 0, POWER_HEIGHT)
  local game = gameFrame(layer)
  local name = draw.edgedText(layer, FONTS.body, ui.AlignMode.TOPLEFT, 6, 1, 0, 0)
  local value = draw.edgedText(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, 0, 1, VALUE_WIDTH, 0)
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local frame = { layer = layer, bounds = bounds }
  -- The look shown, whether its fill wants Auto's dark text, the fill shown, and the fills at which each label
  -- sits wholly on it.
  local shown = nil
  local bright = false
  local fill = nil
  local nameAt = 1
  local valueAt = 1
  -- The spenders last given to showSpenders.
  local spenders = NO_SPENDERS

  local function resize(w, h)
    local inner = w - 2
    local healthHeight = power and h - POWER_HEIGHT - 3 or h - 2
    frame.width = w
    frame.height = h
    bounds.w = w
    bounds.h = h
    draw.size(layer, w, h + (rows and 2 + #frames.SPENDERS * SPENDER_STEP or 0))
    draw.size(border, w, h)
    draw.size(track, inner, healthHeight)
    health.setBox(1, 1, inner, healthHeight)
    draw.size(name, w - VALUE_SPACE, healthHeight)
    pos(value, w - VALUE_WIDTH - 6, 1)
    draw.size(value, VALUE_WIDTH, healthHeight)
    nameAt = (6 + w - VALUE_SPACE) / inner
    valueAt = (inner - 5) / inner
    game.place(w, h)
    if power then
      pos(prayerTrack, 1, healthHeight + 2)
      draw.width(prayerTrack, inner)
      prayer.setBox(1, healthHeight + 2, inner, POWER_HEIGHT)
    end
  end

  local function styleLabels()
    styleText(name, "body", shown, bright and fill ~= nil and fill >= nameAt)
    styleText(value, "body", shown, bright and fill ~= nil and fill >= valueAt)
  end

  function frame.update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then
      return
    end
    fill = model.fill
    health.setFill(fill)
    set(name, "content", model.name)
    set(value, "content", model.valueText)
    styleLabels()
    if power then
      set(prayerTrack, "hidden", model.prayerText == nil)
      prayer.setFill(model.prayerFill)
    end
  end

  function frame.showSpenders(list)
    if not rows then
      return false
    end
    spenders = list or NO_SPENDERS
    local shownList = shown.spenders == "player" and spenders or NO_SPENDERS
    rows.show(shownList, frame.width, frame.height + 2)
    local h = frame.height + #shownList * SPENDER_STEP
    if h == bounds.h then
      return false
    end
    bounds.h = h
    return true
  end

  -- Restyles the frame for a src/style look, returning at once for the look it shows. Returns whether its
  -- bounds changed.
  function frame.setLook(look)
    if look == shown then
      return false
    end
    shown = look
    local moved = frame.width ~= look.frameWidth or frame.height ~= look.frameHeight
    if moved then
      resize(look.frameWidth, look.frameHeight)
    end
    if frame.showSpenders(spenders) then
      moved = true
    end
    local rgb = look[kind]
    bright = look.auto and style.dark(rgb)
    health.setColour(rgb)
    health.setTexture(look.texture)
    if power then
      prayer.setTexture(look.texture)
    end
    set(border, "hidden", look.border == "none")
    draw.hideAll(game.parts, look.border ~= "game")
    styleLabels()
    return moved
  end

  frame.setLook(DEFAULT_LOOK)
  return frame
end

-- The player's frame: health with name and "13.1K | 78%", prayer below.
function unitframe.player(root)
  return unitFrame(root, "player", true)
end

-- The target's frame: health with name and "6,800 | 58%", the same box height as the player frame.
function unitframe.target(root)
  return unitFrame(root, "target", false)
end

return unitframe
