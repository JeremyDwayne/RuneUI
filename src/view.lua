-- Draws RuneUI elements on the plugin layer from display models, in a flat dark style.
-- Each constructor returns { layer, update(model), width, height }, plus setTexture(texture) for elements
-- with bars; place() positions a layer on the game window.
local view = {}

local draw = require("src/draw")
local frames = require("src/frames")
local set, pos, rect, text = draw.set, draw.pos, draw.rect, draw.text
local FONTS, COLOURS = draw.FONTS, draw.COLOURS

-- Tile backgrounds are translucent so the game shows through empty tiles.
local TILE_ALPHA = 0.6

-- at: { x, y, anchorX, anchorY }, with anchors as fractions of the game window.
function view.place(layer, at)
  layer:SetPos(at.x, at.y, at.anchorX, at.anchorY)
end

local FRAME_WIDTH = 250
local HEALTH_HEIGHT = 46
local POWER_HEIGHT = 6

-- A unit frame bar with the name on the left and the value on the right; returns its update(model) and
-- the draw.bar under it.
local function unitBar(layer, rgb, y, height)
  local inner = FRAME_WIDTH - 2
  rect(layer, COLOURS.healthTrack, 1, y, inner, height)
  local bar = draw.bar(layer, rgb, COLOURS.healthTrack, 1, y, inner, height)
  local name = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 6, y, 140, height)
  local value = text(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, FRAME_WIDTH - 101, y, 95, height)
  local function update(model)
    bar.setFill(model.fill)
    set(name, "content", model.name)
    set(value, "content", model.valueText)
  end
  return update, bar
end

-- 250x55: 46px health bar with name and "13.1K | 78%", 6px prayer bar below.
function view.playerFrame(root)
  local height = HEALTH_HEIGHT + POWER_HEIGHT + 3
  local prayerY = HEALTH_HEIGHT + 2
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, height)
  rect(layer, COLOURS.border, 0, 0, FRAME_WIDTH, height)
  local updateHealth, health = unitBar(layer, COLOURS.player, 1, HEALTH_HEIGHT)
  local prayerTrack = rect(layer, COLOURS.healthTrack, 1, prayerY, FRAME_WIDTH - 2, POWER_HEIGHT)
  local prayer = draw.bar(layer, COLOURS.prayer, COLOURS.healthTrack, 1, prayerY, FRAME_WIDTH - 2, POWER_HEIGHT)

  local function update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then return end
    updateHealth(model)
    set(prayerTrack, "hidden", model.prayerText == nil)
    prayer.setFill(model.prayerFill)
  end

  local function setTexture(texture)
    health.setTexture(texture)
    prayer.setTexture(texture)
  end

  return { layer = layer, update = update, setTexture = setTexture, width = FRAME_WIDTH, height = height }
end

local DEBUFF_SIZE = 26
local MAX_DEBUFFS = 8
local DEBUFF_ROW = DEBUFF_SIZE + 4

