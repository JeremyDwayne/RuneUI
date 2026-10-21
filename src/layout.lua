-- Pure geometry for HUD anchors and snapping. Rects are { x, y, w, h } in UI units from the game window's
-- bottom center, the space saved positions use. An anchor is { target, side, align, gap, offset }: the
-- element sits gap pixels outside target's side, with its align edge or center offset from target's.
local layout = {}

-- Alignments each side offers, in the order edit mode lists them.
layout.ALIGNS = {
  left = { "top", "center", "bottom" },
  right = { "top", "center", "bottom" },
  top = { "left", "center", "right" },
  bottom = { "left", "center", "right" },
}

-- The window rect of an element at pos, a { x, y } layer position, showing bounds inside its layer.
function layout.rect(pos, bounds)
  return { x = pos.x + bounds.x, y = pos.y + bounds.y, w = bounds.w, h = bounds.h }
end

-- Start of a span of length size aligned to the span from start to start + length, before the offset.
local function aligned(align, start, length, size)
  if align == "center" then
    return start + (length - size) // 2
  end
  if align == "right" or align == "bottom" then
    return start + length - size
  end
  return start
end

-- x and y of a w by h child placed by anchor against target, a rect.
function layout.place(anchor, target, w, h)
  local side, gap, offset = anchor.side, anchor.gap, anchor.offset
  if side == "left" or side == "right" then
    local x = side == "left" and target.x - gap - w or target.x + target.w + gap
    return x, aligned(anchor.align, target.y, target.h, h) + offset
  end
  local y = side == "top" and target.y - gap - h or target.y + target.h + gap
  return aligned(anchor.align, target.x, target.w, w) + offset, y
end

-- Positions for every element in bounds: anchored ones placed against their targets' resolved rects, the
-- rest at their entry in positions. bounds holds each element's shown rect inside its layer.
function layout.resolve(positions, anchors, bounds)
  local out, visiting = {}, {}

  local function resolveOne(name)
    if out[name] ~= nil then
      return out[name]
    end
    local anchor = anchors[name]
    if anchor == nil or bounds[anchor.target] == nil or visiting[name] then
      out[name] = positions[name]
      return out[name]
    end
    visiting[name] = true
    local target = layout.rect(resolveOne(anchor.target), bounds[anchor.target])
    local b = bounds[name]
    local x, y = layout.place(anchor, target, b.w, b.h)
    out[name] = { x = x - b.x, y = y - b.y, anchorX = 0.5, anchorY = 1 }
    return out[name]
  end

  for name in pairs(bounds) do
    resolveOne(name)
  end
  return out
end

-- The { side, align, gap, offset } that resolve turns back into child, a rect, against target, a rect.
function layout.capture(child, target, side, align)
  local anchor = { side = side, align = align, gap = 0, offset = 0 }
  local x, y = layout.place(anchor, target, child.w, child.h)
  if side == "left" then
    anchor.gap, anchor.offset = x - child.x, child.y - y
  elseif side == "right" then
    anchor.gap, anchor.offset = child.x - x, child.y - y
  elseif side == "top" then
    anchor.gap, anchor.offset = y - child.y, child.x - x
  else
    anchor.gap, anchor.offset = child.y - y, child.x - x
  end
  return anchor
end

