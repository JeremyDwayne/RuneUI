-- A cooldown group: a grid of ability tiles, each with its icon or initials, keybind, seconds left while
-- cooling, and a count or bar for charges, recast stages and spender stacks.
local cooldowngroup = {}

local draw = require("src/draw")
local hudparts = require("src/hudparts")
local layout = require("src/layout")
local savedgroups = require("src/savedgroups")
local set = draw.set
local pos = draw.pos
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS
local styleText = hudparts.styleText
local screenPos = hudparts.screenPos
local DEFAULT_LOOK = hudparts.DEFAULT_LOOK
local GOLD = hudparts.GOLD
local SPENDER_COLOURS = hudparts.SPENDER_COLOURS
-- Tile backgrounds are translucent so the game shows through empty tiles.
local TILE_ALPHA = 0.6

local TILE_GAP = 2
-- Tiles at least this big show their seconds in the larger font.
local LARGE_TILE = 40
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
    icon = draw.new(ui.Sprite, layer),
    initials = draw.edgedText(layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, 0, 12),
    dim = rect(layer, COLOURS.border, 0, 0, 0, 0),
    track = rect(layer, COLOURS.border, 0, 0, 0, 0),
    fill = rect(layer, COLOURS.highlight, 0, 0, 0, 0),
    gold = rect(layer, GOLD, 0, 0, 0, 0),
    notchEdge = rect(layer, COLOURS.border, 0, 0, 0, 0),
    notch = rect(layer, COLOURS.highlight, 0, 0, 0, 0),
    count = draw.edgedText(layer, FONTS.body, ui.AlignMode.TOPLEFT, 0, 0, 0, COUNT_HEIGHT),
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
    styleText(parts.count, "body", look, false)
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

-- A cooldown group of up to savedgroups.MAX_GROUP_KEYS ability tiles laid out by layout.grid. configure takes
-- { size, perRow, grow }, returns whether it changed, and redraws on the next update. update takes
-- src/cooldowns tiles and the seconds since the server tick they were read at, and returns whether bounds
-- changed; bounds spans the shown tiles, and an empty group's sides meet at its axis. step(since) counts the
-- cooling tiles down and moves recharge bars from that tick, and returns at once when none moves. setInUse(false)
-- hides a custom group that is not in use and collapses its bounds. Tiles are built as the group first needs
-- them, inside its layer, and never destroyed. Ready tiles are bright with their keybind; cooling tiles are
-- dimmed with whole seconds left; tiles whose ability can't be cast are tinted dark. Hovering a tile shows
-- its tooltip, with the description describe(key) returns, when given. setLook(look) restyles the tiles' text
-- and returns false, as it moves no bounds.
function cooldowngroup.create(root, tooltip, describe)
  local max = savedgroups.MAX_GROUP_KEYS
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
      info = describe and describe(model.key),
      foot = model.ready and "Ready" or ("Ready in " .. tiles[i].shown .. "s"),
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

return cooldowngroup
