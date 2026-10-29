-- Draws the HUD from display models. Each element constructor returns { layer, update(model), setLook(look),
-- bounds }: setLook takes a src/style look, returns at once for the look the element shows, and returns whether
-- its bounds changed; bounds is the shown { x, y, w, h } inside the layer. place() positions a layer on the game
-- window and arrange() places every element from saved positions and anchors.
local aurarow = require("src/aurarow")
local castbar = require("src/castbar")
local cooldowngroup = require("src/cooldowngroup")
local draw = require("src/draw")
local layout = require("src/layout")
local resourcebar = require("src/resourcebar")
local savedgroups = require("src/savedgroups")
local tooltip = require("src/tooltip")
local unitframe = require("src/unitframe")

local view = {}

view.tooltip = tooltip.create
view.playerFrame = unitframe.player
view.targetFrame = unitframe.target
view.resourceBar = resourcebar.create
view.castBar = castbar.create
view.cooldownGroup = cooldowngroup.create
view.auraRow = aurarow.create
view.AURA_STYLES = aurarow.STYLES

-- at: { x, y, anchorX, anchorY }, with anchors as fractions of the game window.
function view.place(layer, at)
  draw.place(layer, at.x, at.y, at.anchorX, at.anchorY)
end

-- Every cooldown group's element name, built-in then custom.
local GROUP_NAMES = {}
view.GROUP_NAMES = GROUP_NAMES
for _, group in ipairs(savedgroups.GROUPS) do
  GROUP_NAMES[#GROUP_NAMES + 1] = group.name
end
for _, name in ipairs(savedgroups.CUSTOM_GROUPS) do
  GROUP_NAMES[#GROUP_NAMES + 1] = name
end

-- The side of the resource bar, "top" or "bottom", that faces the shown cooldown group nearest it at resolved
-- positions, or nil with no group shown. It measures from the bar itself, which turning the strip leaves still.
local function stripSide(elements, resolved)
  local bar = layout.rect(resolved.resource, elements.resource.bounds)
  local barMid = resolved.resource.y + elements.resource.middle
  local nearest = nil
  local side = nil
  for _, name in ipairs(GROUP_NAMES) do
    local group = elements[name]
    if group ~= nil and group.inUse and group.bounds.w > 0 then
      local r = layout.rect(resolved[name], group.bounds)
      local dx = r.x + r.w / 2 - (bar.x + bar.w / 2)
      local dy = r.y + r.h / 2 - barMid
      local distance = dx * dx + dy * dy
      if nearest == nil or distance < nearest then
        nearest = distance
        side = dy < 0 and "top" or "bottom"
      end
    end
  end
  return side
end

-- Places elements, by name, at positions resolved from src/layout anchors against their bounds, with the
-- resource bar's strip turned to the nearest cooldown group. Called at load and on a tick where a
-- cooldown row's bounds changed. Returns the resolved positions.
function view.arrange(elements, positions, anchors)
  local bounds = {}
  for name, element in pairs(elements) do
    bounds[name] = element.bounds
  end
  local resolved = layout.resolve(positions, anchors, bounds)
  local bar = elements.resource
  if bar ~= nil and bar.faceStrip(stripSide(elements, resolved)) then
    resolved = layout.resolve(positions, anchors, bounds)
  end
  for name, element in pairs(elements) do
    view.place(element.layer, resolved[name])
  end
  return resolved
end

-- Lets view.hold hide and view.fade fade every element, by name: the world map hides the HUD, and the Out of
-- combat setting fades or hides it.
function view.holdable(elements)
  for _, element in pairs(elements) do
    draw.holdable(element.layer)
  end
end

-- Hides every view.holdable element while held is true, and shows each as it was once false.
view.hold = draw.hold

-- Draws every view.holdable element at level, from 0 to 1, of its own opacity.
view.fade = draw.fade

-- Gives each element its look; returns whether any element's bounds changed.
function view.setLook(elements, look)
  local moved = false
  for _, element in pairs(elements) do
    if element.setLook(look) then
      moved = true
    end
  end
  return moved
end

return view
