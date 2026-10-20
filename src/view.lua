-- Draws RuneUI elements on the plugin layer from display models, in a flat dark style.
-- Each constructor returns { layer, update(model) }; place() positions a layer on the game window.
local view = {}

-- Closest client fonts to 13px values, 10px labels and seconds sized to each tile.
local FONTS = {
  body = id.Font.MUSEO_SANS_13PT_BOLD,
  small = id.Font.NOTOSANS_BOLD_10,
  seconds = id.Font.MUSEO_SANS_17PT_BOLD,
  smallSeconds = id.Font.MUSEO_SANS_15PT_BOLD,
}

local COLOURS = {
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
  emptyBlock = 0x22262b,
  tile = 0x141414,
  dimText = 0xc7ccd1,
}
-- Tile backgrounds are translucent so the game shows through empty tiles.
local TILE_ALPHA = 0.6

local warned = {}

-- Writes a component property, logging the first failure per property instead of erroring.
local function set(obj, field, value)
  local ok, err = pcall(function() obj[field] = value end)
  if not ok and not warned[field] then
    warned[field] = true
    log("cannot set " .. field .. ":", err)
  end
end

local function rect(parent, rgb, x, y, width, height)
  local r = ui.Rectangle.new(parent)
  set(r, "fill", true)
  set(r, "rgb", rgb)
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

local function text(parent, font, horizontal, x, y, width, height)
  local t = ui.Text.new(parent)
  set(t, "font", font)
  set(t, "rgb", COLOURS.text)
  set(t, "isShadowed", true)
  align(t, horizontal)
  t:SetPos(x, y)
  t:SetSize(width, height)
  return t
end

-- Sets a bar's width from a 0..1 fill, hiding it when the fill is unknown.
local function setFill(bar, fill, fullWidth)
  set(bar, "hidden", fill == nil)
  if fill ~= nil then bar:SetWidth(math.floor(fullWidth * fill)) end
end

-- pos: { x, y, anchorX, anchorY }, with anchors as fractions of the game window.
function view.place(layer, pos)
  layer:SetPos(pos.x, pos.y, pos.anchorX, pos.anchorY)
end

local FRAME_WIDTH = 250
local HEALTH_HEIGHT = 46
local POWER_HEIGHT = 6

-- A unit frame bar with the name on the left and the value on the right; returns its update(model).
local function unitBar(layer, rgb, y, height)
  local inner = FRAME_WIDTH - 2
  rect(layer, COLOURS.healthTrack, 1, y, inner, height)
  local bar = rect(layer, rgb, 1, y, inner, height)
  local name = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 6, y, 140, height)
  local value = text(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, FRAME_WIDTH - 101, y, 95, height)
  return function(model)
    setFill(bar, model.fill, inner)
    set(name, "content", model.name)
    set(value, "content", model.valueText)
  end
end

-- 250x55: 46px health bar with name and "13.1K | 78%", 6px prayer bar below.
function view.playerFrame(root)
  local height = HEALTH_HEIGHT + POWER_HEIGHT + 3
  local prayerY = HEALTH_HEIGHT + 2
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, height)
  rect(layer, COLOURS.border, 0, 0, FRAME_WIDTH, height)
  local updateHealth = unitBar(layer, COLOURS.player, 1, HEALTH_HEIGHT)
  local prayerTrack = rect(layer, COLOURS.healthTrack, 1, prayerY, FRAME_WIDTH - 2, POWER_HEIGHT)
  local prayer = rect(layer, COLOURS.prayer, 1, prayerY, FRAME_WIDTH - 2, POWER_HEIGHT)

  local function update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then return end
    updateHealth(model)
    set(prayerTrack, "hidden", model.prayerText == nil)
    setFill(prayer, model.prayerFill, FRAME_WIDTH - 2)
  end

  return { layer = layer, update = update }
end

local DEBUFF_SIZE = 26
local MAX_DEBUFFS = 8
local DEBUFF_ROW = DEBUFF_SIZE + 4

-- 250x78: a right-aligned row of debuff icons above a 46px health bar with name and "6,800 | 58%".
function view.targetFrame(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, DEBUFF_ROW + HEALTH_HEIGHT + 2)
  rect(layer, COLOURS.border, 0, DEBUFF_ROW, FRAME_WIDTH, HEALTH_HEIGHT + 2)
  local updateHealth = unitBar(layer, COLOURS.target, DEBUFF_ROW + 1, HEALTH_HEIGHT)

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
        slot.edge:SetPos(x, 0)
        slot.icon:SetPos(x + 1, 1)
        set(slot.icon, "sprite", model.debuffs[i])
      end
    end
  end

  return { layer = layer, update = update }
end

