-- Drawing primitives shared by the HUD elements, the options window and edit mode: fonts, colours, and
-- component builders and writers that skip unchanged values and log a refused property write once instead of
-- erroring. src/controls builds the window's buttons and fields on them.
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
  tooltipEdge = 0x3a3632,
  highlight = 0xffffff,
  -- The dark slot behind every aura icon, as the game's spellbook and ammo grids draw it.
  slot = 0x27231f,
  -- Edit mode and tooltip palette: warm near-black panels and a teal accent.
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

-- Options window palette: black panels, parchment text, and gold for what is chosen, with a white ring and dark
-- text. Its keys name the same roles as draw.COLOURS, so window code reads one palette or the other.
draw.WINDOW = {
  border = 0x000000,
  edge = 0x5a4b33,
  panel = 0x0c0b09,
  sidebar = 0x000000,
  row = 0x17140f,
  rowAlt = 0x201c16,
  line = 0x3a3326,
  popup = 0x17140f,
  button = 0x2b261f,
  buttonHover = 0x3d362c,
  bronze = 0x7a6a4c,
  accent = 0xf2c66d,
  accentHover = 0xf7d891,
  accentText = 0x140e03,
  ring = 0xffffff,
  text = 0xf4ead2,
  mutedText = 0xe0d3b2,
  dimText = 0xe0d3b2,
  darkText = 0x140e03,
  highlight = 0xffffff,
  editorTile = 0x2a2620,
}

local warned = {}
-- Last value written per component and field, so per-tick redraws only touch what changed.
local written = setmetatable({}, { __mode = "k" })
-- Each draw.edgedText label's edge: { copies, on, rgb }.
local edges = setmetatable({}, { __mode = "k" })
-- Label fields its edge copies repeat, and each copy's offset from the label.
local MIRRORED = { content = true, font = true, hidden = true, alpha = true, isShadowed = true }
local EDGE_OFFSETS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

local function writtenFor(obj)
  local fields = written[obj]
  if fields == nil then
    fields = {}
    written[obj] = fields
  end
  return fields
end

-- The edge of obj while it is on, or nil.
local function edgeOn(obj)
  local edge = edges[obj]
  return edge ~= nil and edge.on and edge or nil
end

local function assign(obj, field, value)
  obj[field] = value
end

-- Layers draw.hold covers, each with the hidden state its element last set, and whether they are held hidden.
local holdable = setmetatable({}, { __mode = "k" })
local holding = false
-- Each component built through draw.new and its parent, so draw.fade finds the components under a holdable
-- layer. Each component's root, the holdable layer it sits under or false, is cached until the next
-- draw.holdable.
local parents = setmetatable({}, { __mode = "k" })
local roots = setmetatable({}, { __mode = "k" })
-- The alpha each component was last given through draw.set, before draw.fade scales it, and the fade level.
local alphas = setmetatable({}, { __mode = "k" })
local fading = 1

-- The holdable layer obj sits under, or false.
local function rootOf(obj)
  local root = roots[obj]
  if root == nil then
    root = false
    local c = obj
    while c ~= nil do
      if holdable[c] ~= nil then
        root = c
        break
      end
      c = parents[c]
    end
    roots[obj] = root
  end
  return root
end

-- Writes value unless obj already holds it. A draw.edgedText label's edge copies take raw, the value as the
-- element set it, through draw.set.
local function write(obj, field, value, raw)
  local fields = writtenFor(obj)
  if fields[field] == value then
    return
  end
  local ok, err = pcall(assign, obj, field, value)
  if ok then
    fields[field] = value
    local edge = MIRRORED[field] and edgeOn(obj)
    if edge then
      if raw == nil then
        raw = value
      end
      for _, copy in ipairs(edge.copies) do
        draw.set(copy, field, raw)
      end
    end
  elseif not warned[field] then
    warned[field] = true
    log("cannot set " .. field .. ":", err)
  end
end

-- Writes a component property unless it already holds value, logging the first failure per property. A
-- draw.edgedText label's edge copies take the same write while its edge is on. A layer given to draw.holdable
-- stays hidden while draw.hold holds it, and takes the hidden state set meanwhile once released. A component
-- under a holdable layer takes its alpha scaled by the draw.fade level. Runs on every redraw, so it passes
-- assign to pcall rather than building a closure per write.
function draw.set(obj, field, value)
  local raw = value
  if field == "hidden" and holdable[obj] ~= nil then
    holdable[obj] = value
    value = value or holding
  elseif field == "alpha" then
    alphas[obj] = value
    if fading ~= 1 and rootOf(obj) then
      value = value * fading
    end
  end
  write(obj, field, value, raw)
