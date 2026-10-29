-- An aura row: up to ten buff or debuff icons gathered at one end, each with its time left and stacks, and a
-- highlight in its refresh window.
local aurarow = {}

local draw = require("src/draw")
local hudparts = require("src/hudparts")
local set = draw.set
local pos = draw.pos
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS
local styleFont = hudparts.styleFont
local screenPos = hudparts.screenPos
local DEFAULT_LOOK = hudparts.DEFAULT_LOOK
-- Aura rows by HUD element: which end the icons gather at, and whether they are debuffs, edged in the look's
-- debuffEdge colour. name keys the row's icon size and text in a src/style look's auras.
aurarow.STYLES = {
  targetDebuffs = { name = "targetDebuffs", align = "right", debuff = true, kind = "Debuff on target" },
  playerDebuffs = { name = "playerDebuffs", align = "left", debuff = true, kind = "Debuff on you" },
  upkeepBuffs = { name = "upkeepBuffs", align = "left", kind = "Buff" },
  combatBuffs = { name = "combatBuffs", align = "centre", kind = "Buff" },
}
local MAX_TILES = 10
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

-- Builds one aura tile's components, sized by fitTile: an edge, black or a debuff's look colour, round the
-- game's dark slot, with the icon over it.
local function auraTile(layer)
  local white = COLOURS.highlight
  return {
    ring = {
      rect(layer, white, 0, 0, 0, 0),
      rect(layer, white, 0, 0, 0, 0),
      rect(layer, white, 0, 0, 0, 0),
      rect(layer, white, 0, 0, 0, 0),
    },
    edge = rect(layer, COLOURS.border, 0, 0, 0, 0),
    slot = rect(layer, COLOURS.slot, 0, 0, 0, 0),
    icon = draw.new(ui.Sprite, layer),
    time = draw.edgedText(layer, FONTS.small, ui.AlignMode.CENTRE, 0, 0, 0, 0),
    stacks = draw.edgedText(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 0, 0),
    track = rect(layer, COLOURS.border, 0, 0, 0, AURA_BAR),
    fill = rect(layer, COLOURS.dimText, 0, 0, 0, AURA_BAR - 2),
    stripes = draw.new(ui.Canvas, layer),
    cover = rect(layer, COLOURS.border, 0, 0, 0, AURA_BAR - 2),
    dashed = draw.new(ui.Canvas, layer),
  }
end

-- Sizes an aura tile's parts for a size pixel tile, with its time text timeH tall along the bottom and its
-- stacks stacksH tall at the top right, and gathers them into parts.group, which moves them together. The bar's
-- cover moves on its own, so it sits outside the group.
local function fitTile(parts, size, timeH, stacksH)
  local inner = size - 2
  local white = draw.opaque(COLOURS.highlight)
  local group = draw.group()
  local ring = parts.ring
  draw.size(group.add(ring[1], -2, -2), size + 4, 2)
  draw.size(group.add(ring[2], -2, size), size + 4, 2)
  draw.size(group.add(ring[3], -2, 0), 2, size)
  draw.size(group.add(ring[4], size, 0), 2, size)
  draw.size(group.add(parts.edge, 0, 0), size, size)
  draw.size(group.add(parts.slot, 1, 1), inner, inner)
  draw.size(group.add(parts.icon, 1, 1), inner, inner)
  draw.size(group.add(parts.time, 0, size - timeH - 3), size, timeH + 2)
  draw.size(group.add(parts.stacks, 1, 1), size - 3, stacksH)
  draw.size(group.add(parts.track, 0, size + 1), size, AURA_BAR)
  group.add(parts.fill, 1, size + 2)
  draw.size(group.add(parts.stripes, 1, size + 2), inner, AURA_BAR - 2)
  parts.stripes:Clear()
  for x = 0, inner - 1, STRIPE + STRIPE_GAP do
    parts.stripes:AddRectangle(x, 0, math.min(STRIPE, inner - x), AURA_BAR - 2, white)
  end
  draw.size(group.add(parts.dashed, -3, -3), size + 6, size + 6)
  draw.dashedBox(parts.dashed, size + 6, size + 6, 2, white)
  parts.group = group
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
  set(parts.slot, "hidden", false)
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

-- An aura model's time left, such as "20s" or "6m", with its stacks, or its count as stacks, or nil.
local function auraStatus(model)
  local stacks = model.stacks and (model.stacks .. " stacks")
  if model.text == nil or model.text == "" then
    return stacks
  end
  if model.left == nil then
    return model.text .. " stacks"
  end
  local time = model.text:match("%d$") and (model.text .. "s") or model.text
  return stacks and (time .. ", " .. stacks) or time
