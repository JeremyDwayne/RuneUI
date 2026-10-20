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
  if align == "center" then return start + (length - size) // 2 end
  if align == "right" or align == "bottom" then return start + length - size end
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
    if out[name] ~= nil then return out[name] end
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

  for name in pairs(bounds) do resolveOne(name) end
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
  if target == name then return false end
  for _, child in ipairs(layout.chain(anchors, name)) do
    if child == target then return false end
  end
  return true
end

return layout
