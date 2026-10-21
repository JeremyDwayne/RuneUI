-- Draws RuneUI elements on the plugin layer from display models, in a flat dark style.
-- Each constructor returns { layer, update(model), setLook(look), width, height, bounds }. setLook takes a
-- src/style look, returns at once for the look the element shows, and returns whether bounds changed. bounds is
-- the shown { x, y, w, h } inside the layer. place() positions a layer on the game window and arrange() places
-- every element from saved positions and anchors.
local view = {}

local draw = require("src/draw")
local frames = require("src/frames")
local layout = require("src/layout")
local settings = require("src/settings")
local style = require("src/style")
local set = draw.set
local pos = draw.pos
local rect = draw.rect
local text = draw.text
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS

-- Tile backgrounds are translucent so the game shows through empty tiles.
local TILE_ALPHA = 0.6

-- at: { x, y, anchorX, anchorY }, with anchors as fractions of the game window.
function view.place(layer, at)
  draw.place(layer, at.x, at.y, at.anchorX, at.anchorY)
end

-- Places elements, by name, at positions resolved from src/layout anchors against their bounds. Called at
-- load and on a tick where a cooldown row's bounds changed. Returns the resolved positions.
function view.arrange(elements, positions, anchors)
  local bounds = {}
  for name, element in pairs(elements) do
    bounds[name] = element.bounds
  end
  local resolved = layout.resolve(positions, anchors, bounds)
  for name, element in pairs(elements) do
    view.place(element.layer, resolved[name])
  end
  return resolved
end

local TOOLTIP_WIDTH = 200
local TOOLTIP_PAD = 8
local TOOLTIP_GAP = 6
-- Characters of info that fit one tooltip line in the small font.
local TOOLTIP_LINE_CHARS = 34

-- One tooltip for every HUD icon: a dark panel above the hovered icon, below it when there is no room, kept
-- inside the side edges, with a white outline on the icon. show(content, x, y, size) takes the icon's screen
-- position and { title, left, right, line }, where line may wrap to two lines; hide() clears it and
-- destroy() removes it. It draws above the HUD from its first show. hover(items, show) wires each item's
-- edge to the tooltip.
function view.tooltip(root)
  local layer = ui.Layer.new(root)
  local edge = rect(layer, COLOURS.border, 0, 0, TOOLTIP_WIDTH, 0)
  local inner = rect(layer, COLOURS.tooltipEdge, 1, 1, TOOLTIP_WIDTH - 2, 0)
  local panel = rect(layer, COLOURS.panel, 2, 2, TOOLTIP_WIDTH - 4, 0)
  local textWidth = TOOLTIP_WIDTH - 2 * TOOLTIP_PAD
  local title = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 6, textWidth, 16)
  local left = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 24, textWidth, 14)
  local right = text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, TOOLTIP_PAD, 24, textWidth, 14)
  local line = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 40, textWidth, 28)
  set(left, "rgb", COLOURS.dimText)
  set(right, "rgb", COLOURS.dimText)
  local highlight = draw.outline(root, COLOURS.highlight, 2)
  local height = nil
  local raised = false
  local tooltip = {}

  local function setHidden(hidden)
    set(layer, "hidden", hidden)
    draw.hideAll(highlight, hidden)
  end
  setHidden(true)

  function tooltip.show(content, x, y, size)
    set(title, "content", content.title)
    set(left, "content", content.left or "")
    set(right, "content", content.right or "")
    set(line, "content", content.line or "")
    local lines = 0
    if content.line ~= nil then
      lines = #content.line > TOOLTIP_LINE_CHARS and 2 or 1
    end
    local h = 46 + lines * 14 - (lines == 0 and 6 or 0)
    if h ~= height then
      height = h
      layer:SetSize(TOOLTIP_WIDTH, h)
      edge:SetHeight(h)
      inner:SetHeight(h - 2)
      panel:SetHeight(h - 4)
    end
    local top = y - h - TOOLTIP_GAP
    if top < 0 then
      top = y + size + TOOLTIP_GAP
    end
    local screenWidth = tonumber(root.width)
    local panelX = x
    if screenWidth ~= nil and screenWidth > TOOLTIP_WIDTH then
      panelX = math.max(0, math.min(x, screenWidth - TOOLTIP_WIDTH))
    end
    pos(layer, panelX, top)
    draw.placeOutline(highlight, x + 2, y + 2, size - 4, size - 4)
    setHidden(false)
    -- The client stops drawing a component moved to the front while hidden, so this waits for the first show.
    if not raised then
      raised = true
      layer:MoveToFront()
      for _, side in ipairs(highlight) do
        side:MoveToFront()
      end
    end
  end

  function tooltip.hide()
    setHidden(true)
  end

  function tooltip.destroy()
    layer:Destroy()
    for _, side in ipairs(highlight) do
      side:Destroy()
    end
  end

  -- Entering item i's edge calls show(i) and leaving the hovered edge hides the tooltip. Returns a table
  -- whose index is the hovered item's, or nil, so an update can redraw the tooltip it shows, and whose
  -- add(item) wires one more item as the next index.
  function tooltip.hover(items, show)
    local hover = {}
    local count = 0

    function hover.add(item)
      count = count + 1
      local i = count
      item.edge:Subscribe(ui.Hook.ONMOUSEOVER, function()
        hover.index = i
        show(i)
      end)
      item.edge:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if hover.index == i then
          hover.index = nil
          tooltip.hide()
        end
      end)
    end

    for _, item in ipairs(items) do
      hover.add(item)
    end
    return hover
  end

  return tooltip
end

-- Screen position of a point inside a layer parented to the plugin layer.
local function screenPos(layer, x, y)
  return layer.x + x, layer.y + y
end

-- The look an element shows until it is given one.
local DEFAULT_LOOK = style.look(settings.defaultAppearance(), nil)

