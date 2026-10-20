-- The options window and its ribbon button: a sidebar of pages, a cooldown editor that mirrors both rows
-- with a "+" picker, drag to swap or insert and a Remove menu, marker steppers, appearance choices, the
-- reset dialog, and a footer toggle into src/editmode.
local draw = require("src/draw")
local editmode = require("src/editmode")
local editor = require("src/editor")
local settings = require("src/settings")

local options = {}

local set, rect, text, outline, placeOutline = draw.set, draw.rect, draw.text, draw.outline, draw.placeOutline
local hideAll, hitArea, on, button = draw.hideAll, draw.hitArea, draw.on, draw.button
local pressAt, cursor = draw.pressAt, draw.cursor
local FONTS, COLOURS = draw.FONTS, draw.COLOURS

local WIDTH, HEIGHT = 900, 620
local SIDEBAR, HEADER, FOOTER = 200, 64, 56
local PAGE_X, PAGE_Y = SIDEBAR + 1, HEADER + 1
local PAGE_W = WIDTH - PAGE_X - 1
-- Pixels the cursor must travel after a press before it counts as a drag.
local DRAG_START = 3
local MAX_TILES = 10
local GAP = 2
local PICKER_WIDTH, PICKER_ROW, PICKER_SEARCH, PICKER_TABS = 340, 26, 36, 34
local PICKER_HEAD = PICKER_SEARCH + PICKER_TABS
-- Picker tabs left to right; style nil lists every style.
local PICKER_TAB_LIST = {
  { label = "All", width = 34 }, { label = "Necromancy", style = "necromancy", width = 100 },
  { label = "Magic", style = "magic", width = 58 }, { label = "Ranged", style = "ranged", width = 66 },
  { label = "Melee", style = "melee", width = 58 },
}
local MARKER_STEP = 5

