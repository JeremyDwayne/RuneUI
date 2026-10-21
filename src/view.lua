-- Draws RuneUI elements on the plugin layer from display models, in a flat dark style.
-- Each constructor returns { layer, update(model), width, height, bounds }, plus setTexture(texture) for
-- elements with bars. bounds is the shown { x, y, w, h } inside the layer. place() positions a layer on the
-- game window and arrange() places every element from saved positions and anchors.
local view = {}

local draw = require("src/draw")
local frames = require("src/frames")
local layout = require("src/layout")
local settings = require("src/settings")
local set, pos, rect, text = draw.set, draw.pos, draw.rect, draw.text
local FONTS, COLOURS = draw.FONTS, draw.COLOURS

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
  for name, element in pairs(elements) do bounds[name] = element.bounds end
  local resolved = layout.resolve(positions, anchors, bounds)
  for name, element in pairs(elements) do view.place(element.layer, resolved[name]) end
  return resolved
end

local TOOLTIP_WIDTH, TOOLTIP_PAD, TOOLTIP_GAP = 200, 8, 6
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
    local lines = content.line == nil and 0 or (#content.line > TOOLTIP_LINE_CHARS and 2 or 1)
    local h = 46 + lines * 14 - (lines == 0 and 6 or 0)
    if h ~= height then
      height = h
      layer:SetSize(TOOLTIP_WIDTH, h)
      edge:SetHeight(h)
      inner:SetHeight(h - 2)
      panel:SetHeight(h - 4)
    end
    local top = y - h - TOOLTIP_GAP
    if top < 0 then top = y + size + TOOLTIP_GAP end
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
      for _, side in ipairs(highlight) do side:MoveToFront() end
    end
  end

  function tooltip.hide()
    setHidden(true)
  end

  function tooltip.destroy()
    layer:Destroy()
    for _, side in ipairs(highlight) do side:Destroy() end
  end

  -- Entering item i's edge calls show(i) and leaving the hovered edge hides the tooltip. Returns a table
  -- whose index is the hovered item's, or nil, so an update can redraw the tooltip it shows, and whose
  -- add(item) wires one more item as the next index.
  function tooltip.hover(items, show)
    local hover, count = {}, 0

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

    for _, item in ipairs(items) do hover.add(item) end
    return hover
  end

  return tooltip
end

-- Screen position of a point inside a layer parented to the plugin layer.
local function screenPos(layer, x, y)
  return layer.x + x, layer.y + y
end

local FRAME_WIDTH = 250
local HEALTH_HEIGHT = 46
local POWER_HEIGHT = 6
-- Both unit frames share one box height, whether or not a power bar shows in it.
local FRAME_HEIGHT = HEALTH_HEIGHT + POWER_HEIGHT + 3

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
  local height = FRAME_HEIGHT
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

  return {
    layer = layer, update = update, setTexture = setTexture, width = FRAME_WIDTH, height = height,
    bounds = { x = 0, y = 0, w = FRAME_WIDTH, h = height },
  }
end

-- 250x55: a 53px health bar with name and "6,800 | 58%", the same box height as the player frame.
function view.targetFrame(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  rect(layer, COLOURS.border, 0, 0, FRAME_WIDTH, FRAME_HEIGHT)
  local updateHealth, health = unitBar(layer, COLOURS.target, 1, FRAME_HEIGHT - 2)

  local function update(model)
    set(layer, "hidden", model.hidden)
    if not model.hidden then updateHealth(model) end
  end

  return {
    layer = layer, update = update, setTexture = health.setTexture,
    width = FRAME_WIDTH, height = FRAME_HEIGHT,
    bounds = { x = 0, y = 0, w = FRAME_WIDTH, h = FRAME_HEIGHT },
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

  return {
    layer = layer, update = update, setTexture = fill.setTexture, width = BAR_WIDTH, height = height,
    bounds = { x = 0, y = 0, w = BAR_WIDTH, h = height },
  }
end

local TILE_GAP = 2
-- Tiles at least this big show their seconds in the larger font.
local LARGE_TILE = 40
local MAX_TILES = 10
local COOLING_DIM = 0.62
-- A tile whose ability can't be cast takes the native action bar's look: a dark icon tint and a faded grey
-- keybind.
local UNTINTED, BLOCKED_ICON, BLOCKED_TEXT, BLOCKED_ALPHA = 0xffffff, 0x333333, 0xa5a5a5, 0.6

-- Builds one cooldown tile's components. placeTile positions and sizes them.
local function tile(layer)
  local parts = {
    edge = rect(layer, COLOURS.border, 0, 0, 0, 0),
    background = rect(layer, COLOURS.tile, 0, 0, 0, 0),
    icon = ui.Sprite.new(layer),
    initials = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, 0, 12),
    dim = rect(layer, COLOURS.border, 0, 0, 0, 0),
    keybind = text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 21, 12),
    seconds = text(layer, FONTS.seconds, ui.AlignMode.CENTRE, 0, 0, 0, 0),
  }
  parts.all = { parts.edge, parts.background, parts.icon, parts.initials, parts.dim, parts.keybind, parts.seconds }
  set(parts.background, "alpha", TILE_ALPHA)
  set(parts.dim, "alpha", COOLING_DIM)
  return parts
end

-- Moves and sizes a tile's parts for a size pixel tile at x, y.
local function placeTile(parts, x, y, size)
  parts.x, parts.y = x, y
  pos(parts.edge, x, y)
  draw.size(parts.edge, size, size)
  for _, inner in ipairs({ parts.background, parts.icon, parts.dim }) do
    pos(inner, x + 1, y + 1)
    draw.size(inner, size - 2, size - 2)
  end
  pos(parts.initials, x + 4, y + size - 15)
  draw.size(parts.initials, size - 8, 12)
  pos(parts.keybind, x + size - 24, y + 2)
  pos(parts.seconds, x, y)
  draw.size(parts.seconds, size, size)
  set(parts.seconds, "font", size >= LARGE_TILE and FONTS.seconds or FONTS.smallSeconds)
end

-- Shows a src/cooldowns tile model on parts.
local function showTile(parts, model)
  set(parts.edge, "hidden", false)
  set(parts.background, "hidden", false)
  draw.iconOrInitials(parts.icon, parts.initials, model)
  set(parts.dim, "hidden", model.ready)
  set(parts.keybind, "hidden", model.keybind == nil)
  set(parts.keybind, "content", model.keybind or "")
  set(parts.seconds, "hidden", model.ready)
  set(parts.seconds, "content", model.seconds and tostring(model.seconds) or "")
  local usable = model.usable ~= false
  set(parts.icon, "rgb", usable and UNTINTED or BLOCKED_ICON)
  local labelColour = not usable and BLOCKED_TEXT or model.ready and COLOURS.text or COLOURS.dimText
  local labelAlpha = usable and 1 or BLOCKED_ALPHA
  set(parts.initials, "rgb", labelColour)
  set(parts.keybind, "rgb", labelColour)
  set(parts.initials, "alpha", labelAlpha)
  set(parts.keybind, "alpha", labelAlpha)
end

-- A cooldown group of up to settings.MAX_GROUP_KEYS ability tiles laid out by layout.grid. configure takes
-- { size, perRow, grow }, returns whether it changed, and redraws on the next update. update takes
-- src/cooldowns tiles and returns whether bounds changed; bounds spans the shown tiles, and an empty group's
-- sides meet at its axis. setInUse(false)
-- hides a custom group that is not in use and collapses its bounds. Tiles are built as the group first needs
-- them, inside its layer, and never destroyed. Ready tiles are bright with their keybind; cooling tiles are
-- dimmed with whole seconds left; tiles whose ability can't be cast are tinted dark. Hovering a tile shows
-- its tooltip.
function view.cooldownGroup(root, tooltip)
  local max = settings.MAX_GROUP_KEYS
  local layer = ui.Layer.new(root)
  local tiles = {}
  local display = nil
  local inUse = true
  local current = {}
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
      line = model.ready and "Ready" or ("Ready in " .. model.seconds .. "s"),
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

  function group.update(models)
    if not inUse then
      current = {}
      for _, parts in ipairs(tiles) do draw.hideAll(parts.all, true) end
      local moved = bounds.w ~= 0 or bounds.h ~= 0
      bounds.w, bounds.h = 0, 0
      if hover.index ~= nil then
        hover.index = nil
        tooltip.hide()
      end
      return moved
    end
    current = models
    local count = math.min(#models, max)
    while #tiles < count do
      tiles[#tiles + 1] = tile(layer)
      hover.add(tiles[#tiles])
    end
    local g = layout.grid(count, display.size, TILE_GAP, display.perRow, display.grow, max)
    local shown = g.bounds
    local moved = bounds.x ~= shown.x or bounds.y ~= shown.y or bounds.w ~= shown.w or bounds.h ~= shown.h
    bounds.x, bounds.y, bounds.w, bounds.h = shown.x, shown.y, shown.w, shown.h
    for i, parts in ipairs(tiles) do
      if i > count then
        draw.hideAll(parts.all, true)
      else
        placeTile(parts, g.tiles[i].x, g.tiles[i].y, display.size)
        showTile(parts, models[i])
      end
    end
    if hover.index ~= nil then showTooltip(hover.index) end
    return moved
  end

  return group
end

local CAST_WIDTH, CAST_HEIGHT, CAST_ICON = 278, 22, 20

-- 278x22, as wide as the resource bar: the channelled ability's icon, its name, and its time left as "1.2s"
-- over a fill of the time spent. update takes a src/channel model, or nil to hide the bar while keeping its
-- bounds, so anchored elements stay put.
function view.castBar(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(CAST_WIDTH, CAST_HEIGHT)
  rect(layer, COLOURS.border, 0, 0, CAST_WIDTH, CAST_HEIGHT)
  rect(layer, COLOURS.track, 1, 1, CAST_WIDTH - 2, CAST_HEIGHT - 2)
  local barX = CAST_ICON + 2
  local fill = draw.bar(layer, COLOURS.cast, COLOURS.track, barX, 1, CAST_WIDTH - barX - 1, CAST_HEIGHT - 2)
  local iconBack = rect(layer, COLOURS.tile, 1, 1, CAST_ICON, CAST_ICON)
  local icon = ui.Sprite.new(layer)
  icon:SetPos(1, 1)
  icon:SetSize(CAST_ICON, CAST_ICON)
  local name = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, barX + 5, 1, 180, CAST_HEIGHT - 2)
  local time = text(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, CAST_WIDTH - 78, 1, 72, CAST_HEIGHT - 2)
  set(layer, "hidden", true)

  local function update(model)
    set(layer, "hidden", model == nil)
    if model == nil then return end
    fill.setFill(model.fill)
    set(iconBack, "hidden", model.icon == nil)
    set(icon, "hidden", model.icon == nil)
    if model.icon ~= nil then set(icon, "sprite", model.icon) end
    set(name, "content", model.name or "")
    local whole = math.tointeger(model.seconds)
    set(time, "content", (whole and tostring(whole) or string.format("%.1f", model.seconds)) .. "s")
  end

  return {
    layer = layer, update = update, setTexture = fill.setTexture, width = CAST_WIDTH, height = CAST_HEIGHT,
    bounds = { x = 0, y = 0, w = CAST_WIDTH, h = CAST_HEIGHT },
  }
end

-- Aura rows by HUD element: tile size, which end the icons gather at, and whether they are debuffs, which get
-- an orange edge. timeFont and timeHeight size the time text along a tile's bottom.
view.AURA_STYLES = {
  targetDebuffs = { size = 26, align = "right", debuff = true, timeFont = FONTS.small, timeHeight = 11 },
  playerDebuffs = { size = 26, align = "left", debuff = true, timeFont = FONTS.small, timeHeight = 11 },
  upkeepBuffs = { size = 26, align = "left", timeFont = FONTS.small, timeHeight = 11 },
  combatBuffs = { size = 36, align = "centre", timeFont = FONTS.body, timeHeight = 13 },
}
local AURA_GAP = 2
-- Room around the tiles for the highlight, which draws up to 3px outside a tile.
local AURA_MARGIN = 3
-- With bars on, each tile has a 4px bar 1px below it.
local AURA_BAR, AURA_BAR_SPACE = 4, 5
-- Bar stripes in the refresh window: white and black runs across the bar.
local STRIPE, STRIPE_GAP = 3, 2

-- Builds one aura tile's components as a draw.group. The bar's cover moves on its own, so it sits outside
-- the group.
local function auraTile(layer, style)
  local size = style.size
  local inner = size - 2
  local group = draw.group()
  local white = COLOURS.highlight
  local timeY = size - style.timeHeight - 3
  local parts = {
    group = group,
    ring = {
      group.add(rect(layer, white, 0, 0, size + 4, 2), -2, -2),
      group.add(rect(layer, white, 0, 0, size + 4, 2), -2, size),
      group.add(rect(layer, white, 0, 0, 2, size), -2, 0),
      group.add(rect(layer, white, 0, 0, 2, size), size, 0),
    },
    edge = group.add(rect(layer, style.debuff and COLOURS.debuff or COLOURS.border, 0, 0, size, size), 0, 0),
    icon = group.add(ui.Sprite.new(layer), 1, 1),
    plate = group.add(rect(layer, white, 0, 0, size - 8, style.timeHeight + 2), 4, timeY),
    time = group.add(text(layer, style.timeFont, ui.AlignMode.CENTRE, 0, 0, size, style.timeHeight + 2), 0, timeY),
    stacks = group.add(text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 21, 12), size - 23, 1),
    track = group.add(rect(layer, COLOURS.border, 0, 0, size, AURA_BAR), 0, size + 1),
    fill = group.add(rect(layer, style.debuff and COLOURS.debuff or COLOURS.dimText, 0, 0, inner, AURA_BAR - 2), 1,
      size + 2),
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

-- Shows a src/auras model on parts at x, y. bars draws the bar and the bars-mode highlight.
local function showAura(parts, model, x, y, size, bars)
  parts.group.place(x, y)
  local timed = model.left ~= nil
  local ring, dashed = model.highlight and not bars, model.highlight and bars
  draw.hideAll(parts.ring, not ring)
  set(parts.dashed, "hidden", not dashed)
  set(parts.edge, "hidden", false)
  set(parts.icon, "hidden", false)
  set(parts.icon, "sprite", model.sprite)
  set(parts.plate, "hidden", not ring)
  set(parts.time, "hidden", model.text == nil)
  set(parts.time, "content", model.text or "")
  set(parts.time, "rgb", ring and COLOURS.darkText or COLOURS.text)
  set(parts.time, "isShadowed", not ring)
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
-- in its refresh window a highlight: a white ring and the time on a white plate, or with bars on a dashed
-- outline and a striped bar. update takes src/auras models and whether bars
-- are on, and returns whether bounds changed. bounds spans the shown tiles, at least one, so an empty row
-- can still be dragged in edit mode. Hovering an icon shows the name and info from info(sprite), which
-- returns { name, info } or nil.
function view.auraRow(root, style, tooltip, info)
  local size = style.size
  local step = size + AURA_GAP
  local width = 2 * AURA_MARGIN + MAX_TILES * step - AURA_GAP
  local height = 2 * AURA_MARGIN + size + AURA_BAR_SPACE
  local layer = ui.Layer.new(root)
  layer:SetSize(width, height)
  local tiles = {}
  for i = 1, MAX_TILES do tiles[i] = auraTile(layer, style) end

  -- x of the first of count tiles.
  local function left(count)
    local spare = (MAX_TILES - count) * step
    if style.align == "right" then return AURA_MARGIN + spare end
    if style.align == "centre" then return AURA_MARGIN + spare // 2 end
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
    tooltip.show({
      title = found and found.name or (style.debuff and "Unknown debuff" or "Unknown buff"),
      left = found and found.info or (found == nil and "Looking up name" or nil),
    }, x, y, size)
  end

  local hover = tooltip.hover(tiles, showTooltip)

  local function update(models, bars)
    current = models
    local count = math.min(#models, MAX_TILES)
    local shown = math.max(count, 1)
    local x, w, h = left(shown), shown * step - AURA_GAP, size + (bars and AURA_BAR_SPACE or 0)
    local moved = bounds.x ~= x or bounds.w ~= w or bounds.h ~= h
    bounds.x, bounds.w, bounds.h = x, w, h
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
    if hover.index ~= nil then showTooltip(hover.index) end
    return moved
  end

  return { layer = layer, update = update, width = width, height = height, bounds = bounds }
end

return view
