-- A vertical scrollbar for a clipped list in the options window: a black track and a bronze thumb, moved by the
-- wheel, by a click on the track above or below the thumb, and by dragging the thumb.
local draw = require("src/draw")

local scrollbar = {}

local set = draw.set
local on = draw.on
local COLOURS = draw.WINDOW

scrollbar.WIDTH = 10
-- The wheel reports many small deltas per turn, each moving WHEEL_STEP px. A positive delta scrolls down, as in
-- the game's own lists.
local WHEEL_STEP = 8
local MIN_THUMB = 24
-- Side of the transparent square that holds a thumb drag under the cursor, which a fast move cannot leave.
local GRAB = 160

-- A scrollbar h tall at x, y on parent, for a view h tall. onScroll(y) asks the owner to scroll to y, which the
-- owner does by calling set. Returns { set, wheel, grip, follow, cancel }: set(scroll, contentH) shows scroll
-- within content contentH tall and returns scroll clamped to it; wheel(c) scrolls by the wheel over c;
-- grip(layer, gx, gy) builds the thumb's grab area on layer, where the track sits at gx, gy, after everything it
-- must sit above; follow runs every frame to move a held thumb; cancel ends a drag, as when the window closes.
function scrollbar.create(parent, x, y, h, onScroll)
  local track = draw.hitArea(draw.rect(parent, COLOURS.sidebar, x, y, scrollbar.WIDTH, h))
  local thumb = draw.rect(parent, COLOURS.bronze, x + 1, y, scrollbar.WIDTH - 2, 0)
  local scroll = 0
  local contentH = 0
  -- The grab area and where the track sits on its layer, and the drag it holds: { origin, y, scroll }, with the
  -- cursor's offset from layer coordinates, or nil.
  local grip, gx, gy, held

  local function maxScroll()
    return math.max(0, contentH - h)
  end

  local function thumbBox()
    local th = math.max(MIN_THUMB, h * math.min(1, h / contentH))
    local max = maxScroll()
    return max == 0 and 0 or math.floor((h - th) * scroll / max + 0.5), math.floor(th)
  end

  -- Puts the grab area over the thumb.
  local function placeGrip()
    local ty, th = thumbBox()
    draw.pos(grip, gx, gy + ty)
    draw.size(grip, scrollbar.WIDTH, th)
    set(grip, "hidden", maxScroll() == 0)
  end

  local function wheel(c)
    on(c, "ONSCROLLWHEEL", function(_, delta)
      onScroll(scroll + delta * WHEEL_STEP)
    end)
  end
  wheel(track)
  on(track, "ONCLICK", function(_, _, cy)
    local ty, th = thumbBox()
    if cy < ty then
      onScroll(scroll - h)
    elseif cy > ty + th then
      onScroll(scroll + h)
    end
  end)

  local function setScroll(to, height)
    contentH = height
    scroll = math.max(0, math.min(maxScroll(), to))
    local ty, th = thumbBox()
    draw.pos(thumb, x + 1, y + ty)
    draw.size(thumb, scrollbar.WIDTH - 2, th)
    set(thumb, "hidden", maxScroll() == 0)
    if grip ~= nil and held == nil then
      placeGrip()
    end
    return scroll
  end

  local function buildGrip(layer, trackX, trackY)
    gx = trackX
    gy = trackY
    grip = draw.hitArea(draw.rect(layer, COLOURS.panel, 0, 0, 0, 0))
    set(grip, "alpha", 0)
    wheel(grip)
    on(grip, "ONCLICK", function(_, cx, cy)
      draw.pressAt(grip, cx)
      local mx, my = draw.cursor()
      if mx == nil then
        return
      end
      local ty = thumbBox()
      held = { origin = { x = mx - (gx + cx), y = my - (gy + ty + cy) }, y = my, scroll = scroll }
    end)
    on(grip, "ONRELEASE", function()
      held = nil
      placeGrip()
    end)
    placeGrip()
  end

  -- Moves a held thumb with the cursor. Returns before reading the mouse unless it is held.
  local function follow()
    if held == nil then
      return
    end
    local mx, my = draw.cursor()
    if mx == nil or (mx == held.lastX and my == held.lastY) then
      return
    end
    held.lastX = mx
    held.lastY = my
    local _, th = thumbBox()
    if h > th then
      onScroll(held.scroll + (my - held.y) * maxScroll() / (h - th))
    end
    draw.size(grip, GRAB, GRAB)
    draw.pos(grip, math.floor(mx - held.origin.x) - GRAB // 2, math.floor(my - held.origin.y) - GRAB // 2)
  end

  return {
    set = setScroll,
    wheel = wheel,
    grip = buildGrip,
    follow = follow,
    cancel = function()
      held = nil
      placeGrip()
    end,
  }
end

return scrollbar
