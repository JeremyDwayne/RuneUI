-- Edit mode's anchor menu: a dashed sketch of the target element with a spot on each side for each alignment,
-- opened at the cursor once an element to anchor to is picked.
local draw = require("src/draw")
local layout = require("src/layout")

local anchormenu = {}

local set = draw.set
local rect = draw.rect
local text = draw.text
local hitArea = draw.hitArea
local on = draw.on
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS

local MENU_W = 220
local MENU_H = 166
-- The target's sketch, and the 24 by 16 spots around it.
local SKETCH_X = 60
local SKETCH_Y = 46
local SKETCH_W = 100
local SKETCH_H = 56
local SPOT_W = 24
local SPOT_H = 16
local SIDE_LABELS = { left = "Left side", right = "Right side", top = "Top side", bottom = "Bottom side" }

-- Spots: a column of three beside each of the sketch's left and right sides, a row of three above and below it.
local SPOTS = {}
for _, side in ipairs({ "left", "right", "top", "bottom" }) do
  for i, align in ipairs(layout.ALIGNS[side]) do
    local spot = { side = side, align = align, label = SIDE_LABELS[side] .. ", " .. align }
    if side == "left" or side == "right" then
      spot.x = side == "left" and SKETCH_X - 6 - SPOT_W or SKETCH_X + SKETCH_W + 6
      spot.y = SKETCH_Y + (i - 1) * 20
    else
      spot.x = SKETCH_X + (i - 1) * 38
      spot.y = side == "top" and SKETCH_Y - 6 - SPOT_H or SKETCH_Y + SKETCH_H + 6
    end
    SPOTS[#SPOTS + 1] = spot
  end
end

-- deps: { hover(spot) with the hovered { side, align }, or nil once the cursor leaves it; choose(spot) when a
-- spot is clicked }. Returns { open(title, targetName), close(), destroy() }: open names the menu and the
-- sketch and shows the menu at the cursor, kept inside root.
function anchormenu.create(root, deps)
  local menu = draw.new(ui.Layer, root)
  menu:SetSize(MENU_W, MENU_H)
  rect(menu, COLOURS.border, 0, 0, MENU_W, MENU_H)
  hitArea(rect(menu, COLOURS.popup, 1, 1, MENU_W - 2, MENU_H - 2))
  local title = text(menu, FONTS.small, ui.AlignMode.TOPLEFT, 8, 4, MENU_W - 16, 16)
  set(title, "rgb", COLOURS.dimText)
  local sketch = draw.new(ui.Canvas, menu)
  sketch:SetPos(SKETCH_X, SKETCH_Y)
  sketch:SetSize(SKETCH_W, SKETCH_H)
  draw.dashedBox(sketch, SKETCH_W, SKETCH_H, 1, draw.opaque(COLOURS.dimText))
  local sketchName = text(menu, FONTS.small, ui.AlignMode.CENTRE, SKETCH_X, SKETCH_Y, SKETCH_W, SKETCH_H)
  set(sketchName, "rgb", COLOURS.dimText)
  local spotName = text(menu, FONTS.small, ui.AlignMode.CENTRE, 8, MENU_H - 28, MENU_W - 16, 20)
  local spots = {}
  set(menu, "hidden", true)

  -- Lights the hovered spot, names it under the sketch and tells deps.hover.
  local function hoverSpot(spot, hovered)
    for _, s in ipairs(spots) do
      local hot = hovered and s == spot
      set(s.edge, "rgb", hot and COLOURS.border or COLOURS.spotEdge)
      set(s.fill, "rgb", hot and COLOURS.chip or COLOURS.button)
    end
    set(spotName, "content", hovered and spot.label or "")
    deps.hover(hovered and spot or nil)
  end

  for _, spot in ipairs(SPOTS) do
    local s = {
      label = spot.label,
      side = spot.side,
      align = spot.align,
      edge = hitArea(rect(menu, COLOURS.spotEdge, spot.x, spot.y, SPOT_W, SPOT_H)),
      fill = rect(menu, COLOURS.button, spot.x + 1, spot.y + 1, SPOT_W - 2, SPOT_H - 2),
    }
    on(s.edge, "ONMOUSEOVER", function()
      hoverSpot(s, true)
    end)
    on(s.edge, "ONMOUSELEAVE", function()
      hoverSpot(s, false)
    end)
    on(s.edge, "ONCLICK", function()
      deps.choose(s)
    end)
    spots[#spots + 1] = s
  end

  local m = {}

  function m.open(menuTitle, targetName)
    set(title, "content", menuTitle)
    set(sketchName, "content", targetName)
    hoverSpot(nil, false)
    local mx, my = draw.cursor()
    local w = tonumber(root.width)
    local h = tonumber(root.height)
    if mx ~= nil and w ~= nil and h ~= nil then
      menu:SetPos(math.max(0, math.min(mx, w - MENU_W)), math.max(0, math.min(my, h - MENU_H)))
    end
    set(menu, "hidden", false)
  end

  function m.close()
    set(menu, "hidden", true)
  end

  function m.destroy()
    menu:Destroy()
  end

  return m
end

return anchormenu
