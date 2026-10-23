-- Draws the HUD from display models. Each element constructor returns { layer, update(model), setLook(look),
-- width, height, bounds }: setLook takes a src/style look, returns at once for the look the element shows,
-- and returns whether its bounds changed; bounds is the shown { x, y, w, h } inside the layer. place()
-- positions a layer on the game window and arrange() places every element from saved positions and anchors.
local aurarow = require("src/aurarow")
local castbar = require("src/castbar")
local cooldowngroup = require("src/cooldowngroup")
local draw = require("src/draw")
local layout = require("src/layout")
local resourcebar = require("src/resourcebar")
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

-- Places elements, by name, at positions resolved from src/layout anchors against their bounds. Called at
-- load and on a tick where a cooldown row's bounds changed. Returns the resolved positions.
function view.arrange(elements, positions, anchors)
  local bounds = {}
  for name, element in pairs(elements) do
    bounds[name] = element.bounds
  end
  local resolved = layout.resolve(positions, anchors, bounds)
  for name, element in pairs(elements) do
    view.place(element.layer, resolved[name])
  end
  return resolved
end

-- Lets view.hold hide every element, by name, while a game window the HUD draws over is open.
function view.holdable(elements)
  for _, element in pairs(elements) do
    draw.holdable(element.layer)
  end
end

-- Hides every view.holdable element while held is true, and shows each as it was once false.
view.hold = draw.hold

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
