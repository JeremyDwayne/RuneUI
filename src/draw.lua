-- Drawing primitives shared by src/view and src/options: fonts, colours, and component builders that
-- log a refused property write once instead of erroring.
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

-- Writes a component property, logging the first failure per property instead of erroring.
function draw.set(obj, field, value)
  local ok, err = pcall(function() obj[field] = value end)
  if not ok and not warned[field] then
    warned[field] = true
    log("cannot set " .. field .. ":", err)
  end
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

-- Sets a bar's width from a 0..1 fill, hiding it when the fill is unknown.
function draw.setFill(bar, fill, fullWidth)
  draw.set(bar, "hidden", fill == nil)
  if fill ~= nil then bar:SetWidth(math.floor(fullWidth * fill)) end
end

return draw
