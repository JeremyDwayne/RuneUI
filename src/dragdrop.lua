-- Dragging icons in the options window, shared by the cooldown editor and the Buffs page. A press on an
-- icon's hit area starts a drag once the cursor travels a few pixels; a half-size ghost follows the cursor.
-- The client releases a press as soon as the cursor leaves the pressed component, so while dragging the
-- hit area turns transparent and grows into a large square centred on the cursor, which a fast move between
-- frames cannot leave.
local draw = require("src/draw")

local dragdrop = {}

-- Pixels the cursor must travel after a press before it counts as a drag.
local DRAG_START = 3
-- Side of the transparent grab area that follows the cursor during a drag.
local GRAB = 160
local GHOST_OFFSET = 8

-- layer: where the icons and the ghost live; positions are in its coordinates. ghostSize: the ghost's side.
-- handlers: press(item) runs on a press and returns whether the item holds an icon to drag; ghost(item)
-- returns a src/cooldowns-style tile { icon, initials } for the ghost; start(item) when a drag begins;
-- move(item, x, y) as the cursor moves; drop(item, x, y) on release after dragging; click(item) on release
-- without dragging; finish(item) after either, or on a cancel. Items have edge, their hit area, x and y, where
-- edge sits, and size, its side. Returns { attach(item), follow(), cancel(), dragging() }: follow runs every
-- frame and returns before reading the mouse unless a press is held.
function dragdrop.create(layer, ghostSize, handlers)
  local ghost = draw.group()
  local ghostIcon = ghost.add(ui.Sprite.new(layer), 0, 0)
  local ghostInitials = ghost.add(draw.text(layer, draw.FONTS.small, ui.AlignMode.CENTRE, 0, 0, ghostSize,
    ghostSize), 0, 0)
  ghostIcon:SetSize(ghostSize, ghostSize)
  draw.set(ghostIcon, "alpha", 0.7)
  ghost.set("hidden", true)

  local press = nil
  -- The cursor's offset from layer coordinates, measured on each press.
  local origin = { x = 0, y = 0 }
  local lastX, lastY = nil, nil

  local d = {}

  -- Ends a press: the hit area returns to its icon and the ghost hides.
  local function release()
    local p = press
    press = nil
    local item = p.item
    draw.pos(item.edge, item.x, item.y)
    draw.size(item.edge, item.size, item.size)
    draw.set(item.edge, "alpha", 1)
    ghost.set("hidden", true)
    return p
  end

  function d.cancel()
    if press ~= nil then handlers.finish(release().item) end
  end

  function d.dragging()
    return press ~= nil and press.moved
  end

  function d.attach(item)
    draw.on(item.edge, "ONCLICK", function(_, x, y)
      if not handlers.press(item) then return end
      draw.pressAt(item.edge, x)
      local mx, my = draw.cursor()
      if mx == nil then return end
      origin.x, origin.y = mx - (item.x + x), my - (item.y + y)
      press = { item = item, startX = mx, startY = my, moved = false }
      lastX, lastY = nil, nil
    end)
    draw.on(item.edge, "ONRELEASE", function()
      if press == nil or press.item ~= item then return end
      local mx, my = draw.cursor()
      local p = release()
      if not p.moved then
        handlers.click(item)
      elseif mx ~= nil then
        handlers.drop(item, mx - origin.x, my - origin.y)
      end
      handlers.finish(item)
    end)
  end

  function d.follow()
    if press == nil then return end
    local mx, my = draw.cursor()
    if mx == nil or (mx == lastX and my == lastY) then return end
    lastX, lastY = mx, my
    local item = press.item
    if not press.moved then
      if math.abs(mx - press.startX) + math.abs(my - press.startY) <= DRAG_START then return end
      press.moved = true
      handlers.start(item)
      draw.set(item.edge, "alpha", 0)
      draw.size(item.edge, GRAB, GRAB)
      draw.iconOrInitials(ghostIcon, ghostInitials, handlers.ghost(item))
    end
    local x, y = mx - origin.x, my - origin.y
    draw.pos(item.edge, x - GRAB // 2, y - GRAB // 2)
    ghost.place(x + GHOST_OFFSET, y + GHOST_OFFSET)
    handlers.move(item, x, y)
  end

  return d
end

return dragdrop