end

-- Builds a component of kind, such as ui.Sprite, on parent. An element builds its components through this or
-- the builders below, so draw.fade reaches them.
function draw.new(kind, parent)
  local c = kind.new(parent)
  parents[c] = parent
  return c
end

-- Lets draw.hold hide layer, an element's root layer, whose hidden state the element sets through draw.set,
-- and draw.fade fade every component built on it through draw.new.
function draw.holdable(layer)
  holdable[layer] = writtenFor(layer).hidden == true
  roots = setmetatable({}, { __mode = "k" })
end

-- Hides every draw.holdable layer while held is true, and gives each back its own hidden state once false.
-- Writes nothing when held is unchanged.
function draw.hold(held)
  if held == holding then
    return
  end
  holding = held
  for layer, hidden in pairs(holdable) do
    write(layer, "hidden", hidden or held)
  end
end

-- Draws every component under a draw.holdable layer at level, from 0 to 1, times the alpha its element gave
-- it, and at that alpha again once level is 1. A layer's alpha does not fade its children, so each component
-- takes its own. Writes nothing when level is unchanged.
function draw.fade(level)
  if level == fading then
    return
  end
  fading = level
  for c in pairs(parents) do
    if rootOf(c) then
      local alpha = alphas[c] or 1
      write(c, "alpha", alpha * level, alpha)
    end
  end
end

-- Drops the remembered value of a component property, so the next draw.set writes it even when unchanged, as a
-- field whose text the player edited needs.
function draw.forget(obj, field)
  writtenFor(obj)[field] = nil
end

-- SetPos for components moved on every redraw; skips the call when the position is unchanged.
function draw.pos(obj, x, y)
  local fields = writtenFor(obj)
  if fields["SetPos.x"] == x and fields["SetPos.y"] == y then
    return
  end
  obj:SetPos(x, y)
  fields["SetPos.x"], fields["SetPos.y"] = x, y
  local edge = edgeOn(obj)
  if edge then
    for i, copy in ipairs(edge.copies) do
      draw.pos(copy, x + EDGE_OFFSETS[i][1], y + EDGE_OFFSETS[i][2])
    end
  end
end

-- SetPos with anchors as fractions of the parent, with the same unchanged-value skip as draw.pos.
function draw.place(obj, x, y, anchorX, anchorY)
  local fields = writtenFor(obj)
  if
    fields["place.x"] == x
    and fields["place.y"] == y
    and fields["place.anchorX"] == anchorX
    and fields["place.anchorY"] == anchorY
  then
    return
  end
  obj:SetPos(x, y, anchorX, anchorY)
  fields["place.x"], fields["place.y"], fields["place.anchorX"], fields["place.anchorY"] = x, y, anchorX, anchorY
end

-- SetWidth with the same unchanged-value skip as draw.pos.
function draw.width(obj, width)
  local fields = writtenFor(obj)
  if fields.SetWidth == width then
    return
  end
  obj:SetWidth(width)
  fields.SetWidth, fields["SetSize.w"] = width, width
end

-- SetSize with the same unchanged-value skip as draw.pos. A draw.edgedText label's edge copies follow it.
function draw.size(obj, width, height)
  local fields = writtenFor(obj)
  if fields["SetSize.w"] == width and fields["SetSize.h"] == height then
    return
  end
  obj:SetSize(width, height)
  fields["SetSize.w"], fields["SetSize.h"], fields.SetWidth = width, height, width
  local edge = edgeOn(obj)
  if edge then
    for _, copy in ipairs(edge.copies) do
      draw.size(copy, width, height)
    end
  end
end

function draw.rect(parent, rgb, x, y, width, height)
  local r = draw.new(ui.Rectangle, parent)
  draw.set(r, "fill", true)
  draw.set(r, "rgb", rgb)
  draw.pos(r, x, y)
  draw.size(r, width, height)
  return r
end

-- A white, shadowed label in font, aligned horizontal and centred vertically.
function draw.text(parent, font, horizontal, x, y, width, height)
  local t = draw.new(ui.Text, parent)
  draw.set(t, "font", font)
  draw.set(t, "rgb", draw.COLOURS.text)
  draw.set(t, "isShadowed", true)
  t:AlignTo(horizontal, ui.AlignMode.CENTRE)
  draw.pos(t, x, y)
  draw.size(t, width, height)
  return t
