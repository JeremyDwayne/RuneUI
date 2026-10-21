-- Pure rules for the options window's cooldown editor: where a dragged tile lands and what the picker lists.
local cooldowns = require("src/cooldowns")

local editor = {}

-- Dropping within this fraction of a tile's width either side of its centre swaps instead of inserting.
local SWAP_ZONE = 0.1

-- row: { count, step, size, offset } in the row's own pixels; x: cursor x in the same space.
-- Returns { kind = "swap", index } over a tile's middle, else { kind = "insert", index } before that slot.
function editor.dropTarget(row, x)
  local index = 1
  for i = 1, row.count do
    local centre = row.offset + (i - 1) * row.step + row.size / 2
    if math.abs(x - centre) <= row.size * SWAP_ZONE then
      return { kind = "swap", index = i }
    end
    if x > centre then
      index = i + 1
    end
  end
  return { kind = "insert", index = index }
end

-- grid: { count, step, size, perRow } in the grid's own pixels, filling rows of perRow from the top-left;
-- x, y: the cursor in the same space. Returns dropTarget's result for the row under y, with the index
-- counted across rows.
function editor.gridDropTarget(grid, x, y)
  local rows = math.max(1, math.ceil(grid.count / grid.perRow))
  local row = math.max(0, math.min(rows - 1, y // grid.step))
  local first = row * grid.perRow
  local inRow = math.max(0, math.min(grid.perRow, grid.count - first))
  local target = editor.dropTarget({ count = inRow, step = grid.step, size = grid.size, offset = 0 }, x)
  return { kind = target.kind, index = first + target.index }
end

local function indexOf(list, key)
  for i, k in ipairs(list) do
    if k == key then
      return i
    end
  end
end

-- The settings edit for dropping key, which list holds, on target: { op = "swap", other } or
-- { op = "move", index }, or nil for no change. The index is for src/settings move, which takes the key out
-- before inserting.
function editor.dropAction(list, key, target)
  if target.kind == "swap" then
    local other = list[target.index]
    if other == nil or other == key then
      return nil
    end
    return { op = "swap", other = other }
  end
  local index = target.index
  local from = indexOf(list, key)
  if from ~= nil and from < index then
    index = index - 1
  end
  if index == from then
    return nil
  end
  return { op = "move", index = index }
end

-- Picker sections for groupName's "+" tile: abilities in no group, then one section per other group with the
-- abilities it holds, which adding moves across. groups lists every group in order as { name, title, keys },
-- keys being what it shows with the style being edited. keys is every known ability in display order. A
-- style, such as "magic", keeps that style's abilities and the style-free ones.
function editor.pickerSections(groupName, groups, keys, style)
  local holder = {}
  for _, group in ipairs(groups) do
    for _, key in ipairs(group.keys) do
      holder[key] = group.name
    end
  end
  local notShown = {}
  local held = {}
  for _, key in ipairs(keys) do
    local keyStyle = style and cooldowns.styleOf(key)
    if keyStyle == nil or keyStyle == style then
      local name = holder[key]
      if name == nil then
        notShown[#notShown + 1] = key
      elseif name ~= groupName then
        held[name] = held[name] or {}
        table.insert(held[name], key)
      end
    end
  end
  local sections = { { title = "Not shown", keys = notShown } }
  for _, group in ipairs(groups) do
    if group.name ~= groupName then
      sections[#sections + 1] = { title = "In " .. group.title, keys = held[group.name] or {} }
    end
  end
  return sections
end

return editor