end

-- A row of up to 10 aura icons gathered at aura.align's end, sized by its look's auras entry. Each icon shows
-- its time left and stacks, and in its refresh window a highlight: a white ring, or with bars on a dashed
-- outline and a striped bar. update takes src/auras models and whether bars are on, and returns whether bounds
-- changed. bounds spans the shown tiles, at least one, so an empty row can still be dragged in edit mode.
-- setLook refits the tiles when the icon size or a text height changes, and returns whether bounds changed.
-- Hovering an icon shows the name and info from info(sprite), a src/icons index, over whether it is a buff or
-- whose debuff, and its time left or stacks.
function aurarow.create(root, aura, tooltip, info)
  local size, step, timeH, stacksH
  local layer = draw.new(ui.Layer, root)
  local row = { layer = layer }
  -- The tiles built so far, as auras appear, up to MAX_TILES. Building every spare tile at load cost seconds.
  local tiles = {}

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
  local shownBars = false
  local bounds = { x = 0, y = AURA_MARGIN, w = 0, h = 0 }
  row.bounds = bounds
  -- The look shown.
  local shown = nil

  local function showTooltip(i)
    local model = current[i]
    if model == nil then
      tooltip.hide()
      return
    end
    local found = info(model.sprite)
    local x, y = screenPos(layer, tiles[i].group.x, AURA_MARGIN)
    local title = found.name or (aura.debuff and "Unknown debuff" or "Unknown buff")
    tooltip.show({ title = title, left = aura.kind, right = auraStatus(model), info = found.info }, x, y, size)
  end

  local hover = tooltip.hover(tiles, showTooltip)

  -- Gives parts the fonts and debuff colours of the look shown.
  local function styleTile(parts)
    local own = shown.auras[aura.name]
    styleFont(parts.time, own.font, shown, false)
    styleFont(parts.stacks, own.stacksFont, shown, false)
    if aura.debuff then
      set(parts.edge, "rgb", shown.debuffEdge)
      set(parts.fill, "rgb", shown.debuffEdge)
    end
  end

  -- Tile i, built, fitted and styled on its first use.
  local function tile(i)
    local parts = tiles[i]
    if parts == nil then
      parts = auraTile(layer)
      tiles[i] = parts
      fitTile(parts, size, timeH, stacksH)
      styleTile(parts)
      hover.add(parts)
    end
    return parts
  end

  local function update(models, bars)
    current = models
    shownBars = bars
    local count = math.min(#models, MAX_TILES)
    local shownCount = math.max(count, 1)
    local x = left(shownCount)
    local w = shownCount * step - AURA_GAP
    local h = size + (bars and AURA_BAR_SPACE or 0)
    local moved = bounds.x ~= x or bounds.w ~= w or bounds.h ~= h
    bounds.x = x
    bounds.w = w
    bounds.h = h
    local first = left(count)
    for i = 1, count do
      showAura(tile(i), models[i], first + (i - 1) * step, AURA_MARGIN, size, bars)
    end
    for i = count + 1, #tiles do
      tiles[i].group.set("hidden", true)
      set(tiles[i].cover, "hidden", true)
    end
    if hover.index ~= nil then
      showTooltip(hover.index)
    end
    return moved
  end

  local function setLook(look)
    if look == shown then
      return false
    end
    shown = look
    local own = look.auras[aura.name]
    local newTimeH = math.max(11, own.points)
    local newStacksH = math.max(12, own.stacksPoints + 2)
    local refit = own.size ~= size or newTimeH ~= timeH or newStacksH ~= stacksH
    if refit then
      size = own.size
      step = size + AURA_GAP
      timeH = newTimeH
      stacksH = newStacksH
    end
    for _, parts in ipairs(tiles) do
      if refit then
        fitTile(parts, size, timeH, stacksH)
      end
      styleTile(parts)
    end
    if not refit then
      return false
    end
    row.width = 2 * AURA_MARGIN + MAX_TILES * step - AURA_GAP
    row.height = 2 * AURA_MARGIN + size + AURA_BAR_SPACE
    draw.size(layer, row.width, row.height)
    return update(current, shownBars)
  end

  setLook(DEFAULT_LOOK)
  row.update = update
  row.setLook = setLook
  return row
end

return aurarow
