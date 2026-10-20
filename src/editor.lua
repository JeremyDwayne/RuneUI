-- Pure rules for the options window's cooldown editor: where a dragged tile lands and what the picker lists.
local cooldowns = require("src/cooldowns")

local editor = {}

-- Dropping within this fraction of a tile's width either side of its centre swaps instead of inserting.
local SWAP_ZONE = 0.1

local OTHER_GROUP = { rotation = "cooldowns", cooldowns = "rotation" }
local GROUP_TITLES = { rotation = "In rotation", cooldowns = "In cooldowns" }

-- row: { count, step, size, offset } in the row's own pixels; x: cursor x in the same space.
-- Returns { kind = "swap", index } over a tile's middle, else { kind = "insert", index } before that slot.
function editor.dropTarget(row, x)
  local index = 1
  for i = 1, row.count do
    local centre = row.offset + (i - 1) * row.step + row.size / 2
    if math.abs(x - centre) <= row.size * SWAP_ZONE then return { kind = "swap", index = i } end
    if x > centre then index = i + 1 end
  end
  return { kind = "insert", index = index }
end

local function indexOf(list, key)
  for i, k in ipairs(list) do
    if k == key then return i end
  end
end

-- The settings edit for dropping key on target in groupName: { op = "swap", other } or
-- { op = "move", group, index }, or nil for no change. Indexes are for src/settings move, which takes
-- the key out before inserting.
function editor.dropAction(groups, key, groupName, target)
  local list = groups[groupName]
  if target.kind == "swap" then
    local other = list[target.index]
    if other == nil or other == key then return nil end
    return { op = "swap", other = other }
  end
  local index = target.index
  local from = indexOf(list, key)
  if from ~= nil and from < index then index = index - 1 end
  return { op = "move", group = groupName, index = index }
end

-- Picker sections for groupName's "+" tile: abilities in neither group, then those in the other group,
-- which adding moves across. keys is every known ability in display order. A style, such as "magic",
-- keeps that style's abilities and the style-free ones.
function editor.pickerSections(groupName, groups, keys, style)
  local other = OTHER_GROUP[groupName]
  local notShown, inOther = {}, {}
  for _, key in ipairs(keys) do
    local keyStyle = style and cooldowns.styleOf(key)
    if keyStyle == nil or keyStyle == style then
      if indexOf(groups[other], key) ~= nil then
        inOther[#inOther + 1] = key
      elseif indexOf(groups[groupName], key) == nil then
        notShown[#notShown + 1] = key
      end
    end
  end
  return {
    { title = "Not shown", keys = notShown },
    { title = GROUP_TITLES[other], keys = inOther },
  }
end

return editor
