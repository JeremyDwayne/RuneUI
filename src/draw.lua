-- Drawing primitives shared by src/view, src/options and src/editmode: fonts, colours, component builders that
-- skip unchanged writes and log a refused property write once instead of erroring, buttons, and the cursor.
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
  cast = 0x23706a,
  marker = 0xdfe4ea,
  text = 0xffffff,
  darkText = 0x111316,
  spender = 0xdfe4ea,
  necrosis = 0x9b59d0,
  emptyBlock = 0x22262b,
  tile = 0x141414,
  dimText = 0xc7ccd1,
  tooltipEdge = 0x3a3632,
  highlight = 0xffffff,
  debuff = 0xff8a1f,
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
  -- Edit mode: anchored buttons and the hovered anchor spot, and the other spots' edges.
  chip = 0xdfe4ea,
  spotEdge = 0x6b645c,
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

-- SetPos with anchors as fractions of the parent, with the same unchanged-value skip as draw.pos.
function draw.place(obj, x, y, anchorX, anchorY)
  local fields = writtenFor(obj)
  if fields["place.x"] == x and fields["place.y"] == y and fields["place.anchorX"] == anchorX
    and fields["place.anchorY"] == anchorY then return end
  obj:SetPos(x, y, anchorX, anchorY)
  fields["place.x"], fields["place.y"], fields["place.anchorX"], fields["place.anchorY"] = x, y, anchorX, anchorY
end

-- SetWidth with the same unchanged-value skip as draw.pos.
function draw.width(obj, width)
  local fields = writtenFor(obj)
  if fields.SetWidth == width then return end
  obj:SetWidth(width)
  fields.SetWidth = width
end

-- SetSize with the same unchanged-value skip as draw.pos.
function draw.size(obj, width, height)
  local fields = writtenFor(obj)
  if fields["SetSize.w"] == width and fields["SetSize.h"] == height then return end
  obj:SetSize(width, height)
  fields["SetSize.w"], fields["SetSize.h"] = width, height
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

-- The two-argument AlignTo raised a newindex error in the client; fall back to the one-argument form,
-- which applies the alignment to both axes.
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

-- Makes c take clicks and stop them, like a button: plain components start enabled = false and
-- clickthrough = true, so a click reaches everything beneath and the game world. Each clickable thing has
-- one hit area at the bottom; components drawn over it keep the defaults and pass clicks down to it.
function draw.hitArea(c)
  draw.set(c, "enabled", true)
  draw.set(c, "clickthrough", false)
  return c
end

function draw.on(c, hook, fn)
  c:Subscribe(ui.Hook[hook], fn)
end

-- Mouse reports physical pixels, a multiple of UI units on a high-DPI display. pressAt sets the multiple
-- from a press at local x on c, and cursor returns the mouse in UI units, or nil when there is none.
local scale = 1

function draw.pressAt(c, x)
  local g, mx = c.xyGlobal, Mouse.GetX()
  scale = g ~= nil and mx ~= nil and g.x + x > 0 and mx / (g.x + x) or 1
end

function draw.cursor()
  local mx, my = Mouse.GetX(), Mouse.GetY()
  if mx == nil or my == nil then return nil end
  return mx / scale, my / scale
end

-- Button fills: normal and hover colours, and dark text for the bright ones.
local FILLS = {
  plain = { draw.COLOURS.button, draw.COLOURS.buttonHover },
  accent = { draw.COLOURS.accent, draw.COLOURS.accentHover, dark = true },
  light = { draw.COLOURS.highlight, draw.COLOURS.dimText, dark = true },
}

-- A flat button with a centred label that lightens on hover. fill names a FILLS entry, plain when nil.
-- Returns { bg, label }.
function draw.button(parent, label, x, y, w, h, fill, onClick)
  local colours = FILLS[fill or "plain"]
  local normal, hover = colours[1], colours[2]
  local bg = draw.hitArea(draw.rect(parent, normal, x, y, w, h))
  local t = draw.text(parent, draw.FONTS.body, ui.AlignMode.CENTRE, x, y, w, h)
  draw.set(t, "content", label)
  if colours.dark then
    draw.set(t, "rgb", draw.COLOURS.accentText)
    draw.set(t, "isShadowed", false)
  end
  draw.on(bg, "ONMOUSEOVER", function() draw.set(bg, "rgb", hover) end)
  draw.on(bg, "ONMOUSELEAVE", function() draw.set(bg, "rgb", normal) end)
  draw.on(bg, "ONCLICK", function() onClick() end)
  return { bg = bg, label = t }
