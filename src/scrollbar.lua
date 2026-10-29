-- A vertical scrollbar for a clipped list in the options window, drawn with the game's scrollbar sprites: an
-- arrow at each end, a track and a thumb. The wheel, the arrows, a click on the track above or below the thumb
-- and a drag of the thumb move it.
local draw = require("src/draw")

local scrollbar = {}

local set = draw.set
local on = draw.on
local COLOURS = draw.WINDOW

scrollbar.WIDTH = 16
-- The game's scrollbar sprites, an arrow's height, a thumb end's height and how far an arrow click scrolls.
local SPRITES = {
  up = "SCROLLBAR_V2_0",
  down = "SCROLLBAR_V2_1",
  track = "SCROLLBAR_DRAGGER_V2_3",
  thumbTop = "SCROLLBAR_DRAGGER_V2_0",
  thumbMiddle = "SCROLLBAR_DRAGGER_V2_1",
  thumbBottom = "SCROLLBAR_DRAGGER_V2_2",
}
local ARROW = 16
local END = 5
local ARROW_STEP = 32
-- The wheel reports many small deltas per turn, each moving WHEEL_STEP px. A positive delta scrolls down, as in
-- the game's own lists.
local WHEEL_STEP = 8
local MIN_THUMB = 24
-- Side of the transparent square that holds a thumb drag under the cursor, which a fast move cannot leave.
local GRAB = 160

-- A sprite of the game's named name, w by h at x, y on parent, tiled when tiling is true.
local function sprite(parent, name, x, y, w, h, tiling)
  local c = draw.new(ui.Sprite, parent)
  draw.pos(c, x, y)
  draw.size(c, w, h)
  set(c, "sprite", id.Sprite[name])
  if tiling then
    set(c, "isTiling", true)
  end
  return c
end

-- A scrollbar h tall at x, y on parent, for a view h tall. onScroll(y) asks the owner to scroll to y, which the
-- owner does by calling set. Returns { set, wheel, grip, follow, cancel }: set(scroll, contentH) shows scroll
-- within content contentH tall and returns scroll clamped to it; wheel(c) scrolls by the wheel over c;
-- grip(layer, gx, gy) builds the thumb's grab area on layer, where the scrollbar sits at gx, gy, after
-- everything it must sit above; follow runs every frame to move a held thumb; cancel ends a drag, as when the
-- window closes.
function scrollbar.create(parent, x, y, h, onScroll)
  local trackY = y + ARROW
  local trackH = h - 2 * ARROW
  local up = draw.hitArea(sprite(parent, SPRITES.up, x, y, scrollbar.WIDTH, ARROW))
  local down = draw.hitArea(sprite(parent, SPRITES.down, x, y + h - ARROW, scrollbar.WIDTH, ARROW))
  local track = draw.hitArea(sprite(parent, SPRITES.track, x, trackY, scrollbar.WIDTH, trackH, true))
  local thumb = {
    sprite(parent, SPRITES.thumbTop, x, trackY, scrollbar.WIDTH, END),
    sprite(parent, SPRITES.thumbMiddle, x, trackY, scrollbar.WIDTH, 0, true),
    sprite(parent, SPRITES.thumbBottom, x, trackY, scrollbar.WIDTH, END),
  }
  local scroll = 0
  local contentH = 0
  -- The grab area and where the scrollbar sits on its layer, and the drag it holds: { origin, y, scroll }, with the
  -- cursor's offset from layer coordinates, or nil.
  local grip, gx, gy, held

  local function maxScroll()
    return math.max(0, contentH - h)
  end

  -- The thumb's top from the track's and its height.
  local function thumbBox()
    local th = math.max(MIN_THUMB, trackH * math.min(1, h / contentH))
    local max = maxScroll()
    return max == 0 and 0 or math.floor((trackH - th) * scroll / max + 0.5), math.floor(th)
  end

  -- Puts the grab area over the thumb.
  local function placeGrip()
    local ty, th = thumbBox()
    draw.pos(grip, gx, gy + ARROW + ty)
    draw.size(grip, scrollbar.WIDTH, th)
    set(grip, "hidden", maxScroll() == 0)
  end

  local function wheel(c)
    on(c, "ONSCROLLWHEEL", function(_, delta)
      onScroll(scroll + delta * WHEEL_STEP)
    end)
  end
  wheel(track)
  wheel(up)
  wheel(down)
  on(up, "ONCLICK", function()
    onScroll(scroll - ARROW_STEP)
  end)
  on(down, "ONCLICK", function()
    onScroll(scroll + ARROW_STEP)
  end)
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
    local top = trackY + ty
    draw.pos(thumb[1], x, top)
    draw.pos(thumb[2], x, top + END)
    draw.size(thumb[2], scrollbar.WIDTH, th - 2 * END)
    draw.pos(thumb[3], x, top + th - END)
    draw.hideAll(thumb, maxScroll() == 0)
    if grip ~= nil and held == nil then
      placeGrip()
    end
    return scroll
  end

  local function buildGrip(layer, barX, barY)
    gx = barX
    gy = barY
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
    if trackH > th then
      onScroll(held.scroll + (my - held.y) * maxScroll() / (trackH - th))
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
