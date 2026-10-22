-- The options window and its ribbon button: a PrettyUI window with a tab per page, a cooldown manager with
-- combat style tabs, a group list with New group, and the chosen group's display settings and abilities with a
-- "+" picker, drag to swap or insert and a Remove menu; the src/buffspage Buffs page, the src/appearancepage
-- Appearance and Bars pages, and a footer with Edit mode into src/editmode, Reset positions and Done.
local appearancepage = require("src/appearancepage")
local buffspage = require("src/buffspage")
local catalog = require("src/catalog")
local dragdrop = require("src/dragdrop")
local draw = require("src/draw")
local editmode = require("src/editmode")
local editor = require("src/editor")
local presets = require("src/presets")
local settings = require("src/settings")

local options = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local outline = draw.outline
local placeOutline = draw.placeOutline
local hideAll = draw.hideAll
local hitArea = draw.hitArea
local on = draw.on
local button = draw.button
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW

local WIDTH = 900
local HEIGHT = 680
-- The window's content sits inside its 8 px border under its 32 px title bar. Page tabs fill it above the
-- footer, and each page sits under the tabs' 42 px strip.
local CONTENT_X = 8
local CONTENT_Y = 32
local CONTENT_W = WIDTH - 2 * CONTENT_X
local CONTENT_H = HEIGHT - CONTENT_Y - CONTENT_X
local FOOTER = 46
local TAB_STRIP = 42
local PAGE_X = CONTENT_X
local PAGE_Y = CONTENT_Y + TAB_STRIP
local PAGE_W = CONTENT_W
local PAGE_H = CONTENT_H - FOOTER - TAB_STRIP
-- Footer buttons from the right, and the gap between them and at the window's edge.
local FOOTER_BUTTONS = { "Done", "Reset positions", "Edit mode" }
local FOOTER_GAP = 12
local BUTTON_H = 27
local GAP = 2
-- Cooldown manager layout: style tabs across the top, the group list on the left, and the chosen group's
-- setting rows then its ability tiles, in rows of GRID_PER_ROW, on the right.
local STYLE_TABS = {
  { label = "Necromancy", style = "necromancy", width = 110 },
  { label = "Magic", style = "magic", width = 80 },
  { label = "Ranged", style = "ranged", width = 84 },
  { label = "Melee", style = "melee", width = 76 },
}
local TABS_H = 44
local LIST_W = 170
local LIST_Y = 56
local LIST_ROW = 44
local DETAIL_X = LIST_W + 24
local DETAIL_W = PAGE_W - DETAIL_X - 24
local SETTING_H = 46
local SETTING_ROWS = 5
local TILE = 36
local STEP = TILE + GAP
local GRID_Y = LIST_Y + SETTING_ROWS * SETTING_H + 16
local GRID_PER_ROW = (DETAIL_W + GAP) // STEP
local PICKER_WIDTH = 340
local PICKER_ROW = 26
local PICKER_SEARCH = 36
local PICKER_TABS = 34
local PICKER_HEAD = PICKER_SEARCH + PICKER_TABS
-- Picker tabs left to right; style nil lists every style.
local PICKER_TAB_LIST = {
  { label = "All", width = 34 },
  { label = "Necromancy", style = "necromancy", width = 100 },
  { label = "Magic", style = "magic", width = 58 },
  { label = "Ranged", style = "ranged", width = 66 },
  { label = "Melee", style = "melee", width = 58 },
}

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

