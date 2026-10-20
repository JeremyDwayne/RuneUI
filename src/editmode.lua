-- Edit mode: an outline over each HUD element that drags it, and a toolbar with Reset positions and Done.
local draw = require("src/draw")

local editmode = {}

local set, rect, text, outline, placeOutline = draw.set, draw.rect, draw.text, draw.outline, draw.placeOutline
local hitArea, on, button, pressAt, cursor = draw.hitArea, draw.on, draw.button, draw.pressAt, draw.cursor
local FONTS, COLOURS = draw.FONTS, draw.COLOURS

-- HUD elements in stacking order, later ones on top.
local ELEMENTS = {
  { name = "player", label = "Player" }, { name = "target", label = "Target" },
  { name = "resource", label = "Resource bar" }, { name = "rotation", label = "Rotation" },
  { name = "cooldowns", label = "Cooldowns" },
}

-- deps: { saved = src/settings, elements = src/view elements by name, view = src/view, reset = function
-- asking to reset positions, done = function run by the toolbar's Done }. Returns { open, close, editing,
-- escape, placeAll, shutdown }; escape handles Esc while editing.
function editmode.create(root, deps)
  local saved, elements = deps.saved, deps.elements
  local overlays = {}
  local move = nil

  local function overlay(name, label, element)
    local layer = ui.Layer.new(root)
    layer:SetSize(element.width, element.height)
    local tint = hitArea(rect(layer, COLOURS.accent, 0, 0, element.width, element.height))
    set(tint, "alpha", 0.15)
    placeOutline(outline(layer, COLOURS.accent, 2), 2, 2, element.width - 4, element.height - 4)
    rect(layer, COLOURS.accent, 2, 2, 96, 16)
    local tagText = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, 6, 2, 92, 16)
    set(tagText, "content", label)
    set(tagText, "rgb", COLOURS.accentText)
    set(tagText, "isShadowed", false)
    on(tint, "ONCLICK", function(_, x)
      pressAt(tint, x)
      local mx, my = cursor()
      if mx == nil then return end
      move = { name = name, startX = mx, startY = my, from = saved.positions()[name] }
    end)
    on(tint, "ONRELEASE", function()
      if move ~= nil and move.name == name then
        saved.setPosition(name, move.to or move.from)
        move = nil
      end
    end)
    set(layer, "hidden", true)
    return layer
  end

  for _, entry in ipairs(ELEMENTS) do
    local element = elements[entry.name]
    if element ~= nil then overlays[entry.name] = overlay(entry.name, entry.label, element) end
  end

  -- Ends a move without saving, putting the element back where it was.
  local function cancelMove()
    if move == nil then return end
    deps.view.place(elements[move.name].layer, move.from)
    deps.view.place(overlays[move.name], move.from)
    move = nil
  end

  local mode = {}

  -- Places every element and its overlay from the saved positions and anchors.
  function mode.placeAll()
    local positions = deps.view.arrange(elements, saved.positions(), saved.anchors())
    for name in pairs(elements) do deps.view.place(overlays[name], positions[name]) end
  end

  local toolbar = ui.Layer.new(root)
  toolbar:SetSize(400, 44)
  toolbar:SetPos(-200, 14, 0.5, 0)
  rect(toolbar, COLOURS.border, 0, 0, 400, 44)
  hitArea(rect(toolbar, COLOURS.panel, 1, 1, 398, 42))
  local toolbarTitle = text(toolbar, FONTS.body, ui.AlignMode.TOPLEFT, 14, 1, 120, 42)
  set(toolbarTitle, "content", "Edit mode")
  set(toolbar, "hidden", true)

  local editing = false

  local function setEditing(enabled)
    editing = enabled
    if not enabled then cancelMove() end
    for _, layer in pairs(overlays) do set(layer, "hidden", not enabled) end
    set(toolbar, "hidden", not enabled)
  end

  button(toolbar, "Reset positions", 160, 7, 140, 30, false, deps.reset)
  button(toolbar, "Done", 308, 7, 84, 30, "accent", function()
    setEditing(false)
    deps.done()
  end)

  function mode.open() setEditing(true) end
  function mode.close() setEditing(false) end
  function mode.editing() return editing end
  function mode.escape() setEditing(false) end

  -- Moves the element being placed with the cursor. It runs every frame through Event.Draw so a move keeps
  -- up with the mouse, and on Event.Logic as well in case Draw does not fire. It returns before reading the
  -- mouse unless a move is under way, and before drawing unless the cursor moved.
  local lastX, lastY = nil, nil
  local function followCursor()
    if move == nil then return end
    local mx, my = cursor()
    if mx == nil or (mx == lastX and my == lastY) then return end
    lastX, lastY = mx, my
    local from = move.from
    move.to = { x = from.x + mx - move.startX, y = from.y + my - move.startY,
      anchorX = from.anchorX, anchorY = from.anchorY }
    deps.view.place(elements[move.name].layer, move.to)
    deps.view.place(overlays[move.name], move.to)
  end
  Event.Draw.Subscribe("runeuiEditMode", followCursor)
  Event.Logic.Subscribe("runeuiEditMode", followCursor)

  function mode.shutdown()
    toolbar:Destroy()
    for _, layer in pairs(overlays) do layer:Destroy() end
  end

  return mode
end

return editmode