-- Tile layout for a cooldown group of count tiles, each size wide with gap between, in rows of up to perRow
-- that stack in the grow direction: "down" or "up" rows, or "left" or "right" columns. Every row is centred on
-- the group's axis. The box fits max tiles, and the edge opposite grow stays put as rows are added. Returns
-- { w, h, tiles = { { x, y } }, bounds = { x, y, w, h } }, bounds spanning the shown tiles; an empty group's
-- bounds are one row deep with their sides meeting at the axis.
function layout.grid(count, size, gap, perRow, grow, max)
  local step = size + gap
  local vertical = grow == "up" or grow == "down"
  local along = math.min(max, perRow) * step - gap
  local across = math.ceil(max / perRow) * step - gap
  local w, h = along, across
  if not vertical then
    w, h = across, along
  end

  -- x, y of a span along and across the axis, flipping across from the far edge for up and left.
  local function place(alongAt, acrossAt, acrossSize)
    if grow == "up" then
      return alongAt, h - acrossAt - acrossSize
    end
    if grow == "left" then
      return w - acrossAt - acrossSize, alongAt
    end
    if vertical then
      return alongAt, acrossAt
    end
    return acrossAt, alongAt
  end

  local tiles = {}
  for i = 0, count - 1 do
    local row = i // perRow
    local inRow = math.min(perRow, count - row * perRow)
    local x, y = place((along - (inRow * step - gap)) // 2 + (i % perRow) * step, row * step, size)
    tiles[#tiles + 1] = { x = x, y = y }
  end

  local widest = math.min(count, perRow) * step - gap
  if count == 0 then
    widest = 0
  end
  local deep = math.max(1, math.ceil(count / perRow)) * step - gap
  local bx, by = place((along - widest) // 2, 0, deep)
  local bounds = { x = bx, y = by, w = vertical and widest or deep, h = vertical and deep or widest }
  return { w = w, h = h, tiles = tiles, bounds = bounds }
end

-- Every element anchored to name, directly or through a chain.
function layout.chain(anchors, name)
  local found, seen = {}, { [name] = true }
  local function walk(parent)
    for child, anchor in pairs(anchors) do
      if anchor.target == parent and not seen[child] then
        seen[child] = true
        found[#found + 1] = child
        walk(child)
      end
    end
  end
  walk(name)
  return found
end

-- Whether name may anchor to target: not itself, and not anything anchored to it.
function layout.canAnchor(anchors, name, target)
  if target == name then
    return false
  end
  for _, child in ipairs(layout.chain(anchors, name)) do
    if child == target then
      return false
    end
  end
  return true
end

-- The shift along one axis that brings a span's start, center or end onto another rect's, the nearest within
-- range, or else one of its ends onto a multiple of grid. Returns the shift and the line it lands on, or 0.
local function snapAxis(start, length, others, pos, size, range, grid)
  local best, line = nil, nil
  local function try(from, to)
    local d = to - from
    if math.abs(d) <= range and (best == nil or math.abs(d) < math.abs(best)) then
      best, line = d, to
    end
  end
  for _, o in ipairs(others) do
    local oStart, oLength = o[pos], o[size]
    for _, to in ipairs({ oStart, oStart + oLength // 2, oStart + oLength }) do
      try(start, to)
      try(start + length // 2, to)
      try(start + length, to)
    end
  end
  if best == nil and grid ~= nil then
    for _, from in ipairs({ start, start + length }) do
      try(from, math.floor(from / grid + 0.5) * grid)
    end
  end
  return best or 0, line
end

-- Snaps a dragged rect onto the lines of others, a list of rects, or onto a grid of that spacing when no
-- element line is within range. Returns { x, y, guideX, guideY }, each guide being the line an axis snapped
-- to, or nil.
function layout.snap(rect, others, range, grid)
  local dx, guideX = snapAxis(rect.x, rect.w, others, "x", "w", range, grid)
  local dy, guideY = snapAxis(rect.y, rect.h, others, "y", "h", range, grid)
  return { x = rect.x + dx, y = rect.y + dy, guideX = guideX, guideY = guideY }
end

-- The rects in rects, by name, that a drag of name can snap to, as a list: all but name and its chain.
function layout.snapTargets(rects, anchors, name)
  local skip = { [name] = true }
  for _, child in ipairs(layout.chain(anchors, name)) do
    skip[child] = true
  end
  local targets = {}
  for other, r in pairs(rects) do
    if not skip[other] then
      targets[#targets + 1] = r
    end
  end
  return targets
end

return layout