-- 250x78: a right-aligned row of debuff icons above a 46px health bar with name and "6,800 | 58%".
function view.targetFrame(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, DEBUFF_ROW + HEALTH_HEIGHT + 2)
  rect(layer, COLOURS.border, 0, DEBUFF_ROW, FRAME_WIDTH, HEALTH_HEIGHT + 2)
  local updateHealth, health = unitBar(layer, COLOURS.target, DEBUFF_ROW + 1, HEALTH_HEIGHT)

  local debuffs = {}
  for i = 1, MAX_DEBUFFS do
    local edge = rect(layer, COLOURS.border, 0, 0, DEBUFF_SIZE, DEBUFF_SIZE)
    local icon = ui.Sprite.new(layer)
    icon:SetSize(DEBUFF_SIZE - 2, DEBUFF_SIZE - 2)
    debuffs[i] = { edge = edge, icon = icon }
  end

  local function update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then return end
    updateHealth(model)
    local count = math.min(#model.debuffs, MAX_DEBUFFS)
    for i, slot in ipairs(debuffs) do
      local shown = i <= count
      set(slot.edge, "hidden", not shown)
      set(slot.icon, "hidden", not shown)
      if shown then
        local x = FRAME_WIDTH - (count - i + 1) * (DEBUFF_SIZE + 2) + 2
        pos(slot.edge, x, 0)
        pos(slot.icon, x + 1, 1)
        set(slot.icon, "sprite", model.debuffs[i])
      end
    end
  end

  return {
    layer = layer, update = update, setTexture = health.setTexture,
    width = FRAME_WIDTH, height = DEBUFF_ROW + HEALTH_HEIGHT + 2,
  }
end

local BAR_WIDTH = 278
local SPENDER_ROW = 8
-- Spender rows stack upward from just above the bar, one per spender with stacks.
local BAR_Y = 2 * (SPENDER_ROW + 2)
local BAR_HEIGHT = 20
local NOTCH = 7
local SPENDER_COLOURS = { souls = COLOURS.spender, necrosis = COLOURS.necrosis }
-- Fill fraction at which the centred percent label sits entirely on the fill.
local PERCENT_ON_FILL = 0.56

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

-- 278 wide: up to two rows of spender blocks, the adrenaline bar with its percent, and marker notches
-- below the bar so they never cross the percent.
function view.resourceBar(root)
  local height = BAR_Y + BAR_HEIGHT + NOTCH
  local layer = ui.Layer.new(root)
  layer:SetSize(BAR_WIDTH, height)

  -- One canvas per spender row, redrawn only when its spender, count or max changes.
  local rows = {}
  for r = 1, #frames.SPENDERS do
    local canvas = ui.Canvas.new(layer)
    canvas:SetSize(BAR_WIDTH, SPENDER_ROW)
    rows[r] = { canvas = canvas }
  end

  rect(layer, COLOURS.border, 0, BAR_Y, BAR_WIDTH, BAR_HEIGHT)
  rect(layer, COLOURS.track, 1, BAR_Y + 1, BAR_WIDTH - 2, BAR_HEIGHT - 2)
  local fill = draw.bar(layer, COLOURS.adrenaline, COLOURS.track, 1, BAR_Y + 1, BAR_WIDTH - 2, BAR_HEIGHT - 2)
  -- Light notches with black edges hang from the bar's bottom edge.
  local markers = {}
  for i = 1, 2 do
    markers[i] = {
      edge = rect(layer, COLOURS.border, 0, BAR_Y + BAR_HEIGHT, 4, NOTCH),
      line = rect(layer, COLOURS.marker, 0, BAR_Y + BAR_HEIGHT, 2, NOTCH - 1),
    }
  end
  local percent = text(layer, FONTS.body, ui.AlignMode.CENTRE, 0, BAR_Y + 1, BAR_WIDTH, BAR_HEIGHT - 2)

  -- Black-edged blocks, filled up to the spender's count.
  local function drawBlocks(canvas, spender)
    canvas:Clear()
    local edge = draw.opaque(COLOURS.border)
    for i, span in ipairs(blockSpans(spender.max, BAR_WIDTH)) do
      local rgb = i <= spender.count and SPENDER_COLOURS[spender.key] or COLOURS.emptyBlock
      canvas:AddRectangle(span.x, 0, span.w, SPENDER_ROW, edge)
      canvas:AddRectangle(span.x + 1, 1, span.w - 2, SPENDER_ROW - 2, draw.opaque(rgb))
    end
  end

  local function updateSpenders(spenders)
    for r, row in ipairs(rows) do
      local spender = spenders[r]
      set(row.canvas, "hidden", spender == nil)
      if spender ~= nil then
        pos(row.canvas, 0, BAR_Y - (#spenders - r + 1) * (SPENDER_ROW + 2))
        if row.key ~= spender.key or row.count ~= spender.count or row.max ~= spender.max then
          row.key, row.count, row.max = spender.key, spender.count, spender.max
          drawBlocks(row.canvas, spender)
        end
      end
    end
  end

  local function update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then return end
    fill.setFill(model.fill)
    set(percent, "content", model.text)
    -- Dark text once the fill passes the centred label, white with a shadow on the track.
    local onFill = model.fill >= PERCENT_ON_FILL
    set(percent, "rgb", onFill and COLOURS.darkText or COLOURS.text)
    set(percent, "isShadowed", not onFill)
    for i, marker in ipairs(model.markers) do
      local x = math.min(math.floor(marker.at * (BAR_WIDTH - 2)), BAR_WIDTH - 3)
      pos(markers[i].edge, x - 1, BAR_Y + BAR_HEIGHT)
      pos(markers[i].line, x, BAR_Y + BAR_HEIGHT)
    end
    updateSpenders(model.spenders)
  end

  return { layer = layer, update = update, setTexture = fill.setTexture, width = BAR_WIDTH, height = height }
end

-- Tile sizes: 42px tiles for the rotation and 36px for cooldowns, 2px apart. Each row's
-- combat style accent sits on its outer edge, away from the resource bar between them.
view.TILE_STYLES = {
  rotation = { size = 42, gap = 2, secondsFont = FONTS.seconds, accent = "bottom" },
  cooldowns = { size = 36, gap = 2, secondsFont = FONTS.smallSeconds, accent = "top" },
}
-- Accent colours by cooldowns tracker style.
view.STYLE_COLOURS = { necromancy = 0x6f4ad8, magic = 0x2f7fd6, melee = 0xb8352f, ranged = 0x3c9a4a }
-- A 2px accent line inside a 1px black edge, and the space it takes with a 1px gap to the tiles.
local ACCENT, ACCENT_SPACE = 2, 5
local MAX_TILES = 10
local COOLING_DIM = 0.62

-- Builds one tile's components in a row starting top pixels down; place(x) moves them all, keeping each
-- part's offset in the tile.
local function tile(layer, style, top)
  local size = style.size
  local offsets = {}
  local function at(component, dx, dy)
    offsets[#offsets + 1] = { component = component, dx = dx, dy = top + dy }
    return component
  end
  local parts = {
    edge = at(rect(layer, COLOURS.border, 0, 0, size, size), 0, 0),
    background = at(rect(layer, COLOURS.tile, 0, 0, size - 2, size - 2), 1, 1),
    icon = at(ui.Sprite.new(layer), 1, 1),
  }
  parts.icon:SetSize(size - 2, size - 2)
  set(parts.background, "alpha", TILE_ALPHA)
  parts.initials = at(text(layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, size - 8, 12), 4, size - 15)
  parts.dim = at(rect(layer, COLOURS.border, 0, 0, size - 2, size - 2), 1, 1)
  set(parts.dim, "alpha", COOLING_DIM)
  parts.keybind = at(text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 21, 12), size - 24, 2)
  parts.seconds = at(text(layer, style.secondsFont, ui.AlignMode.CENTRE, 0, 0, size, size), 0, 0)

  function parts.place(x)
    for _, o in ipairs(offsets) do pos(o.component, x + o.dx, o.dy) end
  end

  function parts.setHidden(hidden)
    for _, o in ipairs(offsets) do set(o.component, "hidden", hidden) end
  end

  return parts
end

-- A centred row of up to 10 ability tiles with an accent line as wide as the shown tiles. update takes
-- src/cooldowns tiles and the accent colour, or nil to hide the line. Ready tiles are bright with their
-- keybind; cooling tiles are dimmed with whole seconds left.
function view.cooldownGroup(root, style)
  local step = style.size + style.gap
  local width = MAX_TILES * step - style.gap
  local height = style.size + ACCENT_SPACE
  local layer = ui.Layer.new(root)
  layer:SetSize(width, height)
  local top = style.accent == "top" and ACCENT_SPACE or 0
  local accentY = style.accent == "top" and 0 or style.size + 1
  local accentEdge = rect(layer, COLOURS.border, 0, accentY, width, ACCENT + 2)
  local accent = rect(layer, COLOURS.border, 1, accentY + 1, width - 2, ACCENT)
  local tiles = {}
  for i = 1, MAX_TILES do tiles[i] = tile(layer, style, top) end

  local function update(models, accentRgb)
    local count = math.min(#models, MAX_TILES)
    local offset = math.floor((width - (count * step - style.gap)) / 2)
    local accentShown = accentRgb ~= nil and count > 0
    set(accentEdge, "hidden", not accentShown)
    set(accent, "hidden", not accentShown)
    if accentShown then
      local rowWidth = count * step - style.gap
      set(accent, "rgb", accentRgb)
      pos(accentEdge, offset, accentY)
      draw.width(accentEdge, rowWidth)
      pos(accent, offset + 1, accentY + 1)
      draw.width(accent, rowWidth - 2)
    end
    for i, parts in ipairs(tiles) do
      local model = models[i]
      parts.setHidden(model == nil)
      if model ~= nil then
        parts.place(offset + (i - 1) * step)
        set(parts.icon, "hidden", model.icon == nil)
        if model.icon ~= nil then set(parts.icon, "sprite", model.icon) end
        set(parts.initials, "hidden", model.icon ~= nil)
        set(parts.initials, "content", model.initials)
        set(parts.dim, "hidden", model.ready)
        set(parts.keybind, "hidden", model.keybind == nil)
        set(parts.keybind, "content", model.keybind or "")
        set(parts.seconds, "hidden", model.ready)
        set(parts.seconds, "content", model.seconds and tostring(model.seconds) or "")
        local labelColour = model.ready and COLOURS.text or COLOURS.dimText
        set(parts.initials, "rgb", labelColour)
        set(parts.keybind, "rgb", labelColour)
      end
    end
  end

  return { layer = layer, update = update, width = width, height = height }
end

return view
