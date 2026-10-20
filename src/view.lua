-- Draws RuneUI elements on the plugin layer from src/frames display models.
-- Each constructor returns { layer, update(model) }; place() positions a layer on the game window.
local view = {}

-- Closest client fonts to 13px values and 10px labels.
local FONTS = {
  body = id.Font.MUSEO_SANS_13PT_BOLD,
  small = id.Font.NOTOSANS_BOLD_10,
}

local COLOURS = {
  border = 0x000000,
  track = 0x1a1d21,
  player = 0x2f63a8,
  target = 0xa4511c,
  prayer = 0xdfe4ea,
  adrenaline = 0xffb000,
  marker = 0xdfe4ea,
  text = 0xffffff,
  darkText = 0x111316,
  spender = 0xdfe4ea,
  emptyBlock = 0x22262b,
}

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

local FRAME_WIDTH = 300

-- A unit frame bar with the name on the left and the value on the right; returns its update(model).
local function unitBar(layer, rgb, y, height)
  local inner = FRAME_WIDTH - 2
  rect(layer, COLOURS.track, 1, y, inner, height)
  local bar = rect(layer, rgb, 1, y, inner, height)
  local name = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 9, y, 160, height)
  local value = text(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, 130, y, 161, height)
  return function(model)
    setFill(bar, model.fill, inner)
    set(name, "content", model.name)
    set(value, "content", model.valueText)
  end
end

-- 300x46: health bar with name and "13.1K | 78%", prayer bar below.
function view.playerFrame(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, 46)
  rect(layer, COLOURS.border, 0, 0, FRAME_WIDTH, 46)
  local updateHealth = unitBar(layer, COLOURS.player, 1, 37)
  local prayerTrack = rect(layer, COLOURS.track, 1, 39, FRAME_WIDTH - 2, 6)
  local prayer = rect(layer, COLOURS.prayer, 1, 39, FRAME_WIDTH - 2, 6)

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
local MAX_DEBUFFS = 10
local DEBUFF_ROW = DEBUFF_SIZE + 4

-- 300x76: a right-aligned row of debuff icons above a 46 tall health bar with name and "6,800 | 58%".
function view.targetFrame(root)
  local layer = ui.Layer.new(root)
  layer:SetSize(FRAME_WIDTH, DEBUFF_ROW + 46)
  rect(layer, COLOURS.border, 0, DEBUFF_ROW, FRAME_WIDTH, 46)
  local updateHealth = unitBar(layer, COLOURS.target, DEBUFF_ROW + 1, 44)

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

return view