-- deps: { saved = src/settings, tracker = src/cooldowns tracker, elements = src/view elements by name,
-- view = src/view, auraInfo(sprite) naming an aura icon, describe(struct) reading a struct's description,
-- learnName(sprite, name, struct) naming an aura icon at once, refresh = function redrawing the HUD }. Returns
-- { placeAll, redrawBuffs, shutdown }; placeAll places the HUD and edit mode's overlays from the saved
-- positions and anchors, and redrawBuffs redraws the Buffs page while it is shown.
function options.create(root, deps)
  local saved = deps.saved
  local tracker = deps.tracker
  local elements = deps.elements

  local closePopups, rebuildEditor, fillPicker, openPicker, buffsPage, editorDrag, closeWindow

  -- Built open, as PrettyUI builds every window, and closed once the pages are built.
  local window = prettyui.Window.new(root, {
    title = "RuneUI",
    width = WIDTH,
    height = HEIGHT,
    x = -WIDTH // 2,
    y = -HEIGHT // 2,
    xAnchor = 0.5,
    yAnchor = 0.5,
    scrollable = false,
    onClose = function()
      closeWindow()
    end,
  })

  local function changed()
    rebuildEditor()
    deps.refresh()
  end

  -- Pages ---------------------------------------------------------------------------------------------

  local pages = {}
  local PAGE_LIST = {
    { id = "appearance", label = "Appearance" },
    { id = "cooldowns", label = "Cooldown manager" },
    { id = "buffs", label = "Buffs" },
    { id = "bars", label = "Bars" },
  }

  local currentPage = nil
  -- The src/appearancepage pages, built once the Buffs page's tooltip exists.
  local appearance, bars

  local function showPage(pageID)
    closePopups()
    currentPage = pageID
    if pageID == "buffs" then
      buffsPage.redraw()
    end
    if pageID == "appearance" then
      appearance.open()
    elseif pageID == "bars" then
      bars.open()
    end
  end

  local tabValues = {}
  for i, entry in ipairs(PAGE_LIST) do
    tabValues[i] = { text = entry.label }
  end
  local pageTabs = window:AddTabs(tabValues, {
    x = 0,
    y = 0,
    width = CONTENT_W,
    height = CONTENT_H - FOOTER,
    scrollable = false,
    onChange = function(_, index)
      showPage(PAGE_LIST[index].id)
    end,
  })

  -- Each page is a layer on its tab's content, which the page's module draws on.
  for i, entry in ipairs(PAGE_LIST) do
    local page = ui.Layer.new(pageTabs:GetPage(i).content)
    page:SetSize(PAGE_W, PAGE_H)
    -- A click on the page's background closes its popups.
    if entry.id ~= "appearance" and entry.id ~= "bars" then
      on(hitArea(rect(page, COLOURS.panel, 0, 0, PAGE_W, PAGE_H)), "ONCLICK", function()
        closePopups()
      end)
    end
    pages[entry.id] = page
  end

  -- Cooldown manager ---------------------------------------------------------------------------------

  local page = pages.cooldowns
  -- The style whose lists the page edits, the group shown in the detail pane, and whether its Delete button
  -- has been clicked once.
  local editStyle = "magic"
  local selected = "major"
  local confirmDelete = false

  -- Style tabs: the chosen one underlined, the equipped one marked Equipped.
  local styleTabs = {}
  local styleX = 16
  for _, tab in ipairs(STYLE_TABS) do
    local t = {
      style = tab.style,
      hit = hitArea(rect(page, COLOURS.panel, styleX, 0, tab.width, TABS_H)),
      label = text(page, FONTS.body, ui.AlignMode.CENTRE, styleX, 2, tab.width, 26),
      equipped = text(page, FONTS.small, ui.AlignMode.CENTRE, styleX, 26, tab.width, 14),
      underline = rect(page, COLOURS.accent, styleX, TABS_H - 2, tab.width, 2),
    }
    set(t.label, "content", tab.label)
    set(t.equipped, "content", "Equipped")
    set(t.equipped, "rgb", COLOURS.accent)
    on(t.hit, "ONCLICK", function()
      editStyle = t.style
      closePopups()
      rebuildEditor()
    end)
    styleTabs[#styleTabs + 1] = t
    styleX = styleX + tab.width + 4
  end
  rect(page, COLOURS.line, 0, TABS_H, PAGE_W, 1)

  -- Group list: one row per group in use, the chosen one lit with an accent bar, then New group.
  rect(page, COLOURS.line, LIST_W, TABS_H + 1, 1, PAGE_H - TABS_H - 1)
  local listRows = {}
  for i = 1, #settings.GROUPS + #settings.CUSTOM_GROUPS do
    local y = LIST_Y + (i - 1) * LIST_ROW
    local r = {
      hit = hitArea(rect(page, COLOURS.panel, 0, y, LIST_W, LIST_ROW)),
      bar = rect(page, COLOURS.accent, 0, y, 3, LIST_ROW),
      title = text(page, FONTS.body, ui.AlignMode.TOPLEFT, 16, y + 4, LIST_W - 60, 22),
      shared = text(page, FONTS.small, ui.AlignMode.TOPLEFT, 16, y + 25, LIST_W - 60, 14),
      count = text(page, FONTS.small, ui.AlignMode.BOTTOMRIGHT, LIST_W - 50, y, 38, LIST_ROW),
    }
    set(r.shared, "content", "Every style")
    set(r.shared, "rgb", COLOURS.dimText)
    set(r.count, "rgb", COLOURS.dimText)
    on(r.hit, "ONCLICK", function()
      if r.name == nil then
        return
      end
      selected = r.name
      confirmDelete = false
      closePopups()
      rebuildEditor()
    end)
    listRows[i] = r
  end
  local newGroup = button(page, "New group", 16, 0, LIST_W - 32, 32, "dark", function()
    local name = saved.addGroup()
    if name == nil then
      return
    end
    selected = name
    confirmDelete = false
    closePopups()
    changed()
  end)

  -- Detail pane: Name, Icon size, Icons per row, Grow and Abilities rows over the group's ability tiles.
  local function rowY(i)
    return LIST_Y + (i - 1) * SETTING_H
  end
  local detailRight = DETAIL_X + DETAIL_W - 16
  for i = 1, SETTING_ROWS do
    rect(page, i % 2 == 1 and COLOURS.row or COLOURS.rowAlt, DETAIL_X, rowY(i), DETAIL_W, SETTING_H)
  end
  local function settingLabel(i, content)
    local label = text(page, FONTS.body, ui.AlignMode.TOPLEFT, DETAIL_X + 16, rowY(i), 150, SETTING_H)
    set(label, "content", content)
    return label
  end

  settingLabel(1, "Name")
  local titleText =
    text(page, FONTS.body, ui.AlignMode.BOTTOMRIGHT, DETAIL_X + 120, rowY(1), detailRight - DETAIL_X - 120, SETTING_H)
  local nameField = draw.inputField(page, DETAIL_X + 120, rowY(1) + 11, detailRight - 126 - DETAIL_X - 120, 24, 20)
  -- The group whose title the field shows; a change arriving after another group was chosen is ignored.
  local nameFor = nil
  on(nameField, "ONCONTENTCHANGED", function(_, _, contents)
    if nameFor == nil or nameFor ~= selected or saved.group(nameFor) == nil then
      return
    end
    local before = saved.group(nameFor).title
    saved.setGroup(nameFor, "title", contents or "")
    if saved.group(nameFor).title ~= before then
      changed()
    end
  end)
  local deleteButton
  deleteButton = button(page, "Delete", detailRight - 120, rowY(1) + 9, 120, 28, "dark", function()
    if saved.group(selected) == nil then
      return
    end
    if not confirmDelete then
      confirmDelete = true
      set(deleteButton.label, "content", "Click to delete")
      return
    end
    saved.deleteGroup(selected)
    selected = "major"
    confirmDelete = false
    changed()
  end)

  -- A row's - number + stepper moving field by 1 from low to high, its number typed; returns a function showing
  -- a group's value.
  local function stepper(i, field, low, high)
    local function choose(n)
      local group = saved.group(selected)
      if group == nil or n == group[field] then
        return
      end
      saved.setGroup(selected, field, n)
      changed()
    end
    local value = draw.numberField(page, detailRight - 92, rowY(i) + 11, 56, 24, low, high, choose)
    local function step(d)
      local group = saved.group(selected)
      if group ~= nil then
        choose(math.max(low, math.min(high, group[field] + d)))
      end
    end
    button(page, "-", detailRight - 124, rowY(i) + 9, 28, 28, "dark", function()
      step(-1)
    end)
    button(page, "+", detailRight - 28, rowY(i) + 9, 28, 28, "dark", function()
      step(1)
    end)
    return function(group)
      value.show(group[field])
    end
  end
  settingLabel(2, "Icon size")
  local showSize = stepper(2, "size", settings.SIZE_MIN, settings.SIZE_MAX)
  local perRowLabel = settingLabel(3, "Icons per row")
  local showPerRow = stepper(3, "perRow", 1, settings.MAX_GROUP_KEYS)

  -- Rows of right-aligned draw.option buttons that save one display setting.
  local settingChoices = {}
  local function settingChoice(i, field, choices, width)
    local row = { field = field, buttons = {} }
    for k, option in ipairs(choices) do
      local x = detailRight - (#choices - k + 1) * (width + 4) + 4
      local b = draw.option(page, option.label, x, rowY(i) + 9, width, 28, function()
        if saved.group(selected) == nil then
          return
        end
        saved.setGroup(selected, field, option.value)
        changed()
      end)
      b.value = option.value
      row.buttons[#row.buttons + 1] = b
    end
    settingChoices[#settingChoices + 1] = row
  end
  settingLabel(4, "Grow")
  settingChoice(4, "grow", {
    { value = "up", label = "Up" },
    { value = "down", label = "Down" },
    { value = "left", label = "Left" },
    { value = "right", label = "Right" },
  }, 64)
  settingLabel(5, "Abilities")
  settingChoice(5, "shared", { { value = false, label = "Per style" }, { value = true, label = "Every style" } }, 110)

  -- Page position of grid slot i.
  local function slotPos(i)
    return DETAIL_X + (i - 1) % GRID_PER_ROW * STEP, GRID_Y + (i - 1) // GRID_PER_ROW * STEP
  end

  -- An editor tile as a draw.group. Its edge is the hit area, which src/dragdrop drags.
  local function tile()
    local group = draw.group()
    local t = {
      group = group,
      size = TILE,
      edge = group.add(hitArea(rect(page, COLOURS.border, 0, 0, TILE, TILE)), 0, 0),
      bg = group.add(rect(page, COLOURS.editorTile, 0, 0, TILE - 2, TILE - 2), 1, 1),
      icon = group.add(ui.Sprite.new(page), 1, 1),
      initials = group.add(text(page, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, TILE - 6, 12), 4, TILE - 15),
    }
    t.icon:SetSize(TILE - 2, TILE - 2)
    return t
  end

  local editorTiles = {}
  for i = 1, settings.MAX_GROUP_KEYS do
    editorTiles[i] = tile()
  end
  local count = 0

  -- The "+" tile as a draw.group.
  local plus = draw.group()
  local plusEdge = plus.add(hitArea(rect(page, COLOURS.mutedText, 0, 0, TILE, TILE)), 0, 0)
  plus.add(rect(page, COLOURS.sidebar, 0, 0, TILE - 2, TILE - 2), 1, 1)
  local glyph = plus.add(text(page, FONTS.seconds, ui.AlignMode.CENTRE, 0, 0, TILE, TILE), 0, 0)
  set(glyph, "content", "+")
  set(glyph, "rgb", COLOURS.accent)
  on(plusEdge, "ONCLICK", function()
    openPicker()
  end)

  local hint = text(page, FONTS.small, ui.AlignMode.TOPLEFT, DETAIL_X, 0, DETAIL_W, 14)
  set(hint, "content", "Drag to reorder. Click + to add or move an ability here. Click an icon to remove it.")
  set(hint, "rgb", COLOURS.mutedText)

  local function knownTiles(keys)
    return tracker.tiles(keys, {})
  end

  -- Marks each choice row's option for group's value chosen.
  local function showSettingChoices(group)
    for _, row in ipairs(settingChoices) do
      for _, b in ipairs(row.buttons) do
        draw.showOption(b, b.value == group[row.field])
      end
    end
  end

  function rebuildEditor()
    if saved.group(selected) == nil then
      selected = "major"
    end
    local equipped = tracker.style()
    for _, t in ipairs(styleTabs) do
      set(t.label, "rgb", t.style == editStyle and COLOURS.text or COLOURS.mutedText)
      set(t.underline, "hidden", t.style ~= editStyle)
      set(t.equipped, "hidden", t.style ~= equipped)
    end

    local names = saved.groupNames()
    for i, r in ipairs(listRows) do
      local name = names[i]
      r.name = name
      hideAll({ r.hit, r.title, r.count }, name == nil)
      local group = name and saved.group(name)
      set(r.shared, "hidden", group == nil or not group.shared)
      set(r.bar, "hidden", name ~= selected)
      if group ~= nil then
        set(r.hit, "rgb", name == selected and COLOURS.line or COLOURS.panel)
        set(r.title, "content", group.title)
        set(r.title, "rgb", name == selected and COLOURS.text or COLOURS.mutedText)
        set(r.count, "content", tostring(#saved.keys(name, editStyle)))
      end
    end
    newGroup.group.set("hidden", #names >= #listRows)
    newGroup.group.place(16, LIST_Y + #names * LIST_ROW + 12)

    local group = saved.group(selected)
    local custom = indexOf(settings.CUSTOM_GROUPS, selected) ~= nil
    set(titleText, "hidden", custom)
    set(titleText, "content", group.title)
    set(nameField, "hidden", not custom)
    if custom and nameFor ~= selected then
      nameFor = selected
      nameField.content = group.title
    end
    if not custom then
      nameFor = nil
    end
    deleteButton.group.set("hidden", not custom)
    set(deleteButton.label, "content", confirmDelete and "Click to delete" or "Delete")
    showSize(group)
    showPerRow(group)
    local columns = group.grow == "left" or group.grow == "right"
    set(perRowLabel, "content", columns and "Icons per column" or "Icons per row")
    showSettingChoices(group)

    local models = knownTiles(saved.keys(selected, editStyle))
    count = math.min(#models, settings.MAX_GROUP_KEYS)
    for i, t in ipairs(editorTiles) do
      local model = models[i]
      t.key = model and model.key
      if model == nil then
        t.group.set("hidden", true)
      else
        t.x, t.y = slotPos(i)
        t.group.place(t.x, t.y)
        hideAll({ t.edge, t.bg }, false)
        draw.iconOrInitials(t.icon, t.initials, model)
      end
    end
    plus.place(slotPos(count + 1))
    plus.set("hidden", count >= settings.MAX_GROUP_KEYS)
    local rows = math.max(1, (count + (count < settings.MAX_GROUP_KEYS and 1 or 0) + GRID_PER_ROW - 1) // GRID_PER_ROW)
    draw.pos(hint, DETAIL_X, GRID_Y + rows * STEP + 8)
  end

  -- Drop feedback: a swap outline or an insertion line.
  local swapBox = outline(page, COLOURS.accent, 2)
  local insertLine = rect(page, COLOURS.accent, 0, 0, 2, 0)

  local function hideDragFeedback()
    set(insertLine, "hidden", true)
    hideAll(swapBox, true)
  end
  hideDragFeedback()

  -- The drop target under page position (px, py), or nil off the tile grid.
  local function targetAt(px, py)
    local gx = px - DETAIL_X
    local gy = py - GRID_Y
    local rows = math.max(1, (count + GRID_PER_ROW - 1) // GRID_PER_ROW)
    if gx < -10 or gx > DETAIL_W or gy < -10 or gy > rows * STEP + 10 then
      return nil
    end
    return editor.gridDropTarget({ count = count, step = STEP, size = TILE, perRow = GRID_PER_ROW }, gx, gy)
  end

  -- The target under the cursor during a drag.
  local dropTarget = nil

  local function showDragFeedback(px, py)
    local target = targetAt(px, py)
    dropTarget = target
    local swap = target ~= nil and target.kind == "swap"
    hideAll(swapBox, not swap)
    set(insertLine, "hidden", target == nil or swap)
    if target == nil then
      return
    end
    local x, y = slotPos(target.index)
    if swap then
      placeOutline(swapBox, x, y, TILE, TILE)
    else
      draw.pos(insertLine, x - GAP, y - 4)
      draw.size(insertLine, 2, TILE + 8)
    end
  end

  -- Tile menu: one Remove row under the clicked tile.
  local menu = ui.Layer.new(page)
  menu:SetSize(140, 30)
  hitArea(rect(menu, COLOURS.border, 0, 0, 140, 30))
  local menuKey = nil
  button(menu, "Remove", 1, 1, 138, 28, "dark", function()
    if menuKey ~= nil then
      saved.remove(menuKey, editStyle)
      closePopups()
      changed()
    end
  end)

  local function openMenu(t)
    menuKey = t.key
    menu:SetPos(t.group.x, math.min(t.group.y + TILE + 4, PAGE_H - 30))
    set(menu, "hidden", false)
  end

  editorDrag = dragdrop.create(page, TILE // 2, {
    press = function(t)
      if t.key == nil then
        return false
      end
      closePopups()
      return true
    end,
    ghost = function(t)
      return knownTiles({ t.key })[1]
    end,
    start = function(t)
      t.group.set("alpha", 0.3)
    end,
    move = function(_, px, py)
      showDragFeedback(px, py)
    end,
    drop = function(t)
      if dropTarget == nil then
        return
      end
      local action = editor.dropAction(saved.keys(selected, editStyle), t.key, dropTarget)
      if action == nil then
        return
      end
      if action.op == "swap" then
        saved.swap(t.key, action.other, selected, editStyle)
      else
        saved.move(t.key, selected, editStyle, action.index)
      end
      changed()
    end,
    click = openMenu,
    finish = function(t)
      t.group.set("alpha", 1)
      dropTarget = nil
      hideDragFeedback()
    end,
  })
  for _, t in ipairs(editorTiles) do
    editorDrag.attach(t)
  end

  -- Picker: known abilities under the "+" tile, in sections, one combat style tab at a time, narrowed by a
  -- search box. It opens on the style being edited and stays open for several adds. A search covers every
  -- style.
  local picker = ui.Layer.new(page)
  local pickerRows = {}
  local pickerTabs = {}
  local pickerOpen = false
  local pickerStyle = nil
  local query = ""
  local MAX_PICKER_ROWS = 14
  picker:SetSize(PICKER_WIDTH, PICKER_HEAD + MAX_PICKER_ROWS * PICKER_ROW + 2)
  local pickerEdge = hitArea(rect(picker, COLOURS.border, 0, 0, PICKER_WIDTH, 0))
  local pickerBg = rect(picker, COLOURS.popup, 1, 1, PICKER_WIDTH - 2, 0)
  rect(picker, COLOURS.line, 1, PICKER_HEAD, PICKER_WIDTH - 2, 1)
  local search = draw.inputField(picker, 10, 6, PICKER_WIDTH - 49, 24, 30, true)
  set(search, "emptyText", "Find an ability")
  -- The field also reports its contents on Enter, Esc and focus loss, which can come after the picker closed.
  on(search, "ONCONTENTCHANGED", function(_, _, contents)
    query = (contents or ""):lower()
    if not pickerOpen then
      return
    end
    if query ~= "" then
      pickerStyle = nil
    end
    fillPicker()
  end)
  local pickerTabX = 10
  for _, tab in ipairs(PICKER_TAB_LIST) do
    local hit = hitArea(rect(picker, COLOURS.popup, pickerTabX, PICKER_SEARCH, tab.width, PICKER_TABS))
    local t = {
      style = tab.style,
      label = text(picker, FONTS.body, ui.AlignMode.CENTRE, pickerTabX, PICKER_SEARCH, tab.width, PICKER_TABS - 2),
      underline = rect(picker, COLOURS.accent, pickerTabX, PICKER_HEAD - 2, tab.width, 2),
    }
    set(t.label, "content", tab.label)
    on(hit, "ONCLICK", function()
      pickerStyle = t.style
      fillPicker()
    end)
    pickerTabs[#pickerTabs + 1] = t
    pickerTabX = pickerTabX + tab.width
  end
  draw.closeButton(picker, PICKER_WIDTH - 29, 8, function()
    closePopups()
  end)
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
    on(r.bg, "ONMOUSEOVER", function()
      set(r.hover, "hidden", r.key == nil)
    end)
    on(r.bg, "ONMOUSELEAVE", function()
      set(r.hover, "hidden", true)
    end)
    on(r.bg, "ONCLICK", function()
      if r.key == nil or not pickerOpen then
        return
      end
      saved.add(selected, editStyle, r.key)
      changed()
      fillPicker()
    end)
    pickerRows[i] = r
  end

  -- Every ability fired this session, saved as seen, or in src/presets, sorted by name, and its tile model.
  local function allKnownKeys()
    local keys = {}
    local seen = {}
    for _, key in ipairs(tracker.known()) do
      keys[#keys + 1], seen[key] = key, true
    end
    for _, source in ipairs({ saved.known(), presets.INFO }) do
      for key in pairs(source) do
        if not seen[key] then
          keys[#keys + 1], seen[key] = key, true
        end
      end
    end
    local models = {}
    for _, t in ipairs(knownTiles(keys)) do
      models[t.key] = t
    end
    table.sort(keys, function(a, b)
      return models[a].name < models[b].name
    end)
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
        if models[key].name:lower():find(query, 1, true) then
          matching[#matching + 1] = key
        end
      end
      keys = matching
    end
    local entries = {}
    local groupLists = {}
    for _, name in ipairs(saved.groupNames()) do
      groupLists[#groupLists + 1] = { name = name, title = saved.group(name).title, keys = saved.keys(name, editStyle) }
    end
    for _, section in ipairs(editor.pickerSections(selected, groupLists, keys, pickerStyle)) do
      if #section.keys > 0 then
        entries[#entries + 1] = { title = section.title }
        for _, key in ipairs(section.keys) do
          entries[#entries + 1] = { key = key, name = models[key].name }
        end
      end
    end
    if #entries == 0 then
      entries[1] = { title = query ~= "" and "No ability matches" or "Use an ability to add it here" }
    end
    -- Past the last row, a note counts the abilities left out and points to the search box.
    if #entries > MAX_PICKER_ROWS then
      local hidden = 0
      for i = MAX_PICKER_ROWS, #entries do
        if entries[i].key ~= nil then
          hidden = hidden + 1
        end
      end
      entries[MAX_PICKER_ROWS] = { title = hidden .. " more. Search to find them." }
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
        if icon ~= nil then
          set(r.icon, "sprite", icon)
        end
      end
    end
    local shown = math.min(#entries, MAX_PICKER_ROWS)
    local height = PICKER_HEAD + shown * PICKER_ROW + 2
    pickerEdge:SetSize(PICKER_WIDTH, height)
    pickerBg:SetSize(PICKER_WIDTH - 2, height - 2)
    -- Under the "+" tile, raised as far as it must be to fit on the page.
    draw.pos(picker, math.min(plus.x, PAGE_W - PICKER_WIDTH - 8), math.min(plus.y + TILE + 4, PAGE_H - height))
  end

  function openPicker()
    local wasOpen = pickerOpen
    closePopups()
    if wasOpen then
      return
    end
    pickerOpen = true
    pickerStyle = editStyle
    if query ~= "" then
      query = ""
      search.content = ""
    end
    fillPicker()
    set(picker, "hidden", false)
  end

  function closePopups()
    buffsPage.close()
    set(menu, "hidden", true)
    set(picker, "hidden", true)
    pickerOpen = false
    menuKey = nil
  end

  -- Buffs page ----------------------------------------------------------------------------------------

  local buffsTooltip = deps.view.tooltip(root)
  buffsPage = buffspage.create(pages.buffs, PAGE_W, PAGE_H, {
    saved = saved,
    info = deps.auraInfo,
    catalog = catalog,
    describe = deps.describe,
    learn = deps.learnName,
    tooltip = buffsTooltip,
    toScreen = function(px, py)
      return window.root.x + PAGE_X + px, window.root.y + PAGE_Y + py
    end,
    refresh = deps.refresh,
  })

  -- Appearance page ----------------------------------------------------------------------------------

  local pageDeps = {
    saved = saved,
    view = deps.view,
    tooltip = buffsTooltip,
    auraInfo = deps.auraInfo,
    tracker = tracker,
    refresh = deps.refresh,
  }
  appearance = appearancepage.create(pages.appearance, PAGE_W, PAGE_H, pageDeps)
  bars = appearancepage.bars(pages.bars, PAGE_W, PAGE_H, pageDeps)
  local showHide = { { id = false, label = "Show" }, { id = true, label = "Hide" } }
  appearance.choiceRow(buffsPage.display, 24, 18, PAGE_W - 48, "Game buff bars", showHide, "hideBuffBars", 120)
  local auraIcons = { { id = false, label = "Plain" }, { id = true, label = "With bars" } }
  appearance.choiceRow(buffsPage.display, 24, 68, PAGE_W - 48, "Aura icons", auraIcons, "auraBars", 120)

  -- Edit mode ----------------------------------------------------------------------------------------

  local resetPositions, openWindow
  local editMode = editmode.create(root, {
    saved = saved,
    elements = elements,
    view = deps.view,
    label = function(name)
      local group = saved.group(name)
      return group and group.title
    end,
    reset = function()
      resetPositions()
    end,
    done = function()
      openWindow()
    end,
  })

  -- The open Reset positions confirm, or nil. It sits over the screen, so edit mode's toolbar can open it too.
  local confirm = nil

  local function closeConfirm()
    if confirm ~= nil then
      confirm:Destroy()
      confirm = nil
    end
  end

  local windowOpen = false

  function closeWindow()
    closeConfirm()
    editorDrag.cancel()
    appearance.cancel()
    bars.cancel()
    closePopups()
    confirmDelete = false
    windowOpen = false
  end

  function resetPositions()
    closePopups()
    closeConfirm()
    confirm = prettyui.Confirm.new(root, {
      title = "Reset positions",
      body = "Every frame, bar, ability group and aura row goes back to its default spot. "
        .. "Your groups and settings stay.",
      cancelLabel = "Cancel",
      confirmLabel = "Reset positions",
      onConfirm = function()
        confirm = nil
        saved.resetPositions()
        editMode.placeAll()
      end,
      onCancel = function()
        confirm = nil
      end,
    })
  end

  -- Footer --------------------------------------------------------------------------------------------

  -- Edit mode closes the window, which covers the HUD, and its toolbar's Done returns to the window.
  local footerActions = {
    Done = function()
      window:Close()
    end,
    ["Reset positions"] = resetPositions,
    ["Edit mode"] = function()
      window:Close()
      editMode.open()
    end,
  }
  local footerX = CONTENT_W - FOOTER_GAP
  for _, label in ipairs(FOOTER_BUTTONS) do
    footerX = footerX - prettyui.FancyButton.getSize(label)
    window:AddFancyButton(label, footerActions[label], {
      x = footerX,
      y = CONTENT_H - FOOTER + (FOOTER - BUTTON_H) // 2,
      variant = label == "Done" and "positive" or "neutral",
    })
    footerX = footerX - FOOTER_GAP
  end

  function openWindow()
    editStyle = tracker.style() or editStyle
    window:Show()
    windowOpen = true
    rebuildEditor()
    draw.control(pageTabs, "SetActive", 1)
    showPage("appearance")
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Moves a drag with the cursor. It runs every frame through Event.Draw so a drag keeps up with the mouse,
  -- and on Event.Logic as well in case Draw does not fire. Each returns before reading the mouse unless a
  -- press is held.
  local function followCursor()
    buffsPage.follow()
    editorDrag.follow()
    appearance.follow()
    bars.follow()
  end
  Event.Draw.Subscribe("runeuiOptions", followCursor)
  Event.Logic.Subscribe("runeuiOptions", followCursor)

  Event.KeyDown.Subscribe("runeuiOptions", function(e)
    if e.gameKey ~= GameKey.ESCAPE then
      return
    end
    if confirm ~= nil then
      closeConfirm()
    elseif editMode.editing() then
      editMode.escape()
    elseif pickerOpen or menuKey ~= nil or buffsPage.popupOpen() then
      closePopups()
    elseif windowOpen then
      window:Close()
    end
  end)

  Event.ContentLayerReady.Subscribe("runeuiRibbon", function(e)
    prettyui.FancyButton.new(e.component, "Options", openWindow, { x = 10, y = 10 })
  end)

  editMode.placeAll()
  window:Close()

  return {
    placeAll = editMode.placeAll,
    redrawBuffs = function()
      if windowOpen and currentPage == "buffs" then
        buffsPage.redraw()
      end
    end,
    shutdown = function()
      closeConfirm()
      buffsPage.destroy()
      window:Destroy()
      editMode.shutdown()
    end,
  }
end

return options
