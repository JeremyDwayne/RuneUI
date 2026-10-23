-- Edit mode: an outline over each HUD element's shown bounds that drags it with everything anchored to it,
-- an Anchor button on each outline that picks a target and a side from a diagram menu, snapping with guides
-- over a grid, and a toolbar with a snap toggle, Reset positions and Done.
local anchormenu = require("src/anchormenu")
local controls = require("src/controls")
local draw = require("src/draw")
local layout = require("src/layout")

local editmode = {}

local set = draw.set
local rect = draw.rect
local text = draw.text
local outline = draw.outline
local placeOutline = draw.placeOutline
local hitArea = draw.hitArea
local on = draw.on
local button = controls.button
local pressAt = draw.pressAt
local cursor = draw.cursor
local hideAll = draw.hideAll
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS

-- HUD elements in stacking order, later ones on top. Cooldown groups take their label from deps.label.
local ELEMENTS = {
  { name = "player", label = "Player" },
  { name = "target", label = "Target" },
  { name = "resource", label = "Resource bar" },
  { name = "castbar", label = "Cast bar" },
  { name = "major" },
  { name = "rotation" },
  { name = "utility" },
  { name = "custom1" },
  { name = "custom2" },
  { name = "custom3" },
  { name = "custom4" },
  { name = "targetDebuffs", label = "Target debuffs" },
  { name = "playerDebuffs", label = "Player debuffs" },
  { name = "upkeepBuffs", label = "Upkeep buffs" },
  { name = "combatBuffs", label = "Combat buffs" },
}
local LABELS = {}
for _, entry in ipairs(ELEMENTS) do
  LABELS[entry.name] = entry.label
end

-- Rough width of a small-font character, for sizing tags to their text.
local CHAR_W = 6
local TAG_H = 16
-- Elements shorter than this, or narrower than their tag and button, show both above their outline, and only
-- from hovering them until another element is hovered.
local HEADER_INSIDE_H = 40
local TOOLBAR_W = 600
local TOOLBAR_H = 44
local WHITE = draw.opaque(COLOURS.highlight)
-- Pixels within which a drag snaps, and the grid it falls back to, drawn with brighter lines every 64 px and a
-- teal line up the window's center. Canvas colours are 0xRRGGBBAA.
local SNAP_RANGE = 6
local GRID = 16
local GRID_MAJOR = 64
local GRID_RGBA = 0xFFFFFF12
local GRID_MAJOR_RGBA = 0xFFFFFF24
local GRID_CENTER_RGBA = (COLOURS.accent << 8) | 0x73