end

function draw.hideAll(components, hidden)
  for _, c in ipairs(components) do draw.set(c, "hidden", hidden) end
end

-- Components that move together, each at a fixed offset from the group's top-left. add(c, dx, dy) returns
-- c; place(x, y) moves them all and keeps x and y on the group; set(field, value) writes it on each.
function draw.group()
  local members = {}
  local group = {}

  function group.add(c, dx, dy)
    members[#members + 1] = { c = c, dx = dx, dy = dy }
    return c
  end

  function group.place(x, y)
    group.x, group.y = x, y
    for _, m in ipairs(members) do draw.pos(m.c, x + m.dx, y + m.dy) end
  end

  function group.set(field, value)
    for _, m in ipairs(members) do draw.set(m.c, field, value) end
  end

  return group
end

-- Shows a src/cooldowns tile's icon on sprite, or its initials on label when it has no icon.
function draw.iconOrInitials(sprite, label, tile)
  draw.set(sprite, "hidden", tile.icon == nil)
  if tile.icon ~= nil then draw.set(sprite, "sprite", tile.icon) end
  draw.set(label, "hidden", tile.icon ~= nil)
  draw.set(label, "content", tile.initials)
end

-- Four thin rects forming a box outline; returns them for moving and hiding.
function draw.outline(parent, rgb, thickness)
  return { draw.rect(parent, rgb, 0, 0, 0, 0), draw.rect(parent, rgb, 0, 0, 0, 0), draw.rect(parent, rgb, 0, 0, 0, 0),
    draw.rect(parent, rgb, 0, 0, 0, 0), thickness = thickness }
end

-- Places an outline around the box at x, y sized w by h, its thickness drawn outside.
function draw.placeOutline(box, x, y, w, h)
  local t = box.thickness
  draw.pos(box[1], x - t, y - t)
  draw.size(box[1], w + 2 * t, t)
  draw.pos(box[2], x - t, y + h)
  draw.size(box[2], w + 2 * t, t)
  draw.pos(box[3], x - t, y)
  draw.size(box[3], t, h)
  draw.pos(box[4], x + w, y)
  draw.size(box[4], t, h)
end

local DASH, DASH_GAP = 6, 4

-- Redraws canvas as a w by h box outline of dashes thickness wide, inside its edges. rgba is 0xRRGGBBAA.
function draw.dashedBox(canvas, w, h, thickness, rgba)
  canvas:Clear()
  for x = 0, w - 1, DASH + DASH_GAP do
    local length = math.min(DASH, w - x)
    canvas:AddRectangle(x, 0, length, thickness, rgba)
    canvas:AddRectangle(x, h - thickness, length, thickness, rgba)
  end
  for y = 0, h - 1, DASH + DASH_GAP do
    local length = math.min(DASH, h - y)
    canvas:AddRectangle(0, y, thickness, length, rgba)
    canvas:AddRectangle(w - thickness, y, thickness, length, rgba)
  end
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

-- A bar fill over its track, flat or with a settings.TEXTURES gradient. The gradient is drawn once per
-- texture on a canvas, and a track-coloured cover hides the empty part, so a fill change moves one rect.
-- Returns { setFill(fill from 0 to 1, or nil to hide), setTexture(texture) }.
function draw.bar(parent, rgb, trackRgb, x, y, width, height)
  local solid = draw.rect(parent, rgb, x, y, width, height)
  local canvas = ui.Canvas.new(parent)
  canvas:SetPos(x, y)
  canvas:SetSize(width, height)
  local cover = draw.rect(parent, trackRgb, x, y, width, height)
  local texture, fill = "flat", nil

  local function redraw()
    local gradient = texture ~= "flat"
    local filled = fill and math.floor(width * fill)
    draw.set(solid, "hidden", gradient or fill == nil)
    draw.set(canvas, "hidden", not gradient or fill == nil)
    draw.set(cover, "hidden", not gradient or fill == nil or filled == width)
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
    if texture ~= "flat" then
      local light, dark = draw.opaque(mix(rgb, 0xffffff, LIGHTEN)), draw.opaque(mix(rgb, 0x000000, DARKEN))
      canvas:Clear()
      if texture == "vertical" then
        canvas:AddGradientV(0, 0, width, height, light, dark)
      else
        canvas:AddGradientH(0, 0, width, height, dark, light)
      end
    end
    redraw()
  end

  return bar
end

return draw