local BAR_WIDTH = 278
local MAX_BLOCKS = 12
-- Fill fraction at which the centred percent label sits entirely on the fill.
local PERCENT_ON_FILL = 0.56

-- 278 wide: spender blocks with a count label, adrenaline bar with markers, marker labels.
function view.resourceBar(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(BAR_WIDTH, 52)

  local blocks = {}
  for i = 1, MAX_BLOCKS do blocks[i] = rect(layer, COLOURS.emptyBlock, 0, 0, 0, 12) end
  local spenderLabel = text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, BAR_WIDTH - 80, 0, 80, 12)

  rect(layer, COLOURS.border, 0, 15, BAR_WIDTH, 20)
  rect(layer, COLOURS.track, 1, 16, BAR_WIDTH - 2, 18)
  local fill = rect(layer, COLOURS.adrenaline, 1, 16, BAR_WIDTH - 2, 18)
  -- Light lines with black edges, so a marker shows on both the dark track and the fill.
  local markers = {}
  for i = 1, 2 do
    markers[i] = { edge = rect(layer, COLOURS.border, 0, 12, 4, 26), line = rect(layer, COLOURS.marker, 0, 13, 2, 24) }
  end
  local percent = text(layer, FONTS.body, ui.AlignMode.CENTRE, 0, 16, BAR_WIDTH, 18)
  local markerLabels = {
    text(layer, FONTS.small, ui.AlignMode.CENTRE, 0, 37, 80, 14),
    text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, BAR_WIDTH - 80, 37, 80, 14),
  }

  local function updateSpender(spender)
    set(spenderLabel, "hidden", spender == nil)
    local count = spender and spender.max or 0
    local blockWidth = count > 0 and math.floor((BAR_WIDTH - 86 - 2 * (count - 1)) / count) or 0
    for i, block in ipairs(blocks) do
      set(block, "hidden", i > count)
      if i <= count then
        block:SetPos((i - 1) * (blockWidth + 2), 0)
        block:SetWidth(blockWidth)
        set(block, "rgb", i <= spender.count and COLOURS.spender or COLOURS.emptyBlock)
      end
    end
    if spender ~= nil then set(spenderLabel, "content", spender.label .. " " .. spender.count .. "/" .. spender.max) end
  end

  local function update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then return end
    setFill(fill, model.fill, BAR_WIDTH - 2)
    set(percent, "content", model.text)
    -- Dark text once the fill passes the centred label, white with a shadow on the track.
    local onFill = model.fill >= PERCENT_ON_FILL
    set(percent, "rgb", onFill and COLOURS.darkText or COLOURS.text)
    set(percent, "isShadowed", not onFill)
    for i, marker in ipairs(model.markers) do
      local x = math.min(math.floor(marker.at * (BAR_WIDTH - 2)), BAR_WIDTH - 3)
      markers[i].edge:SetPos(x - 1, 12)
      markers[i].line:SetPos(x, 13)
      set(markerLabels[i], "content", marker.label)
      if i == 1 then markerLabels[i]:SetPos(x - 40, 37) end
    end
    updateSpender(model.spender)
  end

  return { layer = layer, update = update }
end

-- Tile sizes: 42px tiles for the rotation and 36px for cooldowns, 2px apart.
view.TILE_STYLES = {
  rotation = { size = 42, gap = 2, secondsFont = FONTS.seconds },
  cooldowns = { size = 36, gap = 2, secondsFont = FONTS.smallSeconds },
}
local MAX_TILES = 10
local COOLING_DIM = 0.62

-- Builds one tile's components; place(x) moves them all, keeping each part's offset in the tile.
local function tile(layer, style)
  local size = style.size
  local offsets = {}
  local function at(component, dx, dy)
    offsets[#offsets + 1] = { component = component, dx = dx, dy = dy }
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
    for _, o in ipairs(offsets) do o.component:SetPos(x + o.dx, o.dy) end
  end

  function parts.setHidden(hidden)
    for _, o in ipairs(offsets) do set(o.component, "hidden", hidden) end
  end

  return parts
end

-- A centred row of up to 10 ability tiles; update takes src/cooldowns tiles. Ready tiles are bright with
-- their keybind; cooling tiles are dimmed with whole seconds left.
function view.cooldownGroup(root, style)
  local step = style.size + style.gap
  local width = MAX_TILES * step - style.gap
  local layer = ui.Layer.new(root)
  layer:SetSize(width, style.size)
  local tiles = {}
  for i = 1, MAX_TILES do tiles[i] = tile(layer, style) end

  local function update(models)
    local count = math.min(#models, MAX_TILES)
    local offset = math.floor((width - (count * step - style.gap)) / 2)
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

  return { layer = layer, update = update }
end

return view
