-- The adrenaline bar: its fill and percent, a faint mark at each of the two markers, spender rows above or
-- below it as the look picks, and a global cooldown strip on the side that faces the cooldown groups.
local resourcebar = {}

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
local GOLD = hudparts.GOLD
local DEFAULT_LOOK = hudparts.DEFAULT_LOOK
local barMark = hudparts.barMark
local shadeMark = hudparts.shadeMark
-- The global cooldown strip: a dark track with a gold fill that runs from empty to full over the global
-- cooldown, STRIP_GAP from the bar and from whatever sits beyond it, in room the bounds always keep so nothing
-- moves when it shows.
local STRIP = 5
local STRIP_GAP = 2
local STRIP_ROOM = STRIP_GAP + STRIP + STRIP_GAP
-- Room the adrenaline bar's layer keeps above its bar for spender rows and the strip.
local BAR_Y = #frames.SPENDERS * SPENDER_STEP + STRIP_ROOM
-- Fill fraction at which the centred percent label sits entirely on the fill.
local PERCENT_ON_FILL = 0.56

-- A look.barWidth by look.barHeight adrenaline bar with its percent and a bar mark at each of its two markers,
-- and spender rows above or below it as look.spenders picks. Its bounds span the bar, the rows it shows and the
-- strip's room. update(model) takes a src/frames resource model and returns whether the bounds changed.
-- faceStrip(side) puts the strip on the bar's "top" or "bottom", and returns whether the bounds changed.
-- setGlobal(since, remaining, length) shows the strip for a global cooldown with remaining of its length
-- seconds left at the server tick since seconds ago, or hides it when remaining is nil, and step(since) fills
-- it, returning at once while it is hidden. middle is the bar's vertical centre in its
-- layer, which the strip and rows leave where it is.

function resourcebar.create(root)
  local layer = ui.Layer.new(root)
  local rows = spenderRows(layer)
  local border = rect(layer, COLOURS.border, 0, BAR_Y, 0, 0)
  local track = rect(layer, COLOURS.track, 1, BAR_Y + 1, 0, 0)
  local fill = draw.bar(layer, COLOURS.adrenaline, COLOURS.track, 1, BAR_Y + 1, 0, 0)
  local markers = { barMark(layer, 0, BAR_Y + 1, 0), barMark(layer, 0, BAR_Y + 1, 0) }
  local percent = draw.edgedText(layer, FONTS.body, ui.AlignMode.CENTRE, 0, BAR_Y + 1, 0, 0)
  local stripTrack = rect(layer, COLOURS.border, 0, 0, 0, STRIP)
  local stripFill = rect(layer, GOLD, 0, 0, 0, STRIP - 2)
  local strip = { stripTrack, stripFill }
  draw.hideAll(strip, true)
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local bar = { layer = layer, bounds = bounds }
  -- The look shown, whether it wants dark text once the fill passes the label, the fill shown, the model shown,
  -- redrawn after a resize, the bar's height, the side the strip is on, and the global cooldown it shows as
  -- seconds left at the last server tick and its length, or nil.
  local shown = nil
  local bright = false
  local fillShown = 0
  local last = nil
  local barH = 0
  local stripSide = "top"
  local globalLeft = nil
  local globalLength = 0

  local function stylePercent()
    styleText(percent, "body", shown, bright and fillShown >= PERCENT_ON_FILL)
  end

  -- Lays out the spender rows the look puts on the bar and fits the bounds to them; returns whether they moved.
  local function placeSpenders(spenders)
    if shown.spenders == "player" then
      spenders = NO_SPENDERS
    end
    local w = bounds.w
    local rowsH = #spenders * SPENDER_STEP
    local above = shown.spenders == "above"
    local top = stripSide == "top" and STRIP_ROOM or 0
    local bottom = STRIP_ROOM - top
    rows.show(spenders, w, above and BAR_Y - top - rowsH or BAR_Y + barH + bottom + 2)
    local y = BAR_Y - top - (above and rowsH or 0)
    local h = barH + rowsH + STRIP_ROOM
    if y == bounds.y and h == bounds.h then
      return false
    end
    bounds.y = y
    bounds.h = h
    bar.height = h
    return true
  end

  -- Width of the strip's gold fill, since seconds after the server tick: empty as the global cooldown starts and
  -- full as it ends.
  local function stripWidth(since)
    local done = (globalLength - globalLeft + since) / globalLength
    return math.floor((bounds.w - 2) * math.max(0, math.min(1, done)) + 0.5)
  end

  local function placeStrip()
    local y = stripSide == "top" and BAR_Y - STRIP_GAP - STRIP or BAR_Y + barH + STRIP_GAP
    pos(stripTrack, 0, y)
    draw.width(stripTrack, bounds.w)
    pos(stripFill, 1, y + 1)
  end

  local function update(model)
    last = model
    set(layer, "hidden", model.hidden)
    if model.hidden then
      return placeSpenders(NO_SPENDERS)
    end
    local w = bounds.w
    fill.setFill(model.fill)
    set(percent, "content", model.text)
    fillShown = model.fill
    stylePercent()
    for i, marker in ipairs(model.markers) do
      pos(markers[i], math.min(math.floor(marker.at * (w - 2)), w - 3) + 1, BAR_Y + 1)
      shadeMark(markers[i], model.fill >= marker.at)
    end
    return placeSpenders(model.spenders)
  end

  local function resize(w, h)
    barH = h
    bounds.w = w
    bar.middle = BAR_Y + h / 2
    bar.width = w
    draw.size(layer, w, 2 * BAR_Y + h + 2)
    draw.size(border, w, h)
    draw.size(track, w - 2, h - 2)
    fill.setBox(1, BAR_Y + 1, w - 2, h - 2)
    for _, mark in ipairs(markers) do
      draw.size(mark, 1, h - 2)
    end
    draw.size(percent, w, h - 2)
    placeStrip()
  end

  -- Restyles the bar for a src/style look, returning at once for the look it shows. Returns whether its bounds
  -- changed.
  function bar.setLook(look)
    if look == shown then
      return false
    end
    local resized = bounds.w ~= look.barWidth or barH ~= look.barHeight
    shown = look
    bright = look.auto and style.dark(COLOURS.adrenaline)
    if resized then
      resize(look.barWidth, look.barHeight)
    end
    fill.setTexture(look.texture)
    stylePercent()
    local moved = placeSpenders(last and not last.hidden and last.spenders or NO_SPENDERS)
    if last ~= nil and resized then
      update(last)
    end
    return resized or moved
  end

  function bar.faceStrip(side)
    if side == nil or side == stripSide then
      return false
    end
    stripSide = side
    placeStrip()
    return placeSpenders(last and not last.hidden and last.spenders or NO_SPENDERS)
  end

  function bar.setGlobal(since, remaining, length)
    globalLeft = remaining
    globalLength = length or 0
    draw.hideAll(strip, remaining == nil)
    bar.step(since)
  end

  function bar.step(since)
    if globalLeft ~= nil then
      draw.width(stripFill, stripWidth(since))
    end
  end

  bar.update = update
  bar.setLook(DEFAULT_LOOK)
  return bar
end

return resourcebar
