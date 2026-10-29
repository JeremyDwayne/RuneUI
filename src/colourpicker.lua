-- A colour picker for the options window: a shade square, white to the hue across and clear to black down,
-- beside a hue strip, each with a mark at the shown colour. Built on first show, since few players open one.
local draw = require("src/draw")
local style = require("src/style")

local colourpicker = {}

local SQUARE_W = 180
local HUE_W = 18
local HUE_GAP = 8
-- The hue strip's colours from top to bottom, at hues 360 down to 0.
local HUE_STOPS = { 0xFF0000FF, 0xFF00FFFF, 0x0000FFFF, 0x00FFFFFF, 0x00FF00FF, 0xFFFF00FF, 0xFF0000FF }

-- The picker's size on its parent.
colourpicker.W = SQUARE_W + HUE_GAP + HUE_W
colourpicker.H = 110

-- A picker at x, y on parent. deps: { choose(rgb) taking each picked colour; allowed(y), when given, taking a
-- click's y on parent and saying whether it lands where the picker shows, for a picker in a clipped list;
-- wheel(component) wiring the wheel on each canvas }. Returns { show(rgb), hide() }: show
-- builds the picker if need be and marks rgb.
function colourpicker.create(parent, x, y, deps)
  local parts = nil
  -- The hue the square is painted in, kept across greys, which have none of their own.
  local hue = 0
  local painted = nil
  local shown = 0

  local function paintSquare(h)
    parts.square:Clear()
    parts.square:AddRectangle(0, 0, SQUARE_W, colourpicker.H, draw.opaque(style.rgb(h, 1, 1)))
    parts.square:AddGradientH(0, 0, SQUARE_W, colourpicker.H, 0xFFFFFFFF, 0xFFFFFF00)
    parts.square:AddGradientV(0, 0, SQUARE_W, colourpicker.H, 0x00000000, 0x000000FF)
  end

  local picker = {}

  local function allowed(cy)
    return deps.allowed == nil or deps.allowed(y + cy)
  end

  -- Saves the colour at px, py on the square, or at py on the hue strip when onHue. A hue picked for a grey
  -- leaves the colour as it is, so the picker repaints in that hue itself.
  local function pick(px, py, onHue)
    local _, sat, v = style.hsv(shown)
    local fy = math.max(0, math.min(1, py / colourpicker.H))
    if onHue then
      hue = (1 - fy) * 360 % 360
    else
      sat = math.max(0, math.min(1, px / SQUARE_W))
      v = 1 - fy
    end
    deps.choose(style.rgb(hue, sat, v))
    if onHue then
      picker.show(shown)
    end
  end

  local function build()
    parts = {}
    parts.square = draw.hitArea(ui.Canvas.new(parent))
    draw.pos(parts.square, x, y)
    draw.size(parts.square, SQUARE_W, colourpicker.H)
    parts.hue = draw.hitArea(ui.Canvas.new(parent))
    draw.pos(parts.hue, x + SQUARE_W + HUE_GAP, y)
    draw.size(parts.hue, HUE_W, colourpicker.H)
    local segment = colourpicker.H / (#HUE_STOPS - 1)
    for i = 1, #HUE_STOPS - 1 do
      local top = math.floor((i - 1) * segment)
      parts.hue:AddGradientV(0, top, HUE_W, math.floor(i * segment) - top, HUE_STOPS[i], HUE_STOPS[i + 1])
    end
    parts.mark = draw.rect(parent, draw.WINDOW.ring, 0, 0, 6, 6)
    parts.hueMark = draw.rect(parent, draw.WINDOW.ring, 0, 0, HUE_W + 4, 4)
    for _, canvas in ipairs({ parts.square, parts.hue }) do
      deps.wheel(canvas)
      draw.on(canvas, "ONCLICK", function(_, px, py)
        if allowed(py) then
          pick(px, py, canvas == parts.hue)
        end
      end)
    end
  end

  local function hideAll(hidden)
    draw.hideAll({ parts.square, parts.hue, parts.mark, parts.hueMark }, hidden)
  end

  function picker.show(rgb)
    if parts == nil then
      build()
    end
    shown = rgb
    local h, sat, v = style.hsv(rgb)
    if sat > 0 and v > 0 then
      hue = h
    end
    if hue ~= painted then
      painted = hue
      paintSquare(hue)
    end
    local markY = y + math.floor((1 - v) * colourpicker.H) - 3
    draw.pos(parts.mark, x + math.floor(sat * SQUARE_W) - 3, markY)
    draw.pos(parts.hueMark, x + SQUARE_W + HUE_GAP - 2, y + math.floor((1 - hue / 360) * colourpicker.H) - 2)
    hideAll(false)
  end

  function picker.hide()
    if parts ~= nil then
      hideAll(true)
    end
  end

  return picker
end

return colourpicker