-- deps: { saved = src/settings, elements = src/view elements by name, view = src/view, label = function
-- returning a cooldown group's title by element name, reset = function asking to reset positions, done =
-- function run by the toolbar's Done }. Returns { open, close, editing, escape, placeAll, shutdown }; escape
-- handles Esc while editing. An element whose inUse is false, such as a custom group not added, gets no
-- overlay while editing.
function editmode.create(root, deps)
  local saved = deps.saved
  local elements = deps.elements

  local function labelOf(name)
    return LABELS[name] or (deps.label and deps.label(name)) or name
  end

  -- The text on an anchored element's button, such as "Rotation, right, bottom".
  local function anchorText(anchor)
    return labelOf(anchor.target) .. ", " .. anchor.side .. ", " .. anchor.align
  end

  local resolved = saved.positions()
  local overlays = {}
  -- move: the element being dragged; pick: { name, hover, target } while choosing what name anchors to.
  local move = nil
  local pick = nil
  -- The small element whose tag and button the shared header shows, or nil.
  local floatOwner = nil
  local refreshOverlays, pressOverlay, releaseOverlay, pressButton, hoverOverlay, dragTo
  -- The window's size in UI units, read on entering edit mode.
  local screenW = 0
  local screenH = 0

  -- The grid, drawn on entering edit mode with snapping on, and redrawn only when the window size changed.
  local grid = ui.Canvas.new(root)
  set(grid, "hidden", true)
  local gridW = nil
  local gridH = nil

  local function drawGrid()
    if gridW == screenW and gridH == screenH then
      return
    end
    gridW = screenW
    gridH = screenH
    grid:SetPos(0, 0)
    grid:SetSize(screenW, screenH)
    grid:Clear()
    local cx = screenW // 2
    for dx = GRID, cx, GRID do
      local rgba = dx % GRID_MAJOR == 0 and GRID_MAJOR_RGBA or GRID_RGBA
      grid:AddRectangle(cx - dx, 0, 1, screenH, rgba)
      grid:AddRectangle(cx + dx, 0, 1, screenH, rgba)
    end
    for dy = GRID, screenH, GRID do
      grid:AddRectangle(0, screenH - dy, screenW, 1, dy % GRID_MAJOR == 0 and GRID_MAJOR_RGBA or GRID_RGBA)
    end
    grid:AddRectangle(cx, 0, 1, screenH, GRID_CENTER_RGBA)
  end

  -- Dims the HUD under the overlays while picking.
  local dim = hitArea(rect(root, COLOURS.border, 0, 0, 0, 0))
  set(dim, "alpha", 0.5)
  set(dim, "hidden", true)

  -- Sizes o's tag to its element's current label and moves its button beside it.
  local function showLabel(o)
    o.label = labelOf(o.name)
    o.tagW = #o.label * CHAR_W + 10
    set(o.tag, "content", o.label)
    draw.size(o.tagBg, o.tagW, TAG_H)
    draw.size(o.tag, o.tagW - 5, TAG_H)
    draw.pos(o.button, 2 + o.tagW, 2)
    draw.pos(o.buttonText, 8 + o.tagW, 2)
  end

  local function overlay(entry, element)
    local o = { name = entry.name, element = element }
    o.layer = ui.Layer.new(root)
    o.tint = hitArea(rect(o.layer, COLOURS.accent, 0, 0, 0, 0))
    o.edge = outline(o.layer, COLOURS.accent, 2)
    o.tagBg = rect(o.layer, COLOURS.accent, 2, 2, 0, TAG_H)
    o.tag = text(o.layer, FONTS.small, ui.AlignMode.TOPLEFT, 7, 2, 0, TAG_H)
    set(o.tag, "rgb", COLOURS.accentText)
    set(o.tag, "isShadowed", false)
    o.button = hitArea(rect(o.layer, COLOURS.panel, 0, 2, 0, TAG_H))
    o.buttonText = text(o.layer, FONTS.small, ui.AlignMode.TOPLEFT, 0, 2, 200, TAG_H)
    -- The tag and button, and the header's width with the button's current text.
    o.header = { o.tagBg, o.tag, o.button, o.buttonText }
    o.buttonW = #"Anchor" * CHAR_W + 12
    showLabel(o)
    on(o.tint, "ONCLICK", function(_, x)
      pressOverlay(o, x)
    end)
    on(o.tint, "ONRELEASE", function()
      releaseOverlay(o)
    end)
    on(o.tint, "ONMOUSEOVER", function()
      hoverOverlay(o, true)
    end)
    on(o.tint, "ONMOUSELEAVE", function()
      hoverOverlay(o, false)
    end)
    on(o.button, "ONCLICK", function()
      pressButton(o)
    end)
    set(o.layer, "hidden", true)
    return o
  end

  for _, entry in ipairs(ELEMENTS) do
    local element = elements[entry.name]
    if element ~= nil then
      overlays[entry.name] = overlay(entry, element)
    end
  end

  -- One header for small elements, built after every overlay so it draws above them all and its button takes
  -- the click. It sits above the last small element hovered.
  local float = ui.Layer.new(root)
  local floatTagBg = rect(float, COLOURS.accent, 0, 0, 0, TAG_H)
  local floatTag = text(float, FONTS.small, ui.AlignMode.TOPLEFT, 5, 0, 200, TAG_H)
  set(floatTag, "rgb", COLOURS.accentText)
  set(floatTag, "isShadowed", false)
  local floatButton = hitArea(rect(float, COLOURS.panel, 0, 0, 0, TAG_H))
  local floatButtonText = text(float, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, 200, TAG_H)
  on(floatButton, "ONCLICK", function()
    pressButton(floatOwner)
  end)
  set(float, "hidden", true)

  -- Shows the shared header above floatOwner when it is small and placed, with its tag and button text.
  local function placeFloat()
    local o = floatOwner
    local shown = o ~= nil and o.small and o.at ~= nil
    set(float, "hidden", not shown)
    if not shown then
      return
    end
    local b = o.element.bounds
    draw.place(float, o.at.x + b.x, o.at.y + b.y - TAG_H - 2, o.at.anchorX, o.at.anchorY)
    draw.size(float, o.tagW + o.buttonW, TAG_H)
    draw.size(floatTagBg, o.tagW, TAG_H)
    set(floatTag, "content", o.label)
    draw.pos(floatButton, o.tagW, 0)
    draw.size(floatButton, o.buttonW, TAG_H)
    set(floatButton, "rgb", o.buttonFill or COLOURS.panel)
    draw.pos(floatButtonText, o.tagW + 6, 0)
    set(floatButtonText, "content", o.buttonContent or "Anchor")
    set(floatButtonText, "rgb", o.buttonFill == COLOURS.chip and COLOURS.accentText or COLOURS.text)
    set(floatButtonText, "isShadowed", o.buttonFill ~= COLOURS.chip)
  end

  -- Dashed outlines over the picking element and where the chosen spot would put it, and a guide line across
  -- the window on each axis a drag snapped.
  local pickOutline = ui.Canvas.new(root)
  local landing = ui.Canvas.new(root)
  local guideX = rect(root, COLOURS.accent, 0, 0, 1, 0)
  local guideY = rect(root, COLOURS.accent, 0, 0, 0, 1)
  hideAll({ pickOutline, landing, guideX, guideY }, true)

  -- Shows the guides at x and y from the window's bottom center, hiding each that is nil.
  local function showGuides(x, y)
    set(guideX, "hidden", x == nil)
    set(guideY, "hidden", y == nil)
    if x ~= nil then
      draw.place(guideX, x, -screenH, 0.5, 1)
      draw.size(guideX, 1, screenH)
    end
    if y ~= nil then
      draw.place(guideY, -screenW // 2, y, 0.5, 1)
      draw.size(guideY, screenW, 1)
    end
  end

  -- Places o over its element at pos, sized to the element's shown bounds. The layer clips what it holds, so
  -- an element too small for its tag and button hides them and uses the shared header above it.
  local function placeOverlay(o, pos)
    local b = o.element.bounds
    o.at = pos
    o.small = b.h < HEADER_INSIDE_H or b.w < o.tagW + o.buttonW + 4
    draw.place(o.layer, pos.x + b.x, pos.y + b.y, pos.anchorX, pos.anchorY)
    draw.size(o.layer, b.w, b.h)
    draw.size(o.tint, b.w, b.h)
    placeOutline(o.edge, 2, 2, math.max(0, b.w - 4), math.max(0, b.h - 4))
    hideAll(o.header, o.small)
    if o == floatOwner then
      placeFloat()
    end
  end

  -- Places every element and overlay at r, positions by name.
  local function placeAt(r)
    for name, o in pairs(overlays) do
      deps.view.place(elements[name].layer, r[name])
      placeOverlay(o, r[name])
    end
  end

  -- Draws a dashed box of w by h on canvas at x, y from the window's bottom center.
  local function dashedAt(canvas, x, y, w, h)
    draw.place(canvas, x, y, 0.5, 1)
    draw.size(canvas, w, h)
    draw.dashedBox(canvas, w, h, 2, WHITE)
    set(canvas, "hidden", false)
  end

  local function rectOf(name)
    return layout.rect(resolved[name], elements[name].bounds)
  end

  local mode = {}

  -- Places every element and its overlay from the saved positions and anchors, keeping a drag under way at the
  -- cursor. main.lua calls it on a tick where a cooldown row's bounds changed.
  function mode.placeAll()
    resolved = deps.view.arrange(elements, saved.positions(), saved.anchors())
    for name, o in pairs(overlays) do
      placeOverlay(o, resolved[name])
    end
    if move ~= nil and move.to ~= nil then
      dragTo(move.cursorX, move.cursorY)
    end
    if pick ~= nil then
      local r = rectOf(pick.name)
      dashedAt(pickOutline, r.x, r.y, r.w, r.h)
    end
  end

  -- Toolbar: Edit mode with Reset positions and Done, or the pick prompt with Cancel.
  local toolbar = ui.Layer.new(root)
  toolbar:SetSize(TOOLBAR_W, TOOLBAR_H)
  toolbar:SetPos(-TOOLBAR_W // 2, 14, 0.5, 0)
  rect(toolbar, COLOURS.border, 0, 0, TOOLBAR_W, TOOLBAR_H)
  hitArea(rect(toolbar, COLOURS.panel, 1, 1, TOOLBAR_W - 2, TOOLBAR_H - 2))
  local title = text(toolbar, FONTS.body, ui.AlignMode.TOPLEFT, 14, 1, 80, TOOLBAR_H - 2)
  set(title, "content", "Edit mode")
  local snapToggle = hitArea(rect(toolbar, COLOURS.button, 98, 7, 86, 30))
  local snapLabel = text(toolbar, FONTS.body, ui.AlignMode.CENTRE, 98, 7, 86, 30)
  local shiftHint = text(toolbar, FONTS.small, ui.AlignMode.TOPLEFT, 196, 1, 190, TOOLBAR_H - 2)
  set(shiftHint, "content", "Hold Shift to move freely")
  set(shiftHint, "rgb", COLOURS.dimText)
  local prompt = text(toolbar, FONTS.body, ui.AlignMode.TOPLEFT, 14, 1, 380, TOOLBAR_H - 2)
  local escHint = text(toolbar, FONTS.small, ui.AlignMode.TOPLEFT, 400, 1, 100, TOOLBAR_H - 2)
  set(escHint, "content", "Esc cancels")
  set(escHint, "rgb", COLOURS.dimText)
  set(toolbar, "hidden", true)

  local editing = false
  local setEditing, cancelPick
  local reset = button(toolbar, "Reset positions", TOOLBAR_W - 206, 7, 120, 30, false, deps.reset)
  local done = button(toolbar, "Done", TOOLBAR_W - 79, 7, 72, 30, "accent", function()
    setEditing(false)
    deps.done()
  end)
  local cancel = button(toolbar, "Cancel", TOOLBAR_W - 91, 7, 84, 30, false, function()
    cancelPick()
  end)

  local function showToolbar()
    local picking = pick ~= nil
    hideAll({ title, snapToggle, snapLabel, shiftHint, reset.bg, reset.label, done.bg, done.label }, picking)
    hideAll({ prompt, escHint, cancel.bg, cancel.label }, not picking)
  end

  -- The snap toggle reads Snap on in light chip colours or Snap off as a plain button, and the grid shows only
  -- while snapping is on.
  local function showSnap()
    local snap = saved.snap()
    set(snapToggle, "rgb", snap and COLOURS.chip or COLOURS.button)
    set(snapLabel, "content", snap and "Snap on" or "Snap off")
    set(snapLabel, "rgb", snap and COLOURS.accentText or COLOURS.text)
    set(snapLabel, "isShadowed", not snap)
    if snap and editing then
      drawGrid()
    end
    set(grid, "hidden", not (snap and editing))
  end

  on(snapToggle, "ONCLICK", function()
    saved.setSnap(not saved.snap())
    showSnap()
  end)

  -- The anchor menu, opened once the picking element has a target. Hovering a spot shows a dashed landing
  -- outline where the element would sit; clicking one saves the anchor.
  local menu = anchormenu.create(root, {
    hover = function(spot)
      set(landing, "hidden", spot == nil)
      if spot == nil or pick == nil or pick.target == nil then
        return
      end
      local b = elements[pick.name].bounds
      local anchor = { side = spot.side, align = spot.align, gap = 0, offset = 0 }
      local x, y = layout.place(anchor, rectOf(pick.target), b.w, b.h)
      dashedAt(landing, x, y, b.w, b.h)
    end,
    choose = function(spot)
      if pick == nil or pick.target == nil then
        return
      end
      saved.setAnchor(pick.name, { target = pick.target, side = spot.side, align = spot.align, gap = 0, offset = 0 })
      cancelPick()
      mode.placeAll()
    end,
  })

  local function closeMenu()
    menu.close()
    set(landing, "hidden", true)
    if pick ~= nil then
      pick.target = nil
    end
  end

  local function openMenu(target)
    pick.target = target
    menu.open("Anchor " .. labelOf(pick.name) .. " to " .. labelOf(target), labelOf(target))
  end

  -- Overlay looks: a teal tint and outline, white and dashed while picking, white when hovered as a target.
  -- Each button reads Anchor, Picking, or the anchor it holds.
  function refreshOverlays()
    local anchors = saved.anchors()
    for name, o in pairs(overlays) do
      local isPicking = pick ~= nil and pick.name == name
      local hovered = pick ~= nil and pick.hover == name
      set(o.tint, "rgb", (isPicking or hovered) and COLOURS.highlight or COLOURS.accent)
      local alpha = 0.15
      if isPicking then
        alpha = 0.08
      elseif hovered then
        alpha = 0.14
      end
      set(o.tint, "alpha", alpha)
      hideAll(o.edge, isPicking)
      for _, side in ipairs(o.edge) do
        set(side, "rgb", hovered and COLOURS.highlight or COLOURS.accent)
      end
      local content = "Anchor"
      local fill = COLOURS.panel
      if isPicking then
        content = "Picking"
        fill = COLOURS.highlight
      elseif anchors[name] ~= nil then
        content = anchorText(anchors[name])
        fill = COLOURS.chip
      end
      showLabel(o)
      set(o.buttonText, "content", content)
      set(o.buttonText, "rgb", fill == COLOURS.panel and COLOURS.text or COLOURS.accentText)
      set(o.buttonText, "isShadowed", fill == COLOURS.panel)
      set(o.button, "rgb", fill)
      o.buttonContent = content
      o.buttonFill = fill
      o.buttonW = #content * CHAR_W + 12
      draw.size(o.button, o.buttonW, TAG_H)
      if resolved[name] ~= nil then
        placeOverlay(o, resolved[name])
      end
    end
  end

  local function startPick(o)
    pick = { name = o.name }
    set(prompt, "content", "Click the element to anchor " .. labelOf(o.name) .. " to")
    draw.size(dim, tonumber(root.width) or 0, tonumber(root.height) or 0)
    set(dim, "hidden", false)
    local r = rectOf(o.name)
    dashedAt(pickOutline, r.x, r.y, r.w, r.h)
    showToolbar()
    refreshOverlays()
  end

  function cancelPick()
    if pick == nil then
      return
    end
    closeMenu()
    pick = nil
    hideAll({ dim, pickOutline }, true)
    showToolbar()
    refreshOverlays()
  end

  -- Opens the menu for target o, or says why the picking element cannot anchor to it.
  local function choose(o)
    if not layout.canAnchor(saved.anchors(), pick.name, o.name) then
      closeMenu()
      local reason = o.name == pick.name and (labelOf(o.name) .. " cannot anchor to itself")
        or (labelOf(o.name) .. " is anchored to " .. labelOf(pick.name))
      set(prompt, "content", reason)
      return
    end
    openMenu(o.name)
  end

  function pressButton(o)
    if pick ~= nil then
      if pick.name == o.name then
        cancelPick()
      else
        choose(o)
      end
    elseif saved.anchors()[o.name] ~= nil then
      saved.setPosition(o.name, resolved[o.name])
      saved.removeAnchor(o.name)
      refreshOverlays()
    else
      startPick(o)
    end
  end

  function hoverOverlay(o, hovered)
    if hovered and floatOwner ~= o then
      floatOwner = o
      placeFloat()
    end
    if pick == nil or pick.name == o.name then
      return
    end
    if hovered then
      pick.hover = o.name
    elseif pick.hover == o.name then
      pick.hover = nil
    end
    refreshOverlays()
  end

  -- A press starts dragging o's element with everything anchored to it; the drag re-resolves anchors with o's
  -- own anchor set aside, so o follows the cursor.
  function pressOverlay(o, x)
    if pick ~= nil then
      choose(o)
      return
    end
    pressAt(o.tint, x)
    local mx, my = cursor()
    if mx == nil then
      return
    end
    local positions = {}
    local free = {}
    local bounds = {}
    for name, pos in pairs(resolved) do
      positions[name] = pos
    end
    for name, anchor in pairs(saved.anchors()) do
      if name ~= o.name then
        free[name] = anchor
      end
    end
    local rects = {}
    for name, element in pairs(elements) do
      bounds[name] = element.bounds
      if element.inUse ~= false then
        rects[name] = rectOf(name)
      end
    end
    -- The window snaps like an element, so its edges and center lines win over the grid.
    local targets = layout.snapTargets(rects, saved.anchors(), o.name)
    targets[#targets + 1] = { x = -screenW // 2, y = -screenH, w = screenW, h = screenH }
    move = {
      name = o.name,
      startX = mx,
      startY = my,
      from = resolved[o.name],
      positions = positions,
      free = free,
      bounds = bounds,
      targets = targets,
    }
  end

  -- Ends a move without saving, putting everything back where it was.
  local function cancelMove()
    if move == nil then
      return
    end
    move = nil
    showGuides(nil, nil)
    mode.placeAll()
  end

  -- Dropping saves the dragged element's position, or its new gap and offset when it is anchored.
  function releaseOverlay(o)
    if move == nil or move.name ~= o.name then
      return
    end
    local to = move.to
    local anchor = saved.anchors()[o.name]
    move = nil
    showGuides(nil, nil)
    if to == nil then
      return
    end
    if anchor ~= nil then
      local captured =
        layout.capture(layout.rect(to, o.element.bounds), rectOf(anchor.target), anchor.side, anchor.align)
      captured.target = anchor.target
      saved.setAnchor(o.name, captured)
    else
      saved.setPosition(o.name, to)
    end
    mode.placeAll()
  end

  function setEditing(enabled)
    editing = enabled
    if not enabled then
      cancelPick()
      cancelMove()
    end
    for _, o in pairs(overlays) do
      set(o.layer, "hidden", not enabled or o.element.inUse == false)
    end
    floatOwner = nil
    placeFloat()
    set(toolbar, "hidden", not enabled)
    if enabled then
      screenW = tonumber(root.width) or 0
      screenH = tonumber(root.height) or 0
      showToolbar()
      refreshOverlays()
    end
    showSnap()
  end

  function mode.open()
    setEditing(true)
  end
  function mode.close()
    setEditing(false)
  end
  function mode.editing()
    return editing
  end

  -- Esc cancels a pick, or leaves edit mode.
  function mode.escape()
    if pick ~= nil then
      cancelPick()
    else
      setEditing(false)
    end
  end

  -- Shift as its key events report it; Keyboard.IsShiftDown reads false inside Event.Logic.
  local shiftHeld = false
  Event.KeyDown.Subscribe("runeuiEditModeShift", function(e)
    if e.gameKey == GameKey.SHIFT then
      shiftHeld = true
    end
  end)
  Event.KeyUp.Subscribe("runeuiEditModeShift", function(e)
    if e.gameKey == GameKey.SHIFT then
      shiftHeld = false
    end
  end)

  -- Places the dragged element for the cursor at mx, my in whole UI units with its chain, snapping unless
  -- snapping is off or Shift is held.
  function dragTo(mx, my)
    move.cursorX = mx
    move.cursorY = my
    local from = move.from
    local x = math.floor(from.x + mx - move.startX + 0.5)
    local y = math.floor(from.y + my - move.startY + 0.5)
    local lineX = nil
    local lineY = nil
    if saved.snap() and not shiftHeld then
      local b = move.bounds[move.name]
      local snapped = layout.snap({ x = x + b.x, y = y + b.y, w = b.w, h = b.h }, move.targets, SNAP_RANGE, GRID)
      x = snapped.x - b.x
      y = snapped.y - b.y
      lineX = snapped.guideX
      lineY = snapped.guideY
    end
    showGuides(lineX, lineY)
    move.to = { x = x, y = y, anchorX = from.anchorX, anchorY = from.anchorY }
    move.positions[move.name] = move.to
    placeAt(layout.resolve(move.positions, move.free, move.bounds))
  end

  -- Moves the drag with the cursor. It runs every frame through Event.Draw so a move keeps up with the mouse,
  -- and on Event.Logic as well in case Draw does not fire. It returns before reading the mouse unless a move is
  -- under way, and before drawing unless the cursor moved.
  local lastX = nil
  local lastY = nil
  local function followCursor()
    if move == nil then
      return
    end
    local mx, my = cursor()
    if mx == nil or (mx == lastX and my == lastY) then
      return
    end
    lastX = mx
    lastY = my
    dragTo(mx, my)
  end
  Event.Draw.Subscribe("runeuiEditMode", followCursor)
  Event.Logic.Subscribe("runeuiEditMode", followCursor)

  function mode.shutdown()
    toolbar:Destroy()
    menu.destroy()
    dim:Destroy()
    pickOutline:Destroy()
    grid:Destroy()
    guideX:Destroy()
    guideY:Destroy()
    landing:Destroy()
    for _, o in pairs(overlays) do
      o.layer:Destroy()
    end
    float:Destroy()
  end

  return mode
end

return editmode
