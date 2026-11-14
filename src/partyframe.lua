-- The party grid: one cell per group member from a src/party model, each a lifepoints fill with the member's
-- name, their lifepoints as a number, their tag and the leader's icon. Raid cells are one line of tag, name and
-- icon. Cells take no clicks, and hovering one shows the member's name, lifepoints and role.
local partyframe = {}

local draw = require("src/draw")
local hudparts = require("src/hudparts")
local party = require("src/party")
local style = require("src/style")

local set = draw.set
local pos = draw.pos
local size = draw.size
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS
local DEFAULT_LOOK = hudparts.DEFAULT_LOOK

-- The track of a cell whose lifepoints are unknown, the base tank tag's gold, and a dead cell's dashes.
local IDLE = 0x2c3138
local GOLD = COLOURS.adrenaline
local DEAD_EDGE = draw.opaque(COLOURS.dimText)
-- A tag's height, its width at up to two characters in a cell and in a Raid cell, and the leader icon's size.
local TAG_H = 13
local TAG_W = 20
local RAID_TAG_W = 16
local LEADER = 12
-- The opacity of a cell whose member is out of view.
local FAR_ALPHA = 0.45
-- The "Group window closed" line under the grid.
local NOTE_H = 14
local NO_CELLS = {}

-- The width of a tag's box: the mock's at up to two characters, wider for more.
local function tagWidth(tag, raid)
  if raid then
    return math.max(RAID_TAG_W, 7 * #tag + 2)
  end
  return math.max(TAG_W, 7 * #tag + 6)
end

-- Gives a label look's font for role, text colour and shadow, with the font's own outline when the look wants
-- one and the font has it.
local function styleLabel(label, role, look)
  local font = look.fonts[role]
  set(label, "font", id.Font[look.outline and style.outlineFont(font) or font])
  set(label, "rgb", look.text)
  set(label, "isShadowed", look.shadow)
end

-- One cell's components on layer, hidden, in stacking order. edge is a transparent cover that takes the hover.
local function buildCell(layer)
  local p = {}
  p.border = rect(layer, COLOURS.border, 0, 0, 0, 0)
  p.track = rect(layer, COLOURS.healthTrack, 0, 0, 0, 0)
  p.fill = rect(layer, style.FRAME_COLOURS.player, 0, 0, 0, 0)
  p.dashes = draw.new(ui.Canvas, layer)
  p.name = draw.text(layer, FONTS.body, ui.AlignMode.CENTRE, 0, 0, 0, 0)
  p.number = draw.text(layer, FONTS.small, ui.AlignMode.CENTRE, 0, 0, 0, 0)
  p.tagEdge = rect(layer, COLOURS.text, 0, 0, 0, 0)
  p.tagFace = rect(layer, COLOURS.border, 0, 0, 0, 0)
  p.tagText = draw.text(layer, FONTS.small, ui.AlignMode.CENTRE, 0, 0, 0, 0)
  set(p.tagText, "isShadowed", false)
  p.leader = draw.new(ui.Sprite, layer)
  size(p.leader, LEADER, LEADER)
  p.edge = rect(layer, COLOURS.border, 0, 0, 0, 0)
  set(p.edge, "alpha", 0)
  p.tag = { p.tagEdge, p.tagFace, p.tagText }
  -- Every part a far cell dims, and every part.
  p.dimmed = { p.border, p.track, p.fill, p.dashes, p.name, p.number, p.tagEdge, p.tagFace, p.tagText, p.leader }
  p.all = { p.edge, table.unpack(p.dimmed) }
  draw.hideAll(p.all, true)
  return p
end

-- Fits a cell's parts to a w by h box at x, y. A cell puts the name over the number, the tag bottom left and the
-- leader icon bottom right; a Raid cell puts tag, name and icon on one line.
local function fit(p, x, y, w, h, raid, tagW, leader)
  pos(p.border, x, y)
  size(p.border, w, h)
  pos(p.track, x + 1, y + 1)
  size(p.track, w - 2, h - 2)
  pos(p.fill, x + 1, y + 1)
  pos(p.dashes, x, y)
  size(p.dashes, w, h)
  pos(p.edge, x, y)
  size(p.edge, w, h)
  local tagY = raid and y + (h - TAG_H) // 2 or y + h - 1 - TAG_H
  pos(p.tagEdge, x + 1, tagY)
  size(p.tagEdge, tagW, TAG_H)
  pos(p.tagFace, x + 2, tagY + 1)
  size(p.tagFace, tagW - 2, TAG_H - 2)
  pos(p.tagText, x + 1, tagY)
  size(p.tagText, tagW, TAG_H)
  if raid then
    local left = tagW > 0 and tagW + 3 or 3
    pos(p.name, x + left, y + 1)
    size(p.name, w - left - (leader and LEADER + 5 or 3), h - 2)
    pos(p.leader, x + w - 3 - LEADER, y + (h - LEADER) // 2)
    return
  end
  local half = (h - 2) // 2
  pos(p.name, x + 2, y + 2)
  size(p.name, w - 4, half)
  -- The number sits between the tag's slot and the icon's, which match unless the tag is a wide one.
  local left = math.max(TAG_W + 2, tagW + 2)
  local right = left == TAG_W + 2 and left or LEADER + 6
  pos(p.number, x + left, y + 1 + half)
  size(p.number, w - left - right, h - 3 - half)
  pos(p.leader, x + w - 3 - LEADER, y + h - 3 - LEADER)
end

-- The grid on root, hidden until a model shows it. tooltip is a src/tooltip. Returns { layer, bounds,
-- update(model), setLook(look) }: update draws a src/party model, building each cell the first time the group
-- reaches it and hiding the cells past the group's size, and returns whether the bounds changed. bounds is the
-- grid's box, kept from the last group shown so edit mode can place the grid with no group, and a Party row of
-- five until there is one.
function partyframe.create(root, tooltip)
  local layer = draw.new(ui.Layer, root)
  local note = draw.text(layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, 160, NOTE_H)
  set(note, "content", "Group window closed")
  set(note, "hidden", true)
  set(layer, "hidden", true)
  local tier = party.TIER_DEFAULTS.party
  local bounds = { x = 0, y = 0, w = 5 * (tier.w + party.GAP) - party.GAP, h = tier.h }
  local grid = { layer = layer, bounds = bounds }
  local cells = {}
  local current = NO_CELLS
  local look = DEFAULT_LOOK
  -- Counts looks, so a cell refits and restyles on its next draw after one.
  local lookVersion = 0

  local function showTooltip(i)
    local c = current[i]
    if c == nil then
      tooltip.hide()
      return
    end
    local p = cells[i]
    local x, y = hudparts.screenPos(layer, p.x, p.y)
    tooltip.show({ title = c.name, left = c.role, right = c.lifepoints }, x, y, p.h, p.w)
  end

  local hover = tooltip.hover({}, showTooltip)

  -- Draws cell model c of model on parts p. Every write skips an unchanged value.
  local function show(p, c, model)
    local w, h, raid = model.w, model.h, model.raid
    local tagW = c.tag and tagWidth(c.tag, raid) or 0
    local leader = c.leader ~= nil
    if
      p.x ~= c.x
      or p.y ~= c.y
      or p.w ~= w
      or p.h ~= h
      or p.raid ~= raid
      or p.tagW ~= tagW
      or p.hasLeader ~= leader
      or p.tier ~= model.tier
      or p.look ~= lookVersion
    then
      p.x, p.y, p.w, p.h, p.raid, p.tagW, p.hasLeader, p.tier, p.look =
        c.x, c.y, w, h, raid, tagW, leader, model.tier, lookVersion
      fit(p, c.x, c.y, w, h, raid, tagW, leader)
      styleLabel(p.name, model.tier == "duo" and "body" or "small", look)
      styleLabel(p.number, "small", look)
      set(p.fill, "rgb", look.player)
    end
    local alpha = c.far and FAR_ALPHA or 1
    for _, part in ipairs(p.dimmed) do
      set(part, "alpha", alpha)
    end
    local dead = c.state == "dead"
    set(p.border, "hidden", false)
    set(p.border, "rgb", dead and COLOURS.healthTrack or c.state == "low" and COLOURS.highlight or COLOURS.border)
    set(p.track, "hidden", false)
    set(p.track, "rgb", c.fill == nil and IDLE or COLOURS.healthTrack)
    local filled = c.fill and math.floor((w - 2) * c.fill + 0.5) or 0
    set(p.fill, "hidden", filled == 0)
    if filled > 0 then
      size(p.fill, filled, h - 2)
    end
    set(p.dashes, "hidden", not dead)
    if dead and (p.dashW ~= w or p.dashH ~= h) then
      p.dashW, p.dashH = w, h
      draw.dashedBox(p.dashes, w, h, 1, DEAD_EDGE)
    end
    set(p.name, "hidden", false)
    set(p.name, "content", c.name)
    set(p.number, "hidden", c.text == nil)
    if c.text ~= nil then
      set(p.number, "content", c.text)
    end
    draw.hideAll(p.tag, c.tag == nil)
    if c.tag ~= nil then
      local gold = c.tag == party.BASE_TANK
      set(p.tagEdge, "rgb", gold and GOLD or COLOURS.text)
      set(p.tagFace, "rgb", gold and GOLD or COLOURS.border)
      set(p.tagText, "rgb", gold and style.DARK_TEXT or COLOURS.text)
      set(p.tagText, "content", c.tag)
    end
    set(p.leader, "hidden", not leader)
    if leader then
      draw.icon(p.leader, c.leader)
    end
    set(p.edge, "hidden", false)
  end

  function grid.update(model)
    set(layer, "hidden", model.hidden)
    if model.hidden then
      current = NO_CELLS
      if hover.index ~= nil then
        tooltip.hide()
      end
      return false
    end
    current = model.cells
    for i, c in ipairs(current) do
      if cells[i] == nil then
        cells[i] = buildCell(layer)
        hover.add(cells[i])
      end
      show(cells[i], c, model)
    end
    for i = #current + 1, #cells do
      draw.hideAll(cells[i].all, true)
    end
    set(note, "hidden", not model.closed)
    pos(note, 0, model.height + 2)
    size(layer, math.max(model.width, 160), model.height + 2 + NOTE_H)
    if hover.index ~= nil then
      showTooltip(hover.index)
    end
    local moved = bounds.w ~= model.width or bounds.h ~= model.height
    bounds.w = model.width
    bounds.h = model.height
    return moved
  end

  -- Takes a src/style look for the cells' fonts, text and fill colour. The bounds never change with it.
  function grid.setLook(newLook)
    if newLook ~= look then
      look = newLook
      lookVersion = lookVersion + 1
    end
    return false
  end

  return grid
end

return partyframe