end

-- A draw.text label with four hidden copies under it, offset 1px diagonally, that draw.setEdge shows as an
-- outline. Built before the label so they draw beneath it.
function draw.edgedText(parent, font, horizontal, x, y, width, height)
  local copies = {}
  for i, offset in ipairs(EDGE_OFFSETS) do
    copies[i] = draw.text(parent, font, horizontal, x + offset[1], y + offset[2], width, height)
    draw.set(copies[i], "hidden", true)
  end
  local t = draw.text(parent, font, horizontal, x, y, width, height)
  edges[t] = { copies = copies, on = false }
  return t
end

-- Shows a draw.edgedText label's outline in rgb, or hides it when rgb is nil. Once on, the copies take every
-- change to the label's content, font, visibility, alpha, shadow, position and size.
function draw.setEdge(label, rgb)
  local edge = edges[label]
  if edge.rgb == rgb and edge.on == (rgb ~= nil) then
    return
  end
  edge.on = rgb ~= nil
  edge.rgb = rgb
  if rgb == nil then
    draw.hideAll(edge.copies, true)
    return
  end
  local fields = writtenFor(label)
  for i, copy in ipairs(edge.copies) do
    draw.set(copy, "rgb", rgb)
    for field in pairs(MIRRORED) do
      -- The label's alpha as its element set it, which draw.set scales again for the copy.
      local value = fields[field]
      if field == "alpha" then
        value = alphas[label]
      end
      if value ~= nil then
        draw.set(copy, field, value)
      end
    end
    draw.set(copy, "hidden", fields.hidden == true)
    draw.pos(copy, fields["SetPos.x"] + EDGE_OFFSETS[i][1], fields["SetPos.y"] + EDGE_OFFSETS[i][2])
    draw.size(copy, fields["SetSize.w"], fields["SetSize.h"])
  end
end

-- draw.text in the options window's parchment.
function draw.windowText(parent, font, horizontal, x, y, width, height)
  local t = draw.text(parent, font, horizontal, x, y, width, height)
  draw.set(t, "rgb", draw.WINDOW.text)
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
  local g = c.xyGlobal
  local mx = Mouse.GetX()
  scale = g ~= nil and mx ~= nil and g.x + x > 0 and mx / (g.x + x) or 1
end

function draw.cursor()
  local mx = Mouse.GetX()
  local my = Mouse.GetY()
  if mx == nil or my == nil then
    return nil
  end
  return mx / scale, my / scale
end

function draw.hideAll(components, hidden)
  for _, c in ipairs(components) do
    draw.set(c, "hidden", hidden)
  end
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
    group.x = x
    group.y = y
    for _, m in ipairs(members) do
      draw.pos(m.c, x + m.dx, y + m.dy)
    end
  end

  function group.set(field, value)
    for _, m in ipairs(members) do
      draw.set(m.c, field, value)
    end
  end

  return group
end

-- Shows icon on the ui.Sprite c: a sprite id, or minus an item id for an icon the client draws from an item.
-- Skips an unchanged icon.
function draw.icon(c, icon)
  local fields = writtenFor(c)
  local last = fields.icon
  if last == icon then
    return
  end
  if icon < 0 then
    c:SetAssociatedObject(-icon)
  else
    if last ~= nil and last < 0 then
      c:SetAssociatedObject(-1)
    end
    c.sprite = icon
  end
  fields.icon = icon
end

-- Shows a src/cooldowns tile's icon on sprite, or its initials on label when it has no icon.
function draw.iconOrInitials(sprite, label, tile)
  draw.set(sprite, "hidden", tile.icon == nil)
  if tile.icon ~= nil then
    draw.icon(sprite, tile.icon)
  end
  draw.set(label, "hidden", tile.icon ~= nil)
  draw.set(label, "content", tile.initials)
end

-- Four thin rects forming a box outline; returns them for moving and hiding.
function draw.outline(parent, rgb, thickness)
  return {
    draw.rect(parent, rgb, 0, 0, 0, 0),
    draw.rect(parent, rgb, 0, 0, 0, 0),
    draw.rect(parent, rgb, 0, 0, 0, 0),
    draw.rect(parent, rgb, 0, 0, 0, 0),
    thickness = thickness,
  }
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

local DASH = 6
local DASH_GAP = 4

