-- Pieces the HUD elements share: the look an element shows until it is given one, text styling for a look,
-- spender rows, and the faint bar marks the resource bar and cast bar draw.
local hudparts = {}

local draw = require("src/draw")
local frames = require("src/frames")
local savedappearance = require("src/savedappearance")
local style = require("src/style")
local set = draw.set
local pos = draw.pos
local rect = draw.rect
local COLOURS = draw.COLOURS
-- Screen position of a point inside a layer parented to the plugin layer.
local function screenPos(layer, x, y)
  return layer.x + x, layer.y + y
end

-- The look an element shows until it is given one.
local DEFAULT_LOOK = style.look(savedappearance.defaults(), nil)

-- Writes the font name font, a text colour and look's edge to a draw.edgedText label. dark draws Auto's dark
-- text with a light edge and no shadow; rgb overrides the look's text colour. Every write skips an unchanged
-- value.
local function styleFont(label, font, look, dark, rgb)
  local native = look.outline and not dark and style.outlineFont(font)
  set(label, "font", id.Font[native or font])
  local colour = rgb or look.text
  if dark then
    colour = style.DARK_TEXT
  end
  set(label, "rgb", colour)
  set(label, "isShadowed", look.shadow and not dark)
  local edge = nil
  if look.outline and not native then
    edge = dark and style.LIGHT_EDGE or style.DARK_EDGE
  end
  draw.setEdge(label, edge)
end

-- styleFont with look's font for role.
local function styleText(label, role, look, dark, rgb)
  styleFont(label, look.fonts[role], look, dark, rgb)
end

-- Spender rows: each SPENDER_ROW tall, SPENDER_STEP apart, so a host grows SPENDER_STEP per shown row.
local SPENDER_ROW = 8
local SPENDER_STEP = SPENDER_ROW + 2
local SPENDER_COLOURS = { souls = COLOURS.spender, necrosis = COLOURS.necrosis }
-- Stacks that make a whole cast, on spender rows and tile bars.
local GOLD = draw.WINDOW.accent

-- Left edges and widths of count blocks spread evenly across width with 2px gaps, using every pixel.
local function blockSpans(count, width)
  local spans = {}
  for i = 1, count do
    local left = math.floor((i - 1) * (width + 2) / count)
    local right = math.floor(i * (width + 2) / count) - 2
    spans[i] = { x = left, w = right - left }
  end
  return spans
end

-- One row of spender blocks per src/frames spender on layer, hidden. show(spenders, w, y) draws spenders, a
-- src/frames resource model's list, in rows w wide from y down, each canvas redrawn only when its spender,
-- count, gold, max or width changes, and hides the rest.
local function spenderRows(layer)
  local rows = {}
  for r = 1, #frames.SPENDERS do
    rows[r] = { canvas = ui.Canvas.new(layer) }
    set(rows[r].canvas, "hidden", true)
  end

  -- Black-edged blocks, gold up to the spender's whole casts and filled up to its count.
  local function drawBlocks(canvas, spender, w)
    canvas:Clear()
    local edge = draw.opaque(COLOURS.border)
    for i, span in ipairs(blockSpans(spender.max, w)) do
      local rgb = COLOURS.emptyBlock
      if i <= spender.gold then
        rgb = GOLD
      elseif i <= spender.count then
        rgb = SPENDER_COLOURS[spender.key]
      end
      canvas:AddRectangle(span.x, 0, span.w, SPENDER_ROW, edge)
      canvas:AddRectangle(span.x + 1, 1, span.w - 2, SPENDER_ROW - 2, draw.opaque(rgb))
    end
  end

  local function show(spenders, w, y)
    for r, row in ipairs(rows) do
      local spender = spenders[r]
      set(row.canvas, "hidden", spender == nil)
      if spender ~= nil then
        pos(row.canvas, 0, y + (r - 1) * SPENDER_STEP)
        draw.size(row.canvas, w, SPENDER_ROW)
        if
          row.key ~= spender.key
          or row.count ~= spender.count
          or row.gold ~= spender.gold
          or row.max ~= spender.max
          or row.w ~= w
        then
          row.key = spender.key
          row.count = spender.count
          row.gold = spender.gold
          row.max = spender.max
          row.w = w
          drawBlocks(row.canvas, spender, w)
        end
      end
    end
  end

  return { show = show }
end

local NO_SPENDERS = {}

-- Bar marks are faint 1px lines across a bar: dark where the fill has passed them, light ahead of it.
local MARK_DARK_ALPHA = 0.4
local MARK_LIGHT_ALPHA = 0.3

-- A bar mark at x, y as tall as height.
local function barMark(layer, x, y, height)
  local mark = rect(layer, COLOURS.highlight, x, y, 1, height)
  set(mark, "alpha", MARK_LIGHT_ALPHA)
  return mark
end

-- Shades a bar mark for whether the fill has passed it.
local function shadeMark(mark, passed)
  set(mark, "rgb", passed and COLOURS.border or COLOURS.highlight)
  set(mark, "alpha", passed and MARK_DARK_ALPHA or MARK_LIGHT_ALPHA)
end

hudparts.screenPos = screenPos
hudparts.DEFAULT_LOOK = DEFAULT_LOOK
hudparts.styleFont = styleFont
hudparts.styleText = styleText
hudparts.spenderRows = spenderRows
hudparts.SPENDER_STEP = SPENDER_STEP
hudparts.SPENDER_COLOURS = SPENDER_COLOURS
hudparts.GOLD = GOLD
hudparts.NO_SPENDERS = NO_SPENDERS
hudparts.barMark = barMark
hudparts.shadeMark = shadeMark

return hudparts
