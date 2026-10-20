-- The options window, its ribbon button and edit mode: a sidebar of pages, a cooldown
-- editor that mirrors both rows with a "+" picker, drag to swap or insert and a Remove menu, marker
-- steppers, appearance choices, and edit mode outlines for dragging HUD elements.
local draw = require("src/draw")
local editor = require("src/editor")
local settings = require("src/settings")

local options = {}

local set, rect, text, outline, placeOutline = draw.set, draw.rect, draw.text, draw.outline, draw.placeOutline
local hideAll = draw.hideAll
local FONTS, COLOURS = draw.FONTS, draw.COLOURS

local WIDTH, HEIGHT = 900, 620
local SIDEBAR, HEADER, FOOTER = 200, 64, 56
local PAGE_X, PAGE_Y = SIDEBAR + 1, HEADER + 1
local PAGE_W = WIDTH - PAGE_X - 1
-- Pixels the cursor must travel after a press before it counts as a drag.
local DRAG_START = 3
local MAX_TILES = 10
local GAP = 2
local PICKER_WIDTH, PICKER_ROW = 230, 26
local MARKER_STEP = 5
-- HUD elements in edit mode stacking order, later ones on top.
local ELEMENTS = {
  { name = "player", label = "Player" }, { name = "target", label = "Target" },
  { name = "resource", label = "Resource bar" }, { name = "rotation", label = "Rotation" },
  { name = "cooldowns", label = "Cooldowns" },
}

-- Makes c take clicks and stop them, like a button: plain components start enabled = false and
-- clickthrough = true, so a click reaches everything beneath and the game world. Each clickable thing has
-- one hit area at the bottom; components drawn over it keep the defaults and pass clicks down to it.
local function hitArea(c)
  set(c, "enabled", true)
  set(c, "clickthrough", false)
  return c
end

local function on(c, hook, fn)
  c:Subscribe(ui.Hook[hook], fn)
end

-- A flat button with a centred label that lightens on hover. accent uses the accent fill and dark text.
local function button(parent, label, x, y, w, h, accent, onClick)
  local normal = accent and COLOURS.accent or COLOURS.button
  local hover = accent and COLOURS.accentHover or COLOURS.buttonHover
  local bg = hitArea(rect(parent, normal, x, y, w, h))
  local t = text(parent, FONTS.body, ui.AlignMode.CENTRE, x, y, w, h)
  set(t, "content", label)
  if accent then
    set(t, "rgb", COLOURS.accentText)
    set(t, "isShadowed", false)
  end
  on(bg, "ONMOUSEOVER", function() set(bg, "rgb", hover) end)
  on(bg, "ONMOUSELEAVE", function() set(bg, "rgb", normal) end)
  on(bg, "ONCLICK", function() onClick() end)
  return { bg = bg, label = t }
end