-- Redraws canvas as a w by h box outline of dashes thickness wide, inside its edges. rgba is 0xRRGGBBAA.
function draw.dashedBox(canvas, w, h, thickness, rgba)
  canvas:Clear()
  draw.dashedBoxAt(canvas, 0, 0, w, h, thickness, rgba)
end

-- Adds a dashed box at x, y to canvas without clearing it, so one canvas can hold several.
function draw.dashedBoxAt(canvas, x0, y0, w, h, thickness, rgba)
  for x = 0, w - 1, DASH + DASH_GAP do
    local length = math.min(DASH, w - x)
    canvas:AddRectangle(x0 + x, y0, length, thickness, rgba)
    canvas:AddRectangle(x0 + x, y0 + h - thickness, length, thickness, rgba)
  end
  for y = 0, h - 1, DASH + DASH_GAP do
    local length = math.min(DASH, h - y)
    canvas:AddRectangle(x0, y0 + y, thickness, length, rgba)
    canvas:AddRectangle(x0 + w - thickness, y0 + y, thickness, length, rgba)
  end
end

-- Gradient ends as fractions toward white and black.
local LIGHTEN = 0.15
local DARKEN = 0.35

-- Moves each channel of a 0xRRGGBB colour toward target by amount, from 0 to 1.
local function mix(rgb, target, amount)
  local out = 0
  for shift = 16, 0, -8 do
    local from = (rgb >> shift) & 0xFF
    local to = (target >> shift) & 0xFF
    out = out | (math.floor(from + (to - from) * amount + 0.5) << shift)
  end
  return out
end

-- Canvas colours are 0xRRGGBBAA.
function draw.opaque(rgb)
  return (rgb << 8) | 0xFF
end

-- A bar fill over its track, flat or with a savedappearance.TEXTURES gradient. The gradient is drawn once per
-- texture on a canvas, and a track-coloured cover hides the empty part, so a fill change moves one rect.
-- Returns { setFill(fill from 0 to 1, or nil to hide), setTexture(texture), setColour(rgb), setBox(x, y, w, h),
-- parts }, parts listing its components.
function draw.bar(parent, rgb, trackRgb, x, y, width, height)
  local solid = draw.rect(parent, rgb, x, y, width, height)
  local canvas = draw.new(ui.Canvas, parent)
  draw.pos(canvas, x, y)
  draw.size(canvas, width, height)
  local cover = draw.rect(parent, trackRgb, x, y, width, height)
  local texture = "flat"
  local fill = nil

  local function redraw()
    local gradient = texture ~= "flat"
    local filled = fill and math.floor(width * fill)
    draw.set(solid, "hidden", gradient or fill == nil)
    draw.set(canvas, "hidden", not gradient or fill == nil)
    draw.set(cover, "hidden", not gradient or fill == nil or filled == width)
    if fill == nil then
      return
    end
    if gradient then
      draw.pos(cover, x + filled, y)
      draw.width(cover, width - filled)
    else
      draw.width(solid, filled)
    end
  end

  local bar = { parts = { solid, canvas, cover } }

  function bar.setFill(value)
    fill = value
    redraw()
  end

  -- Draws the gradient for the texture and colour, once per change.
  local function paint()
    if texture ~= "flat" then
      local light = draw.opaque(mix(rgb, 0xffffff, LIGHTEN))
      local dark = draw.opaque(mix(rgb, 0x000000, DARKEN))
      canvas:Clear()
      if texture == "vertical" then
        canvas:AddGradientV(0, 0, width, height, light, dark)
      else
        canvas:AddGradientH(0, 0, width, height, dark, light)
      end
    end
    redraw()
  end

  function bar.setTexture(value)
    if value == texture then
      return
    end
    texture = value
    paint()
  end

  function bar.setColour(value)
    if value == rgb then
      return
    end
    rgb = value
    draw.set(solid, "rgb", rgb)
    paint()
  end

  -- Moves and resizes the bar, repainting the gradient at a new size.
  function bar.setBox(newX, newY, w, h)
    if newX == x and newY == y and w == width and h == height then
      return
    end
    local resized = w ~= width or h ~= height
    x = newX
    y = newY
    width = w
    height = h
    for _, part in ipairs(bar.parts) do
      draw.pos(part, x, y)
      draw.size(part, w, h)
    end
    if resized then
      paint()
    else
      redraw()
    end
  end

  return bar
end

return draw
