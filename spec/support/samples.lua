-- Sample models and elements the HUD element specs share: ready cooldown tiles, a configured cooldown group, a
-- combat buffs row, the Asphyxiate channel, a combat buff with time left, a look from the default appearance
-- with changes, and ways to find a bar's marks and strip and a label among the fake's components.
local fake = require("spec/support/fake_ui")
local draw = require("src/draw")
local savedappearance = require("src/savedappearance")
local style = require("src/style")
local view = require("src/view")

local samples = {}

-- n ready tiles for a cooldown group.
function samples.readyTiles(n)
  local out = {}
  for i = 1, n do
    out[i] = { key = "K" .. i, name = "Tile " .. i, initials = "T" .. i, ready = true }
  end
  return out
end

-- A cooldown group with display settings of size px tiles, perRow to a row, growing in grow.
function samples.group(size, perRow, grow, root, tooltip)
  local g = view.cooldownGroup(root or fake.component(), tooltip or view.tooltip(fake.component()))
  g.configure({ size = size or 36, perRow = perRow or 7, grow = grow or "down" })
  return g
end

-- A combat buffs row whose tooltip names nothing.
function samples.auraRow()
  return view.auraRow(fake.component(), view.AURA_STYLES.combatBuffs, view.tooltip(fake.component()), function()
    return {}
  end)
end

-- The src/channel model of Asphyxiate, 7 ticks long, with ticksLeft of them left.
function samples.asphyxiate(start, ticksLeft)
  return {
    start = start or 227269,
    name = "Asphyxiate",
    icon = 14660,
    duration = 4.2,
    ticksLeft = ticksLeft or 7,
    hits = { 0, 1.2, 2.4, 3.6 },
  }
end

-- The src/auras models of one 20 s combat buff with 5 stacks and left seconds left.
function samples.incite(left)
  return {
    {
      sprite = 14766,
      text = tostring(left),
      stacks = "5",
      left = left,
      full = 20,
      fill = left / 20,
      highlight = left <= 2,
    },
  }
end

-- A src/style look from the default appearance with changes.
function samples.look(changes)
  local appearance = {}
  for k, v in pairs(savedappearance.defaults()) do
    appearance[k] = v
  end
  for k, v in pairs(changes or {}) do
    appearance[k] = v
  end
  return style.look(appearance, nil)
end

-- Shown 1px bar marks on bar, as tall as the cast bar's fill unless height is given: { dark ones over the fill,
-- light ones ahead of it }.
function samples.marks(bar, height)
  local dark = 0
  local light = 0
  for _, c in ipairs(fake.created) do
    if fake.shown(c) and c.parent == bar.layer and c.width == 1 and c.height == (height or 20) then
      if c.rgb == draw.COLOURS.border then
        dark = dark + 1
      end
      if c.rgb == draw.COLOURS.highlight then
        light = light + 1
      end
    end
  end
  return { dark, light }
end

-- The adrenaline bar's strip track and gold fill.
function samples.strip(bar)
  local function part(rgb, height)
    for _, c in ipairs(fake.created) do
      if c.parent == bar.layer and c.rgb == rgb and c.height == height then
        return c
      end
    end
  end
  return part(draw.COLOURS.border, 5), part(draw.WINDOW.accent, 3)
end

-- The shown label reading content, or nil.
function samples.label(content)
  return fake.find(function(_, d)
    return d.content == content
  end)
end

return samples