-- deps: { saved = src/settings, tracker = src/cooldowns tracker, elements = src/view elements by name,
-- view = src/view, refresh = function redrawing the HUD }. Returns { shutdown }.
function options.create(root, deps)
  local saved, tracker, elements = deps.saved, deps.tracker, deps.elements

  local window = ui.Layer.new(root)
  window:SetSize(WIDTH, HEIGHT)
  window:SetPos(-WIDTH // 2, -HEIGHT // 2, 0.5, 0.5)
  set(window, "hidden", true)

  rect(window, COLOURS.border, 0, 0, WIDTH, HEIGHT)
  hitArea(rect(window, COLOURS.panel, 1, 1, WIDTH - 2, HEIGHT - 2))
  rect(window, COLOURS.sidebar, 1, 1, SIDEBAR - 1, HEIGHT - 2)
  rect(window, COLOURS.line, SIDEBAR, 1, 1, HEIGHT - 2)
  rect(window, COLOURS.line, PAGE_X, HEADER, PAGE_W, 1)
  rect(window, COLOURS.line, PAGE_X, HEIGHT - FOOTER - 1, PAGE_W, 1)
  local brand = text(window, FONTS.seconds, ui.AlignMode.TOPLEFT, 18, 1, SIDEBAR - 20, HEADER)
  set(brand, "content", "RuneUI")
  local title = text(window, FONTS.seconds, ui.AlignMode.TOPLEFT, PAGE_X + 24, 1, PAGE_W - 48, HEADER)

  -- Groups become the user's own on the first edit, so later automatic filling stops.
  local function groups()
    saved.adopt(saved.groups() or tracker.defaultGroups())
    return saved.groups()
  end

  local closePopups, rebuildEditor, drop, fillPicker, openPicker

  local function changed()
    rebuildEditor()
    deps.refresh()
  end

  -- Pages ---------------------------------------------------------------------------------------------

  local pages, navRows = {}, {}
  local PAGE_LIST = {
    { id = "cooldowns", label = "Cooldown manager" },
    { id = "resource", label = "Resource bar" },
    { id = "appearance", label = "Appearance" },
  }

  local function showPage(pageID)
    closePopups()
    for _, entry in ipairs(PAGE_LIST) do
      local active = entry.id == pageID
      set(pages[entry.id], "hidden", not active)
      local row = navRows[entry.id]
      set(row.bg, "hidden", not active)
      set(row.bar, "hidden", not active)
      set(row.label, "rgb", active and COLOURS.text or COLOURS.mutedText)
      if active then set(title, "content", entry.label) end
    end
  end

  for i, entry in ipairs(PAGE_LIST) do
    local y = HEADER + (i - 1) * 40
    local row = {
      hit = hitArea(rect(window, COLOURS.sidebar, 1, y, SIDEBAR - 1, 40)),
      bg = rect(window, COLOURS.line, 1, y, SIDEBAR - 1, 40),
      bar = rect(window, COLOURS.accent, 1, y, 3, 40),
      label = text(window, FONTS.body, ui.AlignMode.TOPLEFT, 18, y, SIDEBAR - 24, 40),
    }
    set(row.label, "content", entry.label)
    on(row.hit, "ONCLICK", function() showPage(entry.id) end)
    navRows[entry.id] = row
    local page = ui.Layer.new(window)
    page:SetSize(PAGE_W, HEIGHT - PAGE_Y - FOOTER - 1)
    page:SetPos(PAGE_X, PAGE_Y)
    pages[entry.id] = page
  end

  -- Cooldown editor ----------------------------------------------------------------------------------

  local page = pages.cooldowns
  local box = { x = 24, y = 18, w = PAGE_W - 48 }
  local ROWS = {
    { name = "cooldowns", label = "Cooldowns", size = deps.view.TILE_STYLES.cooldowns.size },
    { name = "rotation", label = "Rotation", size = deps.view.TILE_STYLES.rotation.size },
  }
  local y = box.y + 14
  for _, row in ipairs(ROWS) do
    row.labelY = y
    row.x = box.x + 14
    row.y = y + 22
    y = row.y + row.size + 18
  end
  rect(page, COLOURS.border, box.x, box.y, box.w, y - box.y)
  rect(page, COLOURS.sidebar, box.x + 1, box.y + 1, box.w - 2, y - box.y - 2)
  for _, row in ipairs(ROWS) do
    local label = text(page, FONTS.body, ui.AlignMode.TOPLEFT, row.x, row.labelY, 200, 18)
    set(label, "content", row.label)
  end
  local hint = text(page, FONTS.small, ui.AlignMode.TOPLEFT, box.x, y + 10, box.w, 14)
  set(hint, "content", "Drag to reorder or move between rows. Click + to add. Click an icon to remove it.")
  set(hint, "rgb", COLOURS.mutedText)

  -- The window's top-left in game-window pixels, measured from the last press, for following the cursor.
  local origin = { x = 0, y = 0 }
  local drag = nil

  -- An editor tile as a draw.group. Its edge is the hit area.
  local function tile(row)
    local size = row.size
    local group = draw.group()
    local t = {
      row = row, group = group,
      edge = group.add(hitArea(rect(page, COLOURS.border, 0, 0, size, size)), 0, 0),
      bg = group.add(rect(page, COLOURS.editorTile, 0, 0, size - 2, size - 2), 1, 1),
      icon = group.add(ui.Sprite.new(page), 1, 1),
      initials = group.add(text(page, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, size - 6, 12), 4, size - 15),
    }
    t.icon:SetSize(size - 2, size - 2)
    on(t.edge, "ONCLICK", function(_, x, py)
      if t.key == nil then return end
      closePopups()
      origin.x = Mouse.GetX() - (PAGE_X + group.x + x)
      origin.y = Mouse.GetY() - (PAGE_Y + group.y + py)
      drag = { tile = t, startX = Mouse.GetX(), startY = Mouse.GetY(), moved = false }
    end)
    on(t.edge, "ONRELEASE", function() if drag ~= nil and drag.tile == t then drop() end end)
    return t
  end

  -- The "+" tile as a draw.group.
  local function plusTile(row)
    local size = row.size
    local plus = draw.group()
    local edge = plus.add(hitArea(rect(page, COLOURS.mutedText, 0, 0, size, size)), 0, 0)
    plus.add(rect(page, COLOURS.sidebar, 0, 0, size - 2, size - 2), 1, 1)
    local glyph = plus.add(text(page, FONTS.seconds, ui.AlignMode.CENTRE, 0, 0, size, size), 0, 0)
    set(glyph, "content", "+")
    set(glyph, "rgb", COLOURS.accent)
    on(edge, "ONCLICK", function() openPicker(row, plus) end)
    return plus
  end

  for _, row in ipairs(ROWS) do
    row.tiles = {}
    for i = 1, MAX_TILES do row.tiles[i] = tile(row) end
    row.plus = plusTile(row)
  end

  local function knownTiles(keys)
    return tracker.tiles(keys, {})
  end

  function rebuildEditor()
    local current = saved.groups() or tracker.defaultGroups()
    for _, row in ipairs(ROWS) do
      local keys = current[row.name]
      local models = knownTiles(keys)
      for i, t in ipairs(row.tiles) do
        local model = models[i]
        t.key = model and model.key
        if model == nil then
          t.group.set("hidden", true)
        else
          t.group.place(row.x + (i - 1) * (row.size + GAP), row.y)
          hideAll({ t.edge, t.bg }, false)
          draw.iconOrInitials(t.icon, t.initials, model)
        end
      end
      local count = math.min(#models, MAX_TILES)
      row.plus.place(row.x + count * (row.size + GAP), row.y)
      row.plus.set("hidden", count >= MAX_TILES)
      row.count = count
    end
  end

  -- Drag feedback: a half-size ghost, a faded source tile, and either a swap outline or an insertion line.
  local ghost = ui.Sprite.new(page)
  local ghostInitials = text(page, FONTS.small, ui.AlignMode.CENTRE, 0, 0, 24, 24)
  local swapBox = outline(page, COLOURS.accent, 2)
  local insertLine = rect(page, COLOURS.accent, 0, 0, 2, 0)
  set(ghost, "alpha", 0.7)

  local function hideDragFeedback()
    hideAll({ ghost, ghostInitials, insertLine }, true)
    hideAll(swapBox, true)
  end
  hideDragFeedback()

  -- The row and drop target under the window position (wx, wy), or nil.
  local function targetAt(wx, wy)
    for _, row in ipairs(ROWS) do
      local top = PAGE_Y + row.y
      if wy >= top - 10 and wy <= top + row.size + 10 then
        local geometry = { count = row.count, step = row.size + GAP, size = row.size, offset = 0 }
        return row, editor.dropTarget(geometry, wx - PAGE_X - row.x)
      end
    end
  end

  local function showDragFeedback(t, wx, wy)
    local half = math.floor(t.row.size / 2)
    draw.size(ghost, half, half)
    draw.pos(ghost, wx - PAGE_X + 8, wy - PAGE_Y + 8)
    draw.pos(ghostInitials, wx - PAGE_X + 8, wy - PAGE_Y + 8)
    local row, target = targetAt(wx, wy)
    drag.row, drag.target = row, target
    local swap = target ~= nil and target.kind == "swap"
    hideAll(swapBox, not swap)
    set(insertLine, "hidden", target == nil or swap)
    if swap then
      placeOutline(swapBox, row.x + (target.index - 1) * (row.size + GAP), row.y, row.size, row.size)
    elseif target ~= nil then
      draw.pos(insertLine, row.x + (target.index - 1) * (row.size + GAP) - GAP, row.y - 4)
      draw.size(insertLine, 2, row.size + 8)
    end
  end

  local function startDrag(t)
    drag.moved = true
    t.group.set("alpha", 0.3)
    draw.iconOrInitials(ghost, ghostInitials, knownTiles({ t.key })[1])
  end

  -- Tile menu: one Remove row under the clicked tile.
  local menu = ui.Layer.new(page)
  menu:SetSize(140, 30)
  hitArea(rect(menu, COLOURS.border, 0, 0, 140, 30))
  local menuKey = nil
  button(menu, "Remove", 1, 1, 138, 28, false, function()
    if menuKey ~= nil then
      groups()
      saved.remove(menuKey)
      closePopups()
      changed()
    end
  end)

  local function openMenu(t)
    menuKey = t.key
    menu:SetPos(t.group.x, t.group.y + t.row.size + 4)
    set(menu, "hidden", false)
  end

  -- Ends a drag without dropping: the feedback hides and the source tile returns to full alpha.
  local function cancelDrag()
    if drag == nil then return end
    drag.tile.group.set("alpha", 1)
    drag = nil
    hideDragFeedback()
  end

  function drop()
    local d = drag
    cancelDrag()
    if not d.moved then
      openMenu(d.tile)
      return
    end
    if d.target == nil then return end
    local current = groups()
    local action = editor.dropAction(current, d.tile.key, d.row.name, d.target)
    if action == nil then return end
    if action.op == "swap" then
      saved.swap(d.tile.key, action.other)
    else
      saved.move(d.tile.key, action.group, action.index)
    end
    changed()
  end

  -- Picker: known abilities under a row's "+" tile, in sections. It stays open for several adds.
  local picker = ui.Layer.new(page)
  local pickerRows = {}
  local pickerFor = nil
  local MAX_PICKER_ROWS = 16
  picker:SetSize(PICKER_WIDTH, MAX_PICKER_ROWS * PICKER_ROW + 2)
  local pickerEdge = hitArea(rect(picker, COLOURS.border, 0, 0, PICKER_WIDTH, 0))
  local pickerBg = rect(picker, COLOURS.popup, 1, 1, PICKER_WIDTH - 2, 0)
  for i = 1, MAX_PICKER_ROWS do
    local ry = 1 + (i - 1) * PICKER_ROW
    local r = {
      bg = hitArea(rect(picker, COLOURS.popup, 1, ry, PICKER_WIDTH - 2, PICKER_ROW)),
      hover = rect(picker, COLOURS.buttonHover, 1, ry, PICKER_WIDTH - 2, PICKER_ROW),
      label = text(picker, FONTS.body, ui.AlignMode.TOPLEFT, 10, ry, PICKER_WIDTH - 50, PICKER_ROW),
      iconEdge = rect(picker, COLOURS.border, PICKER_WIDTH - 30, ry + 2, 22, 22),
      icon = ui.Sprite.new(picker),
    }
    r.icon:SetSize(20, 20)
    r.icon:SetPos(PICKER_WIDTH - 29, ry + 3)
    set(r.hover, "hidden", true)
    on(r.bg, "ONMOUSEOVER", function() set(r.hover, "hidden", r.key == nil) end)
    on(r.bg, "ONMOUSELEAVE", function() set(r.hover, "hidden", true) end)
    on(r.bg, "ONCLICK", function()
      if r.key == nil or pickerFor == nil then return end
      groups()
      saved.add(pickerFor.name, r.key)
      changed()
      fillPicker()
    end)
    pickerRows[i] = r
  end

  local function allKnownKeys()
    local keys, seen = {}, {}
    for _, key in ipairs(tracker.known()) do
      keys[#keys + 1], seen[key] = key, true
    end
    for key in pairs(saved.known()) do
      if not seen[key] then keys[#keys + 1], seen[key] = key, true end
    end
    local models = {}
    for _, t in ipairs(knownTiles(keys)) do models[t.key] = t end
    table.sort(keys, function(a, b) return models[a].name < models[b].name end)
    return keys, models
  end

  function fillPicker()
    local keys, models = allKnownKeys()
    local entries = {}
    for _, section in ipairs(editor.pickerSections(pickerFor.name, saved.groups() or tracker.defaultGroups(), keys)) do
      if #section.keys > 0 then
        entries[#entries + 1] = { title = section.title }
        for _, key in ipairs(section.keys) do entries[#entries + 1] = { key = key, name = models[key].name } end
      end
    end
    if #entries == 0 then entries[1] = { title = "Use an ability to add it here" } end
    for i, r in ipairs(pickerRows) do
      local entry = entries[i]
      r.key = entry and entry.key
      hideAll({ r.bg, r.label, r.iconEdge, r.icon, r.hover }, entry == nil)
      set(r.hover, "hidden", true)
      if entry ~= nil then
        set(r.label, "content", entry.title or entry.name)
        set(r.label, "rgb", entry.title and COLOURS.mutedText or COLOURS.text)
        local icon = entry.key and models[entry.key].icon
        hideAll({ r.iconEdge, r.icon }, icon == nil)
        if icon ~= nil then set(r.icon, "sprite", icon) end
      end
    end
    local shown = math.min(#entries, MAX_PICKER_ROWS)
    pickerEdge:SetSize(PICKER_WIDTH, shown * PICKER_ROW + 2)
    pickerBg:SetSize(PICKER_WIDTH - 2, shown * PICKER_ROW)
  end

  function openPicker(row, plus)
    local wasOpen = pickerFor == row
    closePopups()
    if wasOpen then return end
    pickerFor = row
    fillPicker()
    picker:SetPos(plus.x, plus.y + row.size + 4)
    set(picker, "hidden", false)
  end

  function closePopups()
    set(menu, "hidden", true)
    set(picker, "hidden", true)
    pickerFor, menuKey = nil, nil
  end

  -- Resource bar page ---------------------------------------------------------------------------------

  local markerPage = pages.resource
  local markerValues = {}
  for i, entry in ipairs({ { id = "threshold", label = "Threshold" }, { id = "ultimate", label = "Ultimate" } }) do
    local ry = 18 + (i - 1) * 50
    rect(markerPage, i % 2 == 1 and COLOURS.sidebar or COLOURS.panel, 24, ry, PAGE_W - 48, 50)
    local label = text(markerPage, FONTS.body, ui.AlignMode.TOPLEFT, 40, ry, 200, 50)
    set(label, "content", entry.label .. " marker")
    local right = PAGE_W - 40
    local value = text(markerPage, FONTS.body, ui.AlignMode.CENTRE, right - 104, ry, 56, 50)
    markerValues[entry.id] = value
    local function step(delta)
      saved.setMarker(entry.id, saved.markers()[entry.id] + delta)
      set(value, "content", saved.markers()[entry.id] .. "%")
      deps.refresh()
    end
    button(markerPage, "-", right - 136, ry + 11, 28, 28, false, function() step(-MARKER_STEP) end)
    button(markerPage, "+", right - 44, ry + 11, 28, 28, false, function() step(MARKER_STEP) end)
  end

  -- Appearance page ----------------------------------------------------------------------------------

  local appearancePage = pages.appearance
  local CHOICE_W = 150
  local choiceRows = {}

  -- The chosen option takes the accent fill and dark text; the others are plain buttons.
  local function showChoices()
    for _, row in ipairs(choiceRows) do
      for value, choice in pairs(row.choices) do
        local chosen = value == row.current()
        set(choice.bg, "rgb", chosen and COLOURS.accent or COLOURS.button)
        set(choice.label, "rgb", chosen and COLOURS.accentText or COLOURS.text)
        set(choice.label, "isShadowed", not chosen)
      end
    end
  end

  -- A labelled row of right-aligned option buttons. choices: { { value, label } }; current() returns the
  -- chosen value and choose(value) saves one.
  local function choiceRow(label, choices, current, choose)
    local ry = 18 + #choiceRows * 50
    rect(appearancePage, #choiceRows % 2 == 0 and COLOURS.sidebar or COLOURS.panel, 24, ry, PAGE_W - 48, 50)
    local rowLabel = text(appearancePage, FONTS.body, ui.AlignMode.TOPLEFT, 40, ry, 200, 50)
    set(rowLabel, "content", label)
    local row = { choices = {}, current = current }
    choiceRows[#choiceRows + 1] = row
    for i, option in ipairs(choices) do
      local x = PAGE_W - 40 - (#choices - i + 1) * (CHOICE_W + 4) + 4
      local bg = hitArea(rect(appearancePage, COLOURS.button, x, ry + 11, CHOICE_W, 28))
      local optionLabel = text(appearancePage, FONTS.body, ui.AlignMode.CENTRE, x, ry + 11, CHOICE_W, 28)
      set(optionLabel, "content", option.label)
      row.choices[option.value] = { bg = bg, label = optionLabel }
      on(bg, "ONMOUSEOVER", function()
        if option.value ~= current() then set(bg, "rgb", COLOURS.buttonHover) end
      end)
      on(bg, "ONMOUSELEAVE", showChoices)
      on(bg, "ONCLICK", function()
        choose(option.value)
        showChoices()
        deps.refresh()
      end)
    end
  end

  local TEXTURE_LABELS = { flat = "Flat", vertical = "Vertical gradient", horizontal = "Horizontal gradient" }
  local textures = {}
  for i, texture in ipairs(settings.TEXTURES) do textures[i] = { value = texture, label = TEXTURE_LABELS[texture] } end
  choiceRow("Bar texture", textures, saved.texture, saved.setTexture)
  choiceRow("Default target panel", { { value = false, label = "Show" }, { value = true, label = "Hide" } },
    saved.hideTargetPanel, saved.setHideTargetPanel)

  -- Edit mode ----------------------------------------------------------------------------------------

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
    on(tint, "ONCLICK", function()
      move = { name = name, startX = Mouse.GetX(), startY = Mouse.GetY(), from = saved.positions()[name] }
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

  local function placeAll()
    local positions = saved.positions()
    for name, element in pairs(elements) do
      deps.view.place(element.layer, positions[name])
      deps.view.place(overlays[name], positions[name])
    end
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
  local openWindow

  local windowOpen = false

  local function closeWindow()
    cancelDrag()
    closePopups()
    windowOpen = false
    set(window, "hidden", true)
  end

  -- Edit mode hides the window, which covers the HUD, and shows a toolbar whose Done returns to it.
  local function setEditing(enabled)
    editing = enabled
    if not enabled then cancelMove() end
    for _, layer in pairs(overlays) do set(layer, "hidden", not enabled) end
    set(toolbar, "hidden", not enabled)
    if enabled then closeWindow() end
  end

  local function resetPositions()
    saved.resetPositions()
    placeAll()
  end

  button(toolbar, "Reset positions", 160, 7, 140, 30, false, resetPositions)
  button(toolbar, "Done", 308, 7, 84, 30, true, function()
    setEditing(false)
    openWindow()
  end)

  -- Footer --------------------------------------------------------------------------------------------

  local footerY = HEIGHT - FOOTER
  local toggleHit = hitArea(rect(window, COLOURS.panel, PAGE_X + 16, footerY, 180, FOOTER))
  rect(window, COLOURS.button, PAGE_X + 24, footerY + 18, 40, 20)
  rect(window, COLOURS.text, PAGE_X + 26, footerY + 20, 16, 16)
  local toggleLabel = text(window, FONTS.body, ui.AlignMode.TOPLEFT, PAGE_X + 72, footerY, 120, FOOTER)
  set(toggleLabel, "content", "Edit mode off")
  on(toggleHit, "ONCLICK", function() setEditing(true) end)
  button(window, "Reset positions", PAGE_X + 200, footerY + 12, 140, 32, false, resetPositions)
  button(window, "Done", WIDTH - 24 - 90, footerY + 12, 90, 32, true, closeWindow)

  function openWindow()
    for id_, value in pairs(markerValues) do set(value, "content", saved.markers()[id_] .. "%") end
    showChoices()
    rebuildEditor()
    showPage("cooldowns")
    windowOpen = true
    set(window, "hidden", false)
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Runs 50 times a second, so it returns before reading the mouse unless a drag or move is under way, and
  -- before drawing unless the cursor moved.
  local lastX, lastY = nil, nil
  Event.Logic.Subscribe("runeuiOptions", function()
    if drag == nil and move == nil then return end
    local mx, my = Mouse.GetX(), Mouse.GetY()
    if mx == nil or my == nil or (mx == lastX and my == lastY) then return end
    lastX, lastY = mx, my
    if drag ~= nil then
      if not drag.moved and math.abs(mx - drag.startX) + math.abs(my - drag.startY) > DRAG_START then
        startDrag(drag.tile)
      end
      if drag.moved then showDragFeedback(drag.tile, mx - origin.x, my - origin.y) end
    end
    if move ~= nil then
      local from = move.from
      move.to = { x = from.x + mx - move.startX, y = from.y + my - move.startY,
        anchorX = from.anchorX, anchorY = from.anchorY }
      deps.view.place(elements[move.name].layer, move.to)
      deps.view.place(overlays[move.name], move.to)
    end
  end)

  Event.KeyDown.Subscribe("runeuiOptions", function(e)
    if e.gameKey ~= GameKey.ESCAPE then return end
    if editing then
      setEditing(false)
    elseif windowOpen then
      closeWindow()
    end
  end)

  Event.ContentLayerReady.Subscribe("runeuiRibbon", function(e)
    button(e.component, "Open RuneUI options", 10, 10, 180, 32, true, openWindow)
  end)

  placeAll()
  closePopups()

  return {
    shutdown = function()
      window:Destroy()
      toolbar:Destroy()
      for _, layer in pairs(overlays) do layer:Destroy() end
    end,
  }
end

return options
