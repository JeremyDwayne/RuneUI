-- Drawing primitives shared by src/view and src/options: fonts, colours, and component builders that
-- skip unchanged writes and log a refused property write once instead of erroring.
local draw = {}

-- Closest client fonts to 13px values, 10px labels and seconds sized to each tile.
draw.FONTS = {
  body = id.Font.MUSEO_SANS_13PT_BOLD,
  small = id.Font.NOTOSANS_BOLD_10,
  seconds = id.Font.MUSEO_SANS_17PT_BOLD,
  smallSeconds = id.Font.MUSEO_SANS_15PT_BOLD,
}

draw.COLOURS = {
  border = 0x000000,
  track = 0x1a1d21,
  healthTrack = 0x111111,
  player = 0x2f63a8,
  target = 0xa4511c,
  prayer = 0xdfe4ea,
  adrenaline = 0xffb000,
  marker = 0xdfe4ea,
  text = 0xffffff,
  darkText = 0x111316,
  spender = 0xdfe4ea,
  necrosis = 0x9b59d0,
  emptyBlock = 0x22262b,
  tile = 0x141414,
  dimText = 0xc7ccd1,
  -- Options window palette: warm near-black panels and a teal accent.
  panel = 0x110f0c,
  sidebar = 0x0b0a08,
  popup = 0x1a1816,
  line = 0x1d1b18,
  button = 0x221e1b,
  buttonHover = 0x302b27,
  accent = 0x0cd29d,
  accentHover = 0x3ddcb1,
  accentText = 0x0b0a08,
  mutedText = 0x9c9b99,
  editorTile = 0x2a2620,
}

local warned = {}
-- Last value written per component and field, so per-tick redraws only touch what changed.
local written = setmetatable({}, { __mode = "k" })

local function writtenFor(obj)
  local fields = written[obj]
  if fields == nil then
    fields = {}
    written[obj] = fields
  end
  return fields
end

-- Writes a component property unless it already holds value, logging the first failure per property.
function draw.set(obj, field, value)
  local fields = writtenFor(obj)
  if fields[field] == value then return end
  local ok, err = pcall(function() obj[field] = value end)
  if ok then
    fields[field] = value
  elseif not warned[field] then
    warned[field] = true
    log("cannot set " .. field .. ":", err)
  end
end

-- SetPos for components moved on every redraw; skips the call when the position is unchanged.
function draw.pos(obj, x, y)
  local fields = writtenFor(obj)
  if fields["SetPos.x"] == x and fields["SetPos.y"] == y then return end
  obj:SetPos(x, y)
  fields["SetPos.x"], fields["SetPos.y"] = x, y
end

-- SetWidth with the same unchanged-value skip as draw.pos.
function draw.width(obj, width)
  local fields = writtenFor(obj)
  if fields.SetWidth == width then return end
  obj:SetWidth(width)
  fields.SetWidth = width
end

function draw.rect(parent, rgb, x, y, width, height)
  local r = ui.Rectangle.new(parent)
  draw.set(r, "fill", true)
  draw.set(r, "rgb", rgb)
  r:SetPos(x, y)
  r:SetSize(width, height)
  return r
end

local alignWarned = false

-- The two-axis AlignTo raised a newindex error in the client; fall back to the one-axis form.
local function align(t, horizontal)
  local ok, err = pcall(function() t:AlignTo(horizontal, ui.AlignMode.CENTRE) end)
  if ok then return end
  if not alignWarned then
    alignWarned = true
    log("two-axis AlignTo failed, using one axis:", err)
  end
  pcall(function() t:AlignTo(horizontal) end)
end

function draw.text(parent, font, horizontal, x, y, width, height)
  local t = ui.Text.new(parent)
  draw.set(t, "font", font)
  draw.set(t, "rgb", draw.COLOURS.text)
  draw.set(t, "isShadowed", true)
  align(t, horizontal)
  t:SetPos(x, y)
  t:SetSize(width, height)
  return t
end

-- Gradient ends as fractions toward white and black.
local LIGHTEN, DARKEN = 0.15, 0.35

-- Moves each channel of a 0xRRGGBB colour toward target by amount, from 0 to 1.
local function mix(rgb, target, amount)
  local out = 0
  for shift = 16, 0, -8 do
    local from, to = (rgb >> shift) & 0xFF, (target >> shift) & 0xFF
    out = out | (math.floor(from + (to - from) * amount + 0.5) << shift)
  end
  return out
end

-- Canvas colours are 0xRRGGBBAA.
function draw.opaque(rgb)
  return (rgb << 8) | 0xFF
end

local canvasWarned = false

local function warnCanvas(err)
  if canvasWarned then return end
  canvasWarned = true
  log("canvas failed, bars stay flat:", err)
end

-- A bar fill over its track, flat or with a settings.TEXTURES gradient. The gradient is drawn once per
-- texture on a canvas, and a track-coloured cover hides the empty part, so a fill change moves one rect.
-- Returns { setFill(fill from 0 to 1, or nil to hide), setTexture(texture) }.
function draw.bar(parent, rgb, trackRgb, x, y, width, height)
  local solid = draw.rect(parent, rgb, x, y, width, height)
  local ok, canvas = pcall(function()
    local c = ui.Canvas.new(parent)
    c:SetPos(x, y)
    c:SetSize(width, height)
    return c
  end)
  if not ok then
    warnCanvas(canvas)
    canvas = nil
  end
  local cover = canvas and draw.rect(parent, trackRgb, x, y, width, height)
  local texture, fill = "flat", nil

  local function redraw()
    local gradient = canvas ~= nil and texture ~= "flat"
    local filled = fill and math.floor(width * fill)
    draw.set(solid, "hidden", gradient or fill == nil)
    if canvas ~= nil then
      draw.set(canvas, "hidden", not gradient or fill == nil)
      draw.set(cover, "hidden", not gradient or fill == nil or filled == width)
    end
    if fill == nil then return end
    if gradient then
      draw.pos(cover, x + filled, y)
      draw.width(cover, width - filled)
    else
      draw.width(solid, filled)
    end
  end

  local bar = {}

  function bar.setFill(value)
    fill = value
    redraw()
  end

  function bar.setTexture(value)
    if value == texture then return end
    texture = value
    if canvas ~= nil and texture ~= "flat" then
      local light, dark = draw.opaque(mix(rgb, 0xffffff, LIGHTEN)), draw.opaque(mix(rgb, 0x000000, DARKEN))
      local drawn, err = pcall(function()
        canvas:Clear()
        if texture == "vertical" then
          canvas:AddGradientV(0, 0, width, height, light, dark)
        else
          canvas:AddGradientH(0, 0, width, height, dark, light)
        end
      end)
      if not drawn then
        warnCanvas(err)
        draw.set(canvas, "hidden", true)
        draw.set(cover, "hidden", true)
        canvas = nil
      end
    end
    redraw()
  end

  return bar
end

return draw