-- deps: { saved = src/settings, tracker = src/cooldowns tracker, elements = src/view elements by name,
-- view = src/view, refresh = function redrawing the HUD }. Returns { placeAll, shutdown }; placeAll places
-- the HUD and edit mode's overlays from the saved positions and anchors.
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
      pressAt(t.edge, x)
      local mx, my = cursor()
      if mx == nil then return end
      origin.x = mx - (PAGE_X + group.x + x)
      origin.y = my - (PAGE_Y + group.y + py)
      drag = { tile = t, startX = mx, startY = my, pressX = x, pressY = py, moved = false }
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

  -- Ends a drag without dropping: the feedback hides and the source tile returns to its slot at full alpha.
  local function cancelDrag()
    if drag == nil then return end
    local group = drag.tile.group
    group.set("alpha", 1)
    group.place(group.x, group.y)
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

  -- Picker: known abilities under a row's "+" tile, in sections, one combat style tab at a time, narrowed by
  -- a search box. It opens on the current style and stays open for several adds. A search covers every style.
  local picker = ui.Layer.new(page)
  local pickerRows, pickerTabs = {}, {}
  local pickerFor, pickerStyle, query = nil, nil, ""
  local MAX_PICKER_ROWS = 14
  picker:SetSize(PICKER_WIDTH, PICKER_HEAD + MAX_PICKER_ROWS * PICKER_ROW + 2)
  local pickerEdge = hitArea(rect(picker, COLOURS.border, 0, 0, PICKER_WIDTH, 0))
  local pickerBg = rect(picker, COLOURS.popup, 1, 1, PICKER_WIDTH - 2, 0)
  rect(picker, COLOURS.line, 1, PICKER_HEAD, PICKER_WIDTH - 2, 1)
  local search = ui.InputField.new(picker)
  search:SetPos(10, 6)
  search:SetSize(PICKER_WIDTH - 20, 24)
  search:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, 30)
  if id.StyleSheet.INPUT_SEARCHBOX_24PX ~= nil then set(search, "stylesheetID", id.StyleSheet.INPUT_SEARCHBOX_24PX) end
  set(search, "emptyText", "Find an ability")
  -- The field also reports its contents on Enter, Esc and focus loss, which can come after the picker closed.
  on(search, "ONCONTENTCHANGED", function(_, _, contents)
    query = (contents or ""):lower()
    if pickerFor == nil then return end
    if query ~= "" then pickerStyle = nil end
    fillPicker()
  end)
  local tabX = 10
  for _, tab in ipairs(PICKER_TAB_LIST) do
    local hit = hitArea(rect(picker, COLOURS.popup, tabX, PICKER_SEARCH, tab.width, PICKER_TABS))
    local t = {
      style = tab.style,
      label = text(picker, FONTS.body, ui.AlignMode.CENTRE, tabX, PICKER_SEARCH, tab.width, PICKER_TABS - 2),
      underline = rect(picker, COLOURS.accent, tabX, PICKER_HEAD - 2, tab.width, 2),
    }
    set(t.label, "content", tab.label)
    on(hit, "ONCLICK", function()
      pickerStyle = t.style
      fillPicker()
    end)
    pickerTabs[#pickerTabs + 1] = t
    tabX = tabX + tab.width
  end
  for i = 1, MAX_PICKER_ROWS do
    local ry = PICKER_HEAD + 1 + (i - 1) * PICKER_ROW
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
    for _, t in ipairs(pickerTabs) do
      set(t.label, "rgb", t.style == pickerStyle and COLOURS.text or COLOURS.mutedText)
      set(t.underline, "hidden", t.style ~= pickerStyle)
    end
    local keys, models = allKnownKeys()
    if query ~= "" then
      local matching = {}
      for _, key in ipairs(keys) do
        if models[key].name:lower():find(query, 1, true) then matching[#matching + 1] = key end
      end
      keys = matching
    end
    local entries = {}
    local groupsNow = saved.groups() or tracker.defaultGroups()
    for _, section in ipairs(editor.pickerSections(pickerFor.name, groupsNow, keys, pickerStyle)) do
      if #section.keys > 0 then
        entries[#entries + 1] = { title = section.title }
        for _, key in ipairs(section.keys) do entries[#entries + 1] = { key = key, name = models[key].name } end
      end
    end
    if #entries == 0 then
      entries[1] = { title = query ~= "" and "No ability matches" or "Use an ability to add it here" }
    end
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
    pickerEdge:SetSize(PICKER_WIDTH, PICKER_HEAD + shown * PICKER_ROW + 2)
    pickerBg:SetSize(PICKER_WIDTH - 2, PICKER_HEAD + shown * PICKER_ROW)
  end

  function openPicker(row, plus)
    local wasOpen = pickerFor == row
    closePopups()
    if wasOpen then return end
    pickerFor, pickerStyle = row, tracker.style()
    if query ~= "" then
      query = ""
      search.content = ""
    end
    fillPicker()
    picker:SetPos(math.min(plus.x, PAGE_W - PICKER_WIDTH - 8), plus.y + row.size + 4)
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

  local resetPositions, openWindow
  local editMode = editmode.create(root, {
    saved = saved, elements = elements, view = deps.view,
    reset = function() resetPositions() end,
    done = function() openWindow() end,
  })

  -- Reset dialog: confirms Reset positions over the window, which it dims when open. Built after the window
  -- and edit mode so it draws above them.
  local DIALOG_W, DIALOG_H = 320, 150
  local dialog = ui.Layer.new(root)
  dialog:SetSize(WIDTH, HEIGHT)
  dialog:SetPos(-WIDTH // 2, -HEIGHT // 2, 0.5, 0.5)
  local dim = hitArea(rect(dialog, COLOURS.border, 0, 0, WIDTH, HEIGHT))
  set(dim, "alpha", 0.6)
  local dialogX, dialogY = (WIDTH - DIALOG_W) // 2, (HEIGHT - DIALOG_H) // 2
  rect(dialog, COLOURS.border, dialogX, dialogY, DIALOG_W, DIALOG_H)
  hitArea(rect(dialog, COLOURS.popup, dialogX + 1, dialogY + 1, DIALOG_W - 2, DIALOG_H - 2))
  local dialogTitle = text(dialog, FONTS.body, ui.AlignMode.TOPLEFT, dialogX + 16, dialogY + 12, DIALOG_W - 32, 20)
  set(dialogTitle, "content", "Reset positions")
  local dialogBody = text(dialog, FONTS.small, ui.AlignMode.TOPLEFT, dialogX + 16, dialogY + 40, DIALOG_W - 32, 44)
  set(dialogBody, "content",
    "Every frame, bar and ability row goes back to its default spot. Your rows and settings stay.")
  set(dialogBody, "rgb", COLOURS.dimText)
  rect(dialog, COLOURS.line, dialogX + 1, dialogY + DIALOG_H - 56, DIALOG_W - 2, 1)
  local dialogOpen = false

  local function closeDialog()
    dialogOpen = false
    set(dialog, "hidden", true)
  end
  closeDialog()

  local buttonsY = dialogY + DIALOG_H - 44
  button(dialog, "Cancel", dialogX + DIALOG_W - 264, buttonsY, 90, 32, nil, closeDialog)
  button(dialog, "Reset positions", dialogX + DIALOG_W - 166, buttonsY, 150, 32, "light", function()
    closeDialog()
    saved.resetPositions()
    editMode.placeAll()
  end)

  local windowOpen = false

  local function closeWindow()
    closeDialog()
    cancelDrag()
    closePopups()
    windowOpen = false
    set(window, "hidden", true)
  end

  function resetPositions()
    closePopups()
    dialogOpen = true
    set(dim, "hidden", not windowOpen)
    set(dialog, "hidden", false)
  end

  -- Footer --------------------------------------------------------------------------------------------

  local footerY = HEIGHT - FOOTER
  local toggleHit = hitArea(rect(window, COLOURS.panel, PAGE_X + 16, footerY, 180, FOOTER))
  rect(window, COLOURS.button, PAGE_X + 24, footerY + 18, 40, 20)
  rect(window, COLOURS.text, PAGE_X + 26, footerY + 20, 16, 16)
  local toggleLabel = text(window, FONTS.body, ui.AlignMode.TOPLEFT, PAGE_X + 72, footerY, 120, FOOTER)
  set(toggleLabel, "content", "Edit mode off")
  -- Edit mode hides the window, which covers the HUD; its toolbar's Done returns to the window.
  on(toggleHit, "ONCLICK", function()
    closeWindow()
    editMode.open()
  end)
  button(window, "Reset positions", PAGE_X + 200, footerY + 12, 140, 32, false, resetPositions)
  button(window, "Done", WIDTH - 24 - 90, footerY + 12, 90, 32, "accent", closeWindow)

  function openWindow()
    for id_, value in pairs(markerValues) do set(value, "content", saved.markers()[id_] .. "%") end
    showChoices()
    rebuildEditor()
    showPage("cooldowns")
    windowOpen = true
    set(window, "hidden", false)
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Moves the drag ghost with the cursor. It runs every frame through Event.Draw so a drag keeps up with the
  -- mouse, and on Event.Logic as well in case Draw does not fire. It returns before reading the mouse unless a
  -- drag is under way, and before drawing unless the cursor moved.
  local lastX, lastY = nil, nil
  local function followCursor()
    if drag == nil then return end
    local mx, my = cursor()
    if mx == nil or (mx == lastX and my == lastY) then return end
    lastX, lastY = mx, my
    if not drag.moved and math.abs(mx - drag.startX) + math.abs(my - drag.startY) > DRAG_START then
      startDrag(drag.tile)
    end
    if drag.moved then
      local wx, wy = mx - origin.x, my - origin.y
      -- The client releases a press once the cursor leaves the pressed component, so the hit area follows.
      draw.pos(drag.tile.edge, wx - PAGE_X - drag.pressX, wy - PAGE_Y - drag.pressY)
      showDragFeedback(drag.tile, wx, wy)
    end
  end
  Event.Draw.Subscribe("runeuiOptions", followCursor)
  Event.Logic.Subscribe("runeuiOptions", followCursor)

  Event.KeyDown.Subscribe("runeuiOptions", function(e)
    if e.gameKey ~= GameKey.ESCAPE then return end
    if dialogOpen then
      closeDialog()
    elseif editMode.editing() then
      editMode.escape()
    elseif windowOpen then
      closeWindow()
    end
  end)

  Event.ContentLayerReady.Subscribe("runeuiRibbon", function(e)
    button(e.component, "Open RuneUI options", 10, 10, 180, 32, "accent", openWindow)
  end)

  editMode.placeAll()
  closePopups()

  return {
    placeAll = editMode.placeAll,
    shutdown = function()
      window:Destroy()
      editMode.shutdown()
      dialog:Destroy()
    end,
  }
end

return options