-- Writes look's font for role, a text colour and the edge to a draw.edgedText label. dark draws Auto's dark text
-- with a light edge and no shadow; rgb overrides the look's text colour. Every write skips an unchanged value.
local function styleText(label, role, look, dark, rgb)
  local font = look.fonts[role]
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

-- Gives each element its look; returns whether any element's bounds changed.
function view.setLook(elements, look)
  local moved = false
  for _, element in pairs(elements) do
    if element.setLook(look) then
      moved = true
    end
  end
  return moved
end

local POWER_HEIGHT = 6
-- Game frame: the 2px window border the game draws round its action bars, from RS3_HUD_WINDOW_COMPACT_CORNER_TOP,
-- _TOP_TILE, _SIDE_TILE, _CORNER_BOTTOM and _BOTTOM_TILE. The right side is the left one flipped.
local GAME_EDGE = 2
local GAME_SPRITES = { cornerTop = 32990, side = 32991, cornerBottom = 32992, top = 32993, bottom = 32994 }

-- The eight sprites of a Game frame on layer, hidden. place(w, h) fits them to a w by h box.
local function gameFrame(layer)
  local parts = {}
  local function part(sprite, flipped, tiling)
    local c = ui.Sprite.new(layer)
    set(c, "sprite", sprite)
    set(c, "isTiling", tiling)
    set(c, "isFlippedHorizontally", flipped)
    set(c, "hidden", true)
    parts[#parts + 1] = c
    return c
  end
  local S = GAME_SPRITES
  local topLeft = part(S.cornerTop, false, false)
  local topRight = part(S.cornerTop, true, false)
  local bottomLeft = part(S.cornerBottom, false, false)
  local bottomRight = part(S.cornerBottom, true, false)
  local top = part(S.top, false, true)
  local bottom = part(S.bottom, false, true)
  local left = part(S.side, false, true)
  local right = part(S.side, true, true)
  local e = GAME_EDGE
  local frame = { parts = parts }

  function frame.place(w, h)
    for c, box in pairs({
      [topLeft] = { 0, 0, e, e },
      [topRight] = { w - e, 0, e, e },
      [bottomLeft] = { 0, h - e, e, e },
      [bottomRight] = { w - e, h - e, e, e },
      [top] = { e, 0, w - 2 * e, e },
      [bottom] = { e, h - e, w - 2 * e, e },
      [left] = { 0, e, e, h - 2 * e },
      [right] = { w - e, e, e, h - 2 * e },
    }) do
      pos(c, box[1], box[2])
      draw.size(c, box[3], box[4])
    end
  end

  return frame
end
-- The value label's width at the right of a unit frame, and the space the name leaves for it.
local VALUE_WIDTH = 95
local VALUE_SPACE = 110

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

-- A unit frame of look.frameWidth by look.frameHeight: a black border, the game's window border over it or none as
-- look.border picks, a health bar in the look's colour for
-- kind, "player" or "target", with the name on the left and the value on the right, and with power a 6px prayer
-- bar along the bottom. Both frames share one box height, whether or not a power bar shows in it. Auto text goes
-- dark over a bright fill once the fill reaches the label's right end. The player frame, built with power, also
-- hosts spender rows under it when look.spenders is "player": showSpenders(spenders) draws a src/frames resource
-- model's list there and returns whether the bounds, which span the frame and those rows, changed.
local function unitFrame(root, kind, power)
  local layer = ui.Layer.new(root)
  local rows = power and spenderRows(layer)
  local border = rect(layer, COLOURS.border, 0, 0, 0, 0)
  local track = rect(layer, COLOURS.healthTrack, 1, 1, 0, 0)
  local health = draw.bar(layer, style.FRAME_COLOURS[kind], COLOURS.healthTrack, 1, 1, 0, 0)
  local prayerTrack = power and rect(layer, COLOURS.healthTrack, 1, 0, 0, POWER_HEIGHT)
  local prayer = power and draw.bar(layer, COLOURS.prayer, COLOURS.healthTrack, 1, 0, 0, POWER_HEIGHT)
  local game = gameFrame(layer)
  local name = draw.edgedText(layer, FONTS.body, ui.AlignMode.TOPLEFT, 6, 1, 0, 0)
  local value = draw.edgedText(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, 0, 1, VALUE_WIDTH, 0)
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local frame = { layer = layer, bounds = bounds }
  -- The look shown, whether its fill wants Auto's dark text, the fill shown, and the fills at which each label
  -- sits wholly on it.
  local shown = nil
  local bright = false
  local fill = nil
  local nameAt = 1
  local valueAt = 1
  -- The spenders last given to showSpenders.
  local spenders = NO_SPENDERS

  local function resize(w, h)
    local inner = w - 2
    local healthHeight = power and h - POWER_HEIGHT - 3 or h - 2
    frame.width = w
    frame.height = h
    bounds.w = w
    bounds.h = h
    draw.size(layer, w, h + (rows and 2 + #frames.SPENDERS * SPENDER_STEP or 0))
    draw.size(border, w, h)
    draw.size(track, inner, healthHeight)
    health.setBox(1, 1, inner, healthHeight)
    draw.size(name, w - VALUE_SPACE, healthHeight)
    pos(value, w - VALUE_WIDTH - 6, 1)
    draw.size(value, VALUE_WIDTH, healthHeight)
    nameAt = (6 + w - VALUE_SPACE) / inner
    valueAt = (inner - 5) / inner
    game.place(w, h)
    if power then
      pos(prayerTrack, 1, healthHeight + 2)
      draw.width(prayerTrack, inner)
      prayer.setBox(1, healthHeight + 2, inner, POWER_HEIGHT)
    end
  end

  local function styleLabels()
    styleText(name, "body", shown, bright and fill ~= nil and fill >= nameAt)
    styleText(value, "body", shown, bright and fill ~= nil and fill >= valueAt)
  end

  function frame.update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then
      return
    end
    fill = model.fill
    health.setFill(fill)
    set(name, "content", model.name)
    set(value, "content", model.valueText)
    styleLabels()
    if power then
      set(prayerTrack, "hidden", model.prayerText == nil)
      prayer.setFill(model.prayerFill)
    end
  end

  function frame.showSpenders(list)
    if not rows then
      return false
    end
    spenders = list or NO_SPENDERS
    local shownList = shown.spenders == "player" and spenders or NO_SPENDERS
    rows.show(shownList, frame.width, frame.height + 2)
    local h = frame.height + #shownList * SPENDER_STEP
    if h == bounds.h then
      return false
    end
    bounds.h = h
    return true
  end

  -- Restyles the frame for a src/style look, returning at once for the look it shows. Returns whether its
  -- bounds changed.
  function frame.setLook(look)
    if look == shown then
      return false
    end
    shown = look
    local moved = frame.width ~= look.frameWidth or frame.height ~= look.frameHeight
    if moved then
      resize(look.frameWidth, look.frameHeight)
    end
    if frame.showSpenders(spenders) then
      moved = true
    end
    local rgb = look[kind]
    bright = look.auto and style.dark(rgb)
    health.setColour(rgb)
    health.setTexture(look.texture)
    if power then
      prayer.setTexture(look.texture)
    end
    set(border, "hidden", look.border == "none")
    draw.hideAll(game.parts, look.border ~= "game")
    styleLabels()
    return moved
  end

  frame.setLook(DEFAULT_LOOK)
  return frame
end

-- The player's frame: health with name and "13.1K | 78%", prayer below.
function view.playerFrame(root)
  return unitFrame(root, "player", true)
end

-- The target's frame: health with name and "6,800 | 58%", the same box height as the player frame.
function view.targetFrame(root)
  return unitFrame(root, "target", false)
end

-- Room the adrenaline bar's layer keeps above its bar for spender rows.
local BAR_Y = #frames.SPENDERS * SPENDER_STEP
-- Fill fraction at which the centred percent label sits entirely on the fill.
local PERCENT_ON_FILL = 0.56

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

-- A look.barWidth by look.barHeight adrenaline bar with its percent and a bar mark at each of its two markers,
-- and spender rows above or below it as look.spenders picks. Its bounds span the bar and the rows it shows.
-- update(model) takes a src/frames resource model and returns whether the bounds changed.
function view.resourceBar(root)
  local layer = ui.Layer.new(root)
  local rows = spenderRows(layer)
  local border = rect(layer, COLOURS.border, 0, BAR_Y, 0, 0)
  local track = rect(layer, COLOURS.track, 1, BAR_Y + 1, 0, 0)
  local fill = draw.bar(layer, COLOURS.adrenaline, COLOURS.track, 1, BAR_Y + 1, 0, 0)
  local markers = { barMark(layer, 0, BAR_Y + 1, 0), barMark(layer, 0, BAR_Y + 1, 0) }
  local percent = draw.edgedText(layer, FONTS.body, ui.AlignMode.CENTRE, 0, BAR_Y + 1, 0, 0)
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local bar = { layer = layer, bounds = bounds }
  -- The look shown, whether it wants dark text once the fill passes the label, the fill shown, the model shown,
  -- redrawn after a resize, and the bar's height.
  local shown = nil
  local bright = false
  local fillShown = 0
  local last = nil
  local barH = 0

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
    rows.show(spenders, w, above and BAR_Y - rowsH or BAR_Y + barH + 2)
    local y = above and BAR_Y - rowsH or BAR_Y
    local h = barH + rowsH
    if y == bounds.y and h == bounds.h then
      return false
    end
    bounds.y = y
    bounds.h = h
    bar.height = h
    return true
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
    bar.width = w
    draw.size(layer, w, 2 * BAR_Y + h + 2)
    draw.size(border, w, h)
    draw.size(track, w - 2, h - 2)
    fill.setBox(1, BAR_Y + 1, w - 2, h - 2)
    for _, mark in ipairs(markers) do
      draw.size(mark, 1, h - 2)
    end
    draw.size(percent, w, h - 2)
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

  bar.update = update
  bar.setLook(DEFAULT_LOOK)
  return bar
end

local TILE_GAP = 2
-- Tiles at least this big show their seconds in the larger font.
local LARGE_TILE = 40
local MAX_TILES = 10
local COOLING_DIM = 0.62
-- A tile whose ability can't be cast takes the native action bar's look: a dark icon tint and a faded grey
-- keybind.
local UNTINTED = 0xffffff
local BLOCKED_ICON = 0x333333
local BLOCKED_TEXT = 0xa5a5a5
local BLOCKED_ALPHA = 0.6
-- A tile bar's height, and while any of it is gold.
local TILE_BAR = 3
local LIT_TILE_BAR = 5
local COUNT_HEIGHT = 14

-- Builds one cooldown tile's components. placeTile positions and sizes them.
local function tile(layer)
  local parts = {
    edge = rect(layer, COLOURS.border, 0, 0, 0, 0),
    background = rect(layer, COLOURS.tile, 0, 0, 0, 0),
    icon = ui.Sprite.new(layer),
    initials = draw.edgedText(layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, 0, 12),
    dim = rect(layer, COLOURS.border, 0, 0, 0, 0),
    track = rect(layer, COLOURS.border, 0, 0, 0, 0),
    fill = rect(layer, COLOURS.highlight, 0, 0, 0, 0),
    gold = rect(layer, GOLD, 0, 0, 0, 0),
    notchEdge = rect(layer, COLOURS.border, 0, 0, 0, 0),
    notch = rect(layer, COLOURS.highlight, 0, 0, 0, 0),
    count = draw.edgedText(layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, 0, COUNT_HEIGHT),
    keybind = draw.edgedText(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 21, 12),
    seconds = draw.edgedText(layer, FONTS.seconds, ui.AlignMode.CENTRE, 0, 0, 0, 0),
  }
  parts.bar = { parts.track, parts.fill, parts.gold, parts.notchEdge, parts.notch }
  parts.all = {
    parts.edge,
    parts.background,
    parts.icon,
    parts.initials,
    parts.dim,
    parts.track,
    parts.fill,
    parts.gold,
    parts.notchEdge,
    parts.notch,
    parts.count,
    parts.keybind,
    parts.seconds,
  }
  parts.inner = { parts.background, parts.icon, parts.dim }
  draw.hideAll(parts.bar, true)
  set(parts.background, "alpha", TILE_ALPHA)
  set(parts.dim, "alpha", COOLING_DIM)
  return parts
end

-- Moves and sizes a tile's parts for a size pixel tile at x, y.
local function placeTile(parts, x, y, size)
  parts.x = x
  parts.y = y
  parts.size = size
  pos(parts.edge, x, y)
  draw.size(parts.edge, size, size)
  for _, inner in ipairs(parts.inner) do
    pos(inner, x + 1, y + 1)
    draw.size(inner, size - 2, size - 2)
  end
  pos(parts.initials, x + 4, y + size - 15)
  draw.size(parts.initials, size - 8, 12)
  pos(parts.keybind, x + size - 24, y + 2)
  pos(parts.seconds, x, y)
  draw.size(parts.seconds, size, size)
end

-- Shows a cooling tile's whole seconds left, since seconds after the server tick its model was read at, rounded
-- up so it reads 1 until the tick that readies it. Returns whether the label changed.
local function showSeconds(parts, since)
  local shown = math.max(1, math.ceil(parts.remaining - since - 1e-6))
  if shown == parts.shown then
    return false
  end
  parts.shown = shown
  set(parts.seconds, "content", tostring(shown))
  return true
end

-- Width of a recharge bar's white fill, since seconds after the server tick its model was read at.
local function rechargeWidth(parts, since)
  local recharge = parts.recharge
  local done = 1 - (recharge.remaining - since) / recharge.length
  return math.floor((parts.size - 2) * math.max(0, math.min(1, done)))
end

-- Draws a tile's bar along its bottom edge: a spender's stacks in its row colour with whole casts gold and a
-- notch at one cast, or a charge's recharge in white. Returns the bar's height, 0 with none.
local function showBar(parts, model, since, size)
  local stacks = model.stacks
  parts.recharge = model.recharge
  if stacks == nil and model.recharge == nil then
    draw.hideAll(parts.bar, true)
    return 0
  end
  local w = size - 2
  local h = (stacks ~= nil and stacks.gold > 0) and LIT_TILE_BAR or TILE_BAR
  local x = parts.x + 1
  local top = parts.y + size - 1 - h
  set(parts.track, "hidden", false)
  set(parts.fill, "hidden", false)
  pos(parts.track, x, top)
  draw.size(parts.track, w, h)
  pos(parts.fill, x, top)
  local notch = stacks and stacks.notch
  set(parts.gold, "hidden", stacks == nil or stacks.gold == 0)
  set(parts.notchEdge, "hidden", notch == nil)
  set(parts.notch, "hidden", notch == nil)
  if stacks == nil then
    set(parts.fill, "rgb", COLOURS.highlight)
    draw.size(parts.fill, rechargeWidth(parts, since), h)
    return h
  end
  set(parts.fill, "rgb", SPENDER_COLOURS[stacks.key])
  draw.size(parts.fill, w * stacks.count // stacks.max, h)
  if stacks.gold > 0 then
    pos(parts.gold, x, top)
    draw.size(parts.gold, w * stacks.gold // stacks.max, h)
  end
  if notch ~= nil then
    local notchX = x + w * notch // stacks.max - 1
    pos(parts.notchEdge, notchX - 1, top)
    draw.size(parts.notchEdge, 4, h)
    pos(parts.notch, notchX, top)
    draw.size(parts.notch, 2, h)
  end
  return h
end

-- Shows a src/cooldowns tile model on a size pixel tile's parts in a src/style look, since seconds after the
-- server tick it was read at. A count sits at bottom left, raised over the bar on a tile that can show one.
local function showTile(parts, model, since, look, size)
  set(parts.edge, "hidden", false)
  set(parts.background, "hidden", false)
  draw.iconOrInitials(parts.icon, parts.initials, model)
  set(parts.dim, "hidden", model.ready)
  set(parts.keybind, "hidden", model.keybind == nil)
  set(parts.keybind, "content", model.keybind or "")
  set(parts.seconds, "hidden", model.ready)
  parts.remaining = model.remaining
  if model.remaining ~= nil then
    showSeconds(parts, since)
  end
  local barH = showBar(parts, model, since, size)
  set(parts.count, "hidden", model.count == nil)
  if model.count ~= nil then
    set(parts.count, "content", model.count)
    local lift = 0
    if model.charges ~= nil or model.stacks ~= nil then
      lift = math.max(barH, TILE_BAR) + 1
    end
    pos(parts.count, parts.x + 4, parts.y + size - 3 - lift - COUNT_HEIGHT)
    draw.size(parts.count, size - 8, COUNT_HEIGHT)
    styleText(parts.count, size >= LARGE_TILE and "body" or "small", look, false)
  end
  local usable = model.usable ~= false
  set(parts.icon, "rgb", usable and UNTINTED or BLOCKED_ICON)
  local labelColour = COLOURS.dimText
  if not usable then
    labelColour = BLOCKED_TEXT
  elseif model.ready then
    labelColour = look.text
  end
  local labelAlpha = usable and 1 or BLOCKED_ALPHA
  styleText(parts.initials, "small", look, false, labelColour)
  styleText(parts.keybind, "small", look, false, labelColour)
  styleText(parts.seconds, size >= LARGE_TILE and "seconds" or "smallSeconds", look, false)
  set(parts.initials, "alpha", labelAlpha)
  set(parts.keybind, "alpha", labelAlpha)
end

-- A cooldown group of up to settings.MAX_GROUP_KEYS ability tiles laid out by layout.grid. configure takes
-- { size, perRow, grow }, returns whether it changed, and redraws on the next update. update takes
-- src/cooldowns tiles and the seconds since the server tick they were read at, and returns whether bounds
-- changed; bounds spans the shown tiles, and an empty group's sides meet at its axis. step(since) counts the
-- cooling tiles down and moves recharge bars from that tick, and returns at once when none moves. setInUse(false)
-- hides a custom group that is not in use and collapses its bounds. Tiles are built as the group first needs
-- them, inside its layer, and never destroyed. Ready tiles are bright with their keybind; cooling tiles are
-- dimmed with whole seconds left; tiles whose ability can't be cast are tinted dark. Hovering a tile shows
-- its tooltip. setLook(look) restyles the tiles' text and returns false, as it moves no bounds.
function view.cooldownGroup(root, tooltip)
  local max = settings.MAX_GROUP_KEYS
  local layer = ui.Layer.new(root)
  local tiles = {}
  local display = nil
  local inUse = true
  local current = {}
  -- Shown tiles, and how many of them are cooling or recharging.
  local count = 0
  local moving = 0
  -- The look shown and the seconds since the server tick of the models shown.
  local look = DEFAULT_LOOK
  local shownSince = 0
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local group = { layer = layer, bounds = bounds, inUse = true }

  local function showTooltip(i)
    local model = current[i]
    if model == nil then
      tooltip.hide()
      return
    end
    local x, y = screenPos(layer, tiles[i].x, tiles[i].y)
    tooltip.show({
      title = model.name,
      left = model.cooldown and ("Cooldown " .. model.cooldown .. "s") or nil,
      right = model.keybind and ("Key " .. model.keybind) or nil,
      line = model.ready and "Ready" or ("Ready in " .. tiles[i].shown .. "s"),
    }, x, y, display.size)
  end

  local hover = tooltip.hover({}, showTooltip)

  function group.configure(d)
    if display ~= nil and display.size == d.size and display.perRow == d.perRow and display.grow == d.grow then
      return false
    end
    display = { size = d.size, perRow = d.perRow, grow = d.grow }
    local extent = layout.grid(max, display.size, TILE_GAP, display.perRow, display.grow, max)
    draw.size(layer, extent.w, extent.h)
    return true
  end

  function group.setInUse(on)
    inUse = on
    group.inUse = on
    set(layer, "hidden", not on)
  end

  function group.update(models, since)
    if not inUse then
      current = {}
      count = 0
      moving = 0
      for _, parts in ipairs(tiles) do
        draw.hideAll(parts.all, true)
      end
      local moved = bounds.w ~= 0 or bounds.h ~= 0
      bounds.w = 0
      bounds.h = 0
      if hover.index ~= nil then
        hover.index = nil
        tooltip.hide()
      end
      return moved
    end
    current = models
    shownSince = since or 0
    count = math.min(#models, max)
    moving = 0
    while #tiles < count do
      tiles[#tiles + 1] = tile(layer)
      hover.add(tiles[#tiles])
    end
    local g = layout.grid(count, display.size, TILE_GAP, display.perRow, display.grow, max)
    local shown = g.bounds
    local moved = bounds.x ~= shown.x or bounds.y ~= shown.y or bounds.w ~= shown.w or bounds.h ~= shown.h
    bounds.x = shown.x
    bounds.y = shown.y
    bounds.w = shown.w
    bounds.h = shown.h
    for i, parts in ipairs(tiles) do
      if i > count then
        draw.hideAll(parts.all, true)
      else
        placeTile(parts, g.tiles[i].x, g.tiles[i].y, display.size)
        showTile(parts, models[i], shownSince, look, display.size)
        if models[i].remaining ~= nil or models[i].recharge ~= nil then
          moving = moving + 1
        end
      end
    end
    if hover.index ~= nil then
      showTooltip(hover.index)
    end
    return moved
  end

  function group.setLook(newLook)
    if newLook == look then
      return false
    end
    look = newLook
    for i = 1, count do
      showTile(tiles[i], current[i], shownSince, look, display.size)
    end
    return false
  end

  function group.step(since)
    if moving == 0 then
      return
    end
    for i = 1, count do
      local parts = tiles[i]
      if parts.remaining ~= nil and showSeconds(parts, since) and hover.index == i then
        showTooltip(i)
      end
      if parts.recharge ~= nil then
        draw.width(parts.fill, rechargeWidth(parts, since))
      end
    end
  end

  return group
end

-- Hit marks built for the cast bar, more than any channel deals.
local MAX_HITS = 12
local NO_HITS = {}

-- Ticks left as the game's cast bar writes them: "4.2s", "3s".
local function castSeconds(ticks)
  local tenths = ticks * 6
  if tenths % 10 == 0 then
    return (tenths // 10) .. "s"
  end
  return string.format("%d.%ds", tenths // 10, tenths % 10)
end

-- A cancelled channel shows "Cancelled" for CANCEL_HOLD seconds, then the bar fades out over CANCEL_FADE seconds
-- in CANCEL_STEPS alpha steps, from 0.8 down to 0.
local CANCEL_HOLD = 0.6
local CANCEL_FADE = 0.4
local CANCEL_STEPS = 5

-- Fill colour by the channelled ability's src/cooldowns combat style, for Ability style. A channel with none keeps
-- the RuneUI fill.
local CAST_COLOURS = style.STYLE_COLOURS
-- The time label's width and its gap from the bar's right end.
local CAST_TIME_W = 72
local CAST_TIME_GAP = 6

-- The spark at the fill's edge: a 2px white core with a glow of SPARK_GLOW 1px white strips behind it, their alpha
-- rising evenly to GLOW_PEAK by the core, times the glow level. The level sits at GLOW_BASE and flashes on each
-- server tick, stepping down through FLASH_LEVELS over FLASH seconds, as the game's spark glow does.
local SPARK_GLOW = 12
local SPARK_CORE = 2
local GLOW_PEAK = 0.9
local GLOW_BASE = 0.5
local FLASH = 0.2
local FLASH_LEVELS = { 1, 0.8, 0.65 }

-- look.castWidth by look.castHeight: the channelled ability's icon, its name, and its time left as "1.2s" over a
-- fill of the time spent in look.castColour, or its combat style's colour for Ability style, with a spark at the
-- fill's edge and a bar mark at each hit that lands inside the bar rather than at its ends. A cancelled channel
-- shows "Cancelled" in place of its time, hides its spark and marks, and fades out, whatever updates arrive
-- meanwhile.
-- update takes a src/channel model, or nil to hide the bar while keeping its bounds, so anchored elements stay
-- put. The time steps with the model's ticks left, as the game's label does, and each new count sets the fill to
-- that tick. step(seconds) moves the fill on smoothly up to the next tick, hides the bar once its last tick runs
-- out, and does nothing between channels.
function view.castBar(root)
  local layer = ui.Layer.new(root)
  local border = rect(layer, COLOURS.border, 0, 0, 0, 0)
  local track = rect(layer, COLOURS.track, 1, 1, 0, 0)
  -- The bar's left edge and width, right of the icon, set by resize.
  local barX = 0
  local barWidth = 0
  local fill = draw.bar(layer, style.CAST_COLOUR, COLOURS.track, 0, 1, 0, 0)
  local marks = {}
  for i = 1, MAX_HITS do
    marks[i] = barMark(layer, 0, 1, 0)
    set(marks[i], "hidden", true)
  end
  local sparkWidth = SPARK_GLOW + SPARK_CORE
  local spark = ui.Layer.new(layer)
  local glow = {}
  for i = 1, SPARK_GLOW do
    glow[i] = rect(spark, COLOURS.highlight, i - 1, 0, 1, 0)
  end
  local core = rect(spark, COLOURS.highlight, sparkWidth - SPARK_CORE, 0, SPARK_CORE, 0)
  -- The glow level shown, and seconds left in a flash.
  local glowLevel = nil
  local flashLeft = 0
  local iconBack = rect(layer, COLOURS.tile, 1, 1, 0, 0)
  local icon = ui.Sprite.new(layer)
  icon:SetPos(1, 1)
  local name = draw.edgedText(layer, FONTS.body, ui.AlignMode.TOPLEFT, 0, 1, 0, 0)
  local time = draw.edgedText(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, 0, 1, CAST_TIME_W, 0)
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local bar = { layer = layer, bounds = bounds }
  -- The look shown.
  local shown = nil
  -- Every component the cancel fade dims. Marks hide on a cancel, so they are left out.
  local faded = { border, track, iconBack, icon, name, time }
  for _, part in ipairs(fill.parts) do
    faded[#faded + 1] = part
  end
  -- Seconds left showing a cancel, or nil.
  local cancelLeft = nil
  set(layer, "hidden", true)
  -- The shown channel's model and seconds left, nil once it ends, the start of the latest channel shown and the
  -- ticks left its label shows.
  local current = nil
  local left = nil
  local shownStart = nil
  local shownTicks = nil
  -- Seconds into the channel of each shown mark, the start and hit count they were placed for, and how many the
  -- fill has passed.
  local markAt = {}
  local placedFor = nil
  local placedHits = nil
  local placed = 0
  local passedShown = nil

  local function placeMarks(model)
    placedFor = model.start
    placedHits = model.hits and #model.hits
    placed = 0
    passedShown = nil
    for _, at in ipairs(model.hits or NO_HITS) do
      if at > 0 and at < model.duration and placed < MAX_HITS then
        placed = placed + 1
        markAt[placed] = at
        pos(marks[placed], barX + math.floor(barWidth * at / model.duration + 0.5), 1)
      end
    end
    for i, mark in ipairs(marks) do
      set(mark, "hidden", i > placed)
    end
  end

  -- Shades the marks for the seconds spent, only when the fill passes one.
  local function shadeMarks(spent)
    local passed = 0
    for i = 1, placed do
      if markAt[i] <= spent then
        passed = i
      end
    end
    if passed == passedShown then
      return
    end
    passedShown = passed
    for i = 1, placed do
      shadeMark(marks[i], i <= passed)
    end
  end

  local function setGlow(level)
    if level == glowLevel then
      return
    end
    glowLevel = level
    for i, strip in ipairs(glow) do
      set(strip, "alpha", GLOW_PEAK * level * i / SPARK_GLOW)
    end
  end

  -- Puts the spark's core at edge, hiding any part of it left of the fill.
  local function placeSpark(edge)
    local x = edge - sparkWidth
    pos(spark, x, 1)
    for i, strip in ipairs(glow) do
      set(strip, "hidden", x + i - 1 < barX)
    end
    set(core, "hidden", edge - SPARK_CORE < barX)
  end

  -- Fills the bar to the share of the channel spent, moves the spark to its edge and shades the marks it passed.
  local function show(remaining)
    local spent = 1 - remaining / current.duration
    fill.setFill(spent)
    placeSpark(barX + math.floor(barWidth * spent))
    shadeMarks(current.duration - remaining)
  end

  local function setAlpha(alpha)
    for _, part in ipairs(faded) do
      set(part, "alpha", alpha)
    end
  end

  -- Hides the bar and ends its channel.
  local function finish()
    current = nil
    left = nil
    cancelLeft = nil
    set(layer, "hidden", true)
    setAlpha(1)
  end

  local function update(model)
    local cancel = model ~= nil and model.cancelled
    if cancelLeft ~= nil and (model == nil or cancel or model.start == shownStart) then
      return
    end
    if cancel then
      if current ~= nil and model.start == shownStart then
        cancelLeft = CANCEL_HOLD + CANCEL_FADE
        set(time, "content", "Cancelled")
        draw.hideAll(marks, true)
        set(spark, "hidden", true)
      else
        finish()
      end
      return
    end
    if cancelLeft ~= nil then
      finish()
    end
    if model ~= nil and model.start ~= shownStart then
      shownStart = model.start
      left = model.duration
      shownTicks = nil
    end
    if model ~= nil and left ~= nil and model.ticksLeft ~= shownTicks then
      shownTicks = model.ticksLeft
      left = model.ticksLeft * 6 / 10
      flashLeft = FLASH
      set(time, "content", castSeconds(shownTicks))
      setGlow(FLASH_LEVELS[1])
    end
    current = left ~= nil and model or nil
    set(layer, "hidden", current == nil)
    if current == nil then
      left = nil
      return
    end
    set(iconBack, "hidden", model.icon == nil)
    set(icon, "hidden", model.icon == nil)
    if model.icon ~= nil then
      set(icon, "sprite", model.icon)
    end
    set(name, "content", model.name or "")
    fill.setColour(shown.castColour or CAST_COLOURS[model.style] or style.CAST_COLOUR)
    set(spark, "hidden", false)
    if model.start ~= placedFor or (model.hits and #model.hits) ~= placedHits then
      placeMarks(model)
    end
    show(left)
  end

  local function step(seconds)
    if current == nil then
      return
    end
    if cancelLeft ~= nil then
      cancelLeft = cancelLeft - seconds
      if cancelLeft <= 0 then
        finish()
      elseif cancelLeft < CANCEL_FADE then
        setAlpha((math.ceil(cancelLeft / CANCEL_FADE * CANCEL_STEPS) - 1) / CANCEL_STEPS)
      end
      return
    end
    if flashLeft > 0 then
      flashLeft = flashLeft - seconds
      local steps = #FLASH_LEVELS
      setGlow(flashLeft > 0 and FLASH_LEVELS[steps + 1 - math.ceil(flashLeft / FLASH * steps)] or GLOW_BASE)
    end
    left = math.max(left - seconds, (shownTicks - 1) * 6 / 10)
    if left > 0 then
      show(left)
    else
      finish()
    end
  end

  -- Sizes every part for a w by h bar, the icon a square filling its height, and redraws a running channel.
  local function resize(w, h)
    local inner = h - 2
    bar.width = w
    bar.height = h
    bounds.w = w
    bounds.h = h
    barX = inner + 2
    barWidth = w - inner - 3
    draw.size(layer, w, h)
    draw.size(border, w, h)
    draw.size(track, w - 2, inner)
    fill.setBox(barX, 1, barWidth, inner)
    for _, mark in ipairs(marks) do
      draw.size(mark, 1, inner)
    end
    draw.size(spark, sparkWidth, inner)
    for _, strip in ipairs(glow) do
      draw.size(strip, 1, inner)
    end
    draw.size(core, SPARK_CORE, inner)
    draw.size(iconBack, inner, inner)
    draw.size(icon, inner, inner)
    pos(name, barX + 5, 1)
    draw.size(name, math.max(0, w - barX - 5 - CAST_TIME_W), inner)
    pos(time, w - CAST_TIME_W - CAST_TIME_GAP, 1)
    draw.size(time, CAST_TIME_W, inner)
    if current ~= nil and cancelLeft == nil then
      placeMarks(current)
      show(left)
    end
  end

  -- Restyles the bar for a src/style look, returning at once for the look it shows. Returns whether its bounds
  -- changed. Its fills are all dark, so Auto keeps the text light.
  function bar.setLook(look)
    if look == shown then
      return false
    end
    shown = look
    local moved = bounds.w ~= look.castWidth or bounds.h ~= look.castHeight
    if moved then
      resize(look.castWidth, look.castHeight)
    end
    fill.setTexture(look.texture)
    if current ~= nil then
      fill.setColour(look.castColour or CAST_COLOURS[current.style] or style.CAST_COLOUR)
    end
    styleText(name, "cast", look, false)
    styleText(time, "cast", look, false)
    return moved
  end

  bar.update = update
  bar.step = step
  bar.setLook(DEFAULT_LOOK)
  return bar
end

-- Aura rows by HUD element: tile size, which end the icons gather at, and whether they are debuffs, which get
-- an orange edge. timeRole, a src/style text role, and timeHeight size the time text along a tile's bottom.
view.AURA_STYLES = {
  targetDebuffs = { size = 26, align = "right", debuff = true, timeRole = "small", timeHeight = 11 },
  playerDebuffs = { size = 26, align = "left", debuff = true, timeRole = "small", timeHeight = 11 },
  upkeepBuffs = { size = 26, align = "left", timeRole = "small", timeHeight = 11 },
  combatBuffs = { size = 36, align = "centre", timeRole = "body", timeHeight = 13 },
}
local AURA_GAP = 2
-- Room around the tiles for the highlight, which draws up to 3px outside a tile.
local AURA_MARGIN = 3
-- With bars on, each tile has a 4px bar 1px below it.
local AURA_BAR = 4
local AURA_BAR_SPACE = 5
-- Bar stripes in the refresh window: white and black runs across the bar.
local STRIPE = 3
local STRIPE_GAP = 2
-- A missing Keep up buff's icon alpha.
local MISSING_ALPHA = 0.35

-- Builds one aura tile's components as a draw.group. The bar's cover moves on its own, so it sits outside
-- the group.
local function auraTile(layer, aura)
  local size = aura.size
  local inner = size - 2
  local group = draw.group()
  local white = COLOURS.highlight
  local timeY = size - aura.timeHeight - 3
  local parts = {
    group = group,
    ring = {
      group.add(rect(layer, white, 0, 0, size + 4, 2), -2, -2),
      group.add(rect(layer, white, 0, 0, size + 4, 2), -2, size),
      group.add(rect(layer, white, 0, 0, 2, size), -2, 0),
      group.add(rect(layer, white, 0, 0, 2, size), size, 0),
    },
    edge = group.add(rect(layer, aura.debuff and COLOURS.debuff or COLOURS.border, 0, 0, size, size), 0, 0),
    icon = group.add(ui.Sprite.new(layer), 1, 1),
    time = group.add(
      draw.edgedText(layer, FONTS[aura.timeRole], ui.AlignMode.CENTRE, 0, 0, size, aura.timeHeight + 2),
      0,
      timeY
    ),
    stacks = group.add(draw.edgedText(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 21, 12), size - 23, 1),
    track = group.add(rect(layer, COLOURS.border, 0, 0, size, AURA_BAR), 0, size + 1),
    fill = group.add(
      rect(layer, aura.debuff and COLOURS.debuff or COLOURS.dimText, 0, 0, inner, AURA_BAR - 2),
      1,
      size + 2
    ),
    stripes = group.add(ui.Canvas.new(layer), 1, size + 2),
    cover = rect(layer, COLOURS.border, 0, 0, inner, AURA_BAR - 2),
    dashed = group.add(ui.Canvas.new(layer), -3, -3),
  }
  parts.icon:SetSize(inner, inner)
  parts.stripes:SetSize(inner, AURA_BAR - 2)
  for x = 0, inner - 1, STRIPE + STRIPE_GAP do
    parts.stripes:AddRectangle(x, 0, math.min(STRIPE, inner - x), AURA_BAR - 2, draw.opaque(white))
  end
  parts.dashed:SetSize(size + 6, size + 6)
  draw.dashedBox(parts.dashed, size + 6, size + 6, 2, draw.opaque(white))
  return parts
end

-- Shows a src/auras model on parts at x, y. bars draws the bar and the bars-mode highlight. A missing Keep
-- up buff draws dim inside the dashed outline, with no time.
local function showAura(parts, model, x, y, size, bars)
  parts.group.place(x, y)
  local timed = model.left ~= nil
  local ring = model.highlight and not bars
  local dashed = model.highlight and bars or model.missing == true
  draw.hideAll(parts.ring, not ring)
  set(parts.dashed, "hidden", not dashed)
  set(parts.edge, "hidden", false)
  set(parts.icon, "hidden", false)
  draw.icon(parts.icon, model.sprite)
  set(parts.icon, "alpha", model.missing and MISSING_ALPHA or 1)
  set(parts.time, "hidden", model.text == nil)
  set(parts.time, "content", model.text or "")
  set(parts.stacks, "hidden", model.stacks == nil)
  set(parts.stacks, "content", model.stacks or "")

  local barShown = bars and timed
  local inner = size - 2
  local filled = barShown and math.floor(inner * model.fill) or 0
  set(parts.track, "hidden", not barShown)
  set(parts.fill, "hidden", not barShown or dashed or filled == 0)
  set(parts.stripes, "hidden", not barShown or not dashed)
  set(parts.cover, "hidden", not barShown or not dashed or filled == inner)
  if barShown then
    draw.width(parts.fill, math.max(filled, 1))
    pos(parts.cover, x + 1 + filled, y + size + 2)
    draw.width(parts.cover, inner - filled)
  end
end

-- A row of up to 10 aura icons gathered at style.align's end. Each icon shows its time left and stacks, and
-- in its refresh window a highlight: a white ring, or with bars on a dashed
-- outline and a striped bar. update takes src/auras models and whether bars
-- are on, and returns whether bounds changed. bounds spans the shown tiles, at least one, so an empty row
-- can still be dragged in edit mode. Hovering an icon shows the name and info from info(sprite), which
-- returns { name, info } or nil.
function view.auraRow(root, aura, tooltip, info)
  local size = aura.size
  local step = size + AURA_GAP
  local width = 2 * AURA_MARGIN + MAX_TILES * step - AURA_GAP
  local height = 2 * AURA_MARGIN + size + AURA_BAR_SPACE
  local layer = ui.Layer.new(root)
  layer:SetSize(width, height)
  local tiles = {}
  for i = 1, MAX_TILES do
    tiles[i] = auraTile(layer, aura)
  end

  -- x of the first of count tiles.
  local function left(count)
    local spare = (MAX_TILES - count) * step
    if aura.align == "right" then
      return AURA_MARGIN + spare
    end
    if aura.align == "centre" then
      return AURA_MARGIN + spare // 2
    end
    return AURA_MARGIN
  end

  local current = {}
  local bounds = { x = left(1), y = AURA_MARGIN, w = size, h = size }

  local function showTooltip(i)
    local model = current[i]
    if model == nil then
      tooltip.hide()
      return
    end
    local found = info(model.sprite)
    local x, y = screenPos(layer, tiles[i].group.x, AURA_MARGIN)
    local title = aura.debuff and "Unknown debuff" or "Unknown buff"
    local detail = nil
    if found then
      title = found.name or title
      detail = found.info
    elseif found == nil then
      detail = "Looking up name"
    end
    tooltip.show({ title = title, left = detail }, x, y, size)
  end

  local hover = tooltip.hover(tiles, showTooltip)

  local function update(models, bars)
    current = models
    local count = math.min(#models, MAX_TILES)
    local shown = math.max(count, 1)
    local x = left(shown)
    local w = shown * step - AURA_GAP
    local h = size + (bars and AURA_BAR_SPACE or 0)
    local moved = bounds.x ~= x or bounds.w ~= w or bounds.h ~= h
    bounds.x = x
    bounds.w = w
    bounds.h = h
    local first = left(count)
    for i, parts in ipairs(tiles) do
      local model = models[i]
      if i > count then
        parts.group.set("hidden", true)
        set(parts.cover, "hidden", true)
      else
        showAura(parts, model, first + (i - 1) * step, AURA_MARGIN, size, bars)
      end
    end
    if hover.index ~= nil then
      showTooltip(hover.index)
    end
    return moved
  end

  local shown = nil
  local function setLook(look)
    if look == shown then
      return false
    end
    shown = look
    for _, parts in ipairs(tiles) do
      styleText(parts.time, aura.timeRole, look, false)
      styleText(parts.stacks, "small", look, false)
    end
    return false
  end

  setLook(DEFAULT_LOOK)
  return { layer = layer, update = update, setLook = setLook, width = width, height = height, bounds = bounds }
end

return view
