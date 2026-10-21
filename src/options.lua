-- The options window and its ribbon button: a sidebar of pages, a cooldown manager with combat style tabs, a
-- group list with New group, and the chosen group's display settings and abilities with a "+" picker, drag to
-- swap or insert and a Remove menu; the src/buffspage Buffs page, resource bar steppers, appearance choices, the reset
-- dialog, and a footer toggle into src/editmode.
local appearancepage = require("src/appearancepage")
local buffspage = require("src/buffspage")
local dragdrop = require("src/dragdrop")
local draw = require("src/draw")
local editmode = require("src/editmode")
local editor = require("src/editor")
local presets = require("src/presets")
local settings = require("src/settings")

local options = {}

local set, rect, text, outline, placeOutline = draw.set, draw.rect, draw.windowText, draw.outline, draw.placeOutline
local hideAll, hitArea, on, button = draw.hideAll, draw.hitArea, draw.on, draw.button
local FONTS, COLOURS = draw.FONTS, draw.WINDOW

local WIDTH, HEIGHT = 900, 620
-- The sidebar's brand sits above its menu rows; pages take the window's full height above the footer.
local SIDEBAR, BRAND, NAV_ROW, FOOTER = 200, 64, 42, 56
local PAGE_X, PAGE_Y = SIDEBAR + 1, 1
local PAGE_W = WIDTH - PAGE_X - 1
local PAGE_H = HEIGHT - PAGE_Y - FOOTER - 1
local GAP = 2
-- Cooldown manager layout: style tabs across the top, the group list on the left, and the chosen group's
-- setting rows then its ability tiles, in rows of GRID_PER_ROW, on the right.
local STYLE_TABS = {
  { label = "Necromancy", style = "necromancy", width = 110 }, { label = "Magic", style = "magic", width = 80 },
  { label = "Ranged", style = "ranged", width = 84 }, { label = "Melee", style = "melee", width = 76 },
}
local TABS_H, LIST_W, LIST_Y, LIST_ROW = 44, 170, 56, 44
local DETAIL_X = LIST_W + 24
local DETAIL_W = PAGE_W - DETAIL_X - 24
local SETTING_H, SETTING_ROWS = 46, 5
local TILE = 36
local STEP = TILE + GAP
local GRID_Y = LIST_Y + SETTING_ROWS * SETTING_H + 16
local GRID_PER_ROW = (DETAIL_W + GAP) // STEP
local PICKER_WIDTH, PICKER_ROW, PICKER_SEARCH, PICKER_TABS = 340, 26, 36, 34
local PICKER_HEAD = PICKER_SEARCH + PICKER_TABS
-- Picker tabs left to right; style nil lists every style.
local PICKER_TAB_LIST = {
  { label = "All", width = 34 }, { label = "Necromancy", style = "necromancy", width = 100 },
  { label = "Magic", style = "magic", width = 58 }, { label = "Ranged", style = "ranged", width = 66 },
  { label = "Melee", style = "melee", width = 58 },
}

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
end

-- deps: { saved = src/settings, tracker = src/cooldowns tracker, elements = src/view elements by name,
-- view = src/view, auraInfo(sprite) naming an aura icon, refresh = function redrawing the HUD }. Returns
-- { placeAll, redrawBuffs, shutdown }; placeAll places the HUD and edit mode's overlays from the saved
-- positions and anchors, and redrawBuffs redraws the Buffs page while it is shown.
function options.create(root, deps)
  local saved, tracker, elements = deps.saved, deps.tracker, deps.elements

  local window = ui.Layer.new(root)
  window:SetSize(WIDTH, HEIGHT)
  window:SetPos(-WIDTH // 2, -HEIGHT // 2, 0.5, 0.5)
  set(window, "hidden", true)

  -- Each page draws its own background, so the Appearance preview can show the game through the window.
  placeOutline(outline(window, COLOURS.edge, 1), 1, 1, WIDTH - 2, HEIGHT - 2)
  hitArea(rect(window, COLOURS.sidebar, 1, 1, SIDEBAR - 1, HEIGHT - 2))
  rect(window, COLOURS.line, SIDEBAR, 1, 1, HEIGHT - 2)
  rect(window, COLOURS.line, PAGE_X, HEIGHT - FOOTER - 1, PAGE_W, 1)
  hitArea(rect(window, COLOURS.panel, PAGE_X, HEIGHT - FOOTER, PAGE_W, FOOTER - 1))
  local brand = text(window, id.Font.CINZEL_18PT_BOLD, ui.AlignMode.TOPLEFT, 18, 1, SIDEBAR - 20, BRAND)
  set(brand, "content", "RuneUI")
  set(brand, "rgb", COLOURS.accent)

  local closePopups, rebuildEditor, fillPicker, openPicker, buffsPage, editorDrag

  local function changed()
    rebuildEditor()
    deps.refresh()
  end

  -- Pages ---------------------------------------------------------------------------------------------

  local pages, navRows = {}, {}
  local PAGE_LIST = {
    { id = "appearance", label = "Appearance" },
    { id = "cooldowns", label = "Cooldown manager" },
    { id = "buffs", label = "Buffs" },
    { id = "resource", label = "Resource bar" },
  }

  local currentPage = nil

  local function showPage(pageID)
    closePopups()
    currentPage = pageID
    if pageID == "buffs" then buffsPage.redraw() end
    for _, entry in ipairs(PAGE_LIST) do
      local active = entry.id == pageID
      set(pages[entry.id], "hidden", not active)
      local row = navRows[entry.id]
      set(row.bg, "hidden", not active)
      set(row.bar, "hidden", not active)
      set(row.label, "rgb", active and COLOURS.accent or COLOURS.text)
    end
  end

  -- Menu rows: the chosen one has a lighter fill, gold text and a gold bar on its left.
  for i, entry in ipairs(PAGE_LIST) do
    local y = BRAND + (i - 1) * NAV_ROW
    local row = {
      hit = hitArea(rect(window, COLOURS.sidebar, 1, y, SIDEBAR - 1, NAV_ROW)),
      bg = rect(window, COLOURS.rowAlt, 1, y, SIDEBAR - 1, NAV_ROW),
      bar = rect(window, COLOURS.accent, 1, y, 4, NAV_ROW),
      label = text(window, FONTS.body, ui.AlignMode.TOPLEFT, 18, y, SIDEBAR - 24, NAV_ROW),
    }
    set(row.label, "content", entry.label)
    on(row.hit, "ONCLICK", function() showPage(entry.id) end)
    navRows[entry.id] = row
    local page = ui.Layer.new(window)
    page:SetSize(PAGE_W, PAGE_H)
    page:SetPos(PAGE_X, PAGE_Y)
    if entry.id ~= "appearance" then hitArea(rect(page, COLOURS.panel, 0, 0, PAGE_W, PAGE_H)) end
    pages[entry.id] = page
  end

  -- Cooldown manager ---------------------------------------------------------------------------------

  local page = pages.cooldowns
  -- The style whose lists the page edits, the group shown in the detail pane, and whether its Delete button
  -- has been clicked once.
  local editStyle, selected, confirmDelete = "magic", "major", false

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
      if r.name == nil then return end
      selected, confirmDelete = r.name, false
      closePopups()
      rebuildEditor()
    end)
    listRows[i] = r
  end
  local newGroup = button(page, "New group", 16, 0, LIST_W - 32, 32, "dark", function()
    local name = saved.addGroup()
    if name == nil then return end
    selected, confirmDelete = name, false
    closePopups()
    changed()
  end)

  -- Detail pane: Name, Icon size, Icons per row, Grow and Abilities rows over the group's ability tiles.
  local function rowY(i) return LIST_Y + (i - 1) * SETTING_H end
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
  local titleText = text(page, FONTS.body, ui.AlignMode.BOTTOMRIGHT, DETAIL_X + 120, rowY(1),
    detailRight - DETAIL_X - 120, SETTING_H)
  local nameField = ui.InputField.new(page)
  nameField:SetPos(DETAIL_X + 120, rowY(1) + 11)
  nameField:SetSize(detailRight - 126 - DETAIL_X - 120, 24)
  nameField:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, 20)
  if id.StyleSheet.INPUT_SEARCHBOX_24PX ~= nil then
    set(nameField, "stylesheetID", id.StyleSheet.INPUT_SEARCHBOX_24PX)
  end
  -- The group whose title the field shows; a change arriving after another group was chosen is ignored.
  local nameFor = nil
  on(nameField, "ONCONTENTCHANGED", function(_, _, contents)
    if nameFor == nil or nameFor ~= selected or saved.group(nameFor) == nil then return end
    local before = saved.group(nameFor).title
    saved.setGroup(nameFor, "title", contents or "")
    if saved.group(nameFor).title ~= before then changed() end
  end)
  local deleteButton
  deleteButton = button(page, "Delete", detailRight - 120, rowY(1) + 9, 120, 28, "dark", function()
    if saved.group(selected) == nil then return end
    if not confirmDelete then
      confirmDelete = true
      set(deleteButton.label, "content", "Click to delete")
      return
    end
    saved.deleteGroup(selected)
    selected, confirmDelete = "major", false
    changed()
  end)

  -- A row's - number + stepper moving field by 1 from low to high, its number typed; returns a function showing
  -- a group's value.
  local function stepper(i, field, low, high)
    local function choose(n)
      local group = saved.group(selected)
      if group == nil or n == group[field] then return end
      saved.setGroup(selected, field, n)
      changed()
    end
    local value = draw.numberField(page, detailRight - 92, rowY(i) + 11, 56, 24, low, high, choose)
    local function step(d)
      local group = saved.group(selected)
      if group ~= nil then choose(math.max(low, math.min(high, group[field] + d))) end
    end
    button(page, "-", detailRight - 124, rowY(i) + 9, 28, 28, "dark", function() step(-1) end)
    button(page, "+", detailRight - 28, rowY(i) + 9, 28, 28, "dark", function() step(1) end)
    return function(group) value.show(group[field]) end
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
        if saved.group(selected) == nil then return end
        saved.setGroup(selected, field, option.value)
        changed()
      end)
      b.value = option.value
      row.buttons[#row.buttons + 1] = b
    end
    settingChoices[#settingChoices + 1] = row
  end
  settingLabel(4, "Grow")
  settingChoice(4, "grow", { { value = "up", label = "Up" }, { value = "down", label = "Down" },
    { value = "left", label = "Left" }, { value = "right", label = "Right" } }, 64)
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
      group = group, size = TILE,
      edge = group.add(hitArea(rect(page, COLOURS.border, 0, 0, TILE, TILE)), 0, 0),
      bg = group.add(rect(page, COLOURS.editorTile, 0, 0, TILE - 2, TILE - 2), 1, 1),
      icon = group.add(ui.Sprite.new(page), 1, 1),
      initials = group.add(text(page, FONTS.small, ui.AlignMode.TOPLEFT, 0, 0, TILE - 6, 12), 4, TILE - 15),
    }
    t.icon:SetSize(TILE - 2, TILE - 2)
    return t
  end

  local editorTiles = {}
  for i = 1, settings.MAX_GROUP_KEYS do editorTiles[i] = tile() end
  local count = 0

  -- The "+" tile as a draw.group.
  local plus = draw.group()
  local plusEdge = plus.add(hitArea(rect(page, COLOURS.mutedText, 0, 0, TILE, TILE)), 0, 0)
  plus.add(rect(page, COLOURS.sidebar, 0, 0, TILE - 2, TILE - 2), 1, 1)
  local glyph = plus.add(text(page, FONTS.seconds, ui.AlignMode.CENTRE, 0, 0, TILE, TILE), 0, 0)
  set(glyph, "content", "+")
  set(glyph, "rgb", COLOURS.accent)
  on(plusEdge, "ONCLICK", function() openPicker() end)

  local hint = text(page, FONTS.small, ui.AlignMode.TOPLEFT, DETAIL_X, 0, DETAIL_W, 14)
  set(hint, "content", "Drag to reorder. Click + to add or move an ability here. Click an icon to remove it.")
  set(hint, "rgb", COLOURS.mutedText)

  local function knownTiles(keys)
    return tracker.tiles(keys, {})
  end

  -- Marks each choice row's option for group's value chosen.
  local function showSettingChoices(group)
    for _, row in ipairs(settingChoices) do
      for _, b in ipairs(row.buttons) do draw.showOption(b, b.value == group[row.field]) end
    end
  end

  function rebuildEditor()
    if saved.group(selected) == nil then selected = "major" end
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
    if not custom then nameFor = nil end
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
    local gx, gy = px - DETAIL_X, py - GRID_Y
    local rows = math.max(1, (count + GRID_PER_ROW - 1) // GRID_PER_ROW)
    if gx < -10 or gx > DETAIL_W or gy < -10 or gy > rows * STEP + 10 then return nil end
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
    if target == nil then return end
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
      if t.key == nil then return false end
      closePopups()
      return true
    end,
    ghost = function(t) return knownTiles({ t.key })[1] end,
    start = function(t) t.group.set("alpha", 0.3) end,
    move = function(_, px, py) showDragFeedback(px, py) end,
    drop = function(t)
      if dropTarget == nil then return end
      local action = editor.dropAction(saved.keys(selected, editStyle), t.key, dropTarget)
      if action == nil then return end
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
  for _, t in ipairs(editorTiles) do editorDrag.attach(t) end

  -- Picker: known abilities under the "+" tile, in sections, one combat style tab at a time, narrowed by a
  -- search box. It opens on the style being edited and stays open for several adds. A search covers every
  -- style.
  local picker = ui.Layer.new(page)
  local pickerRows, pickerTabs = {}, {}
  local pickerOpen, pickerStyle, query = false, nil, ""
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
    if not pickerOpen then return end
    if query ~= "" then pickerStyle = nil end
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
      if r.key == nil or not pickerOpen then return end
      saved.add(selected, editStyle, r.key)
      changed()
      fillPicker()
    end)
    pickerRows[i] = r
  end

  -- Every ability fired this session, saved as seen, or in src/presets, sorted by name, and its tile model.
  local function allKnownKeys()
    local keys, seen = {}, {}
    for _, key in ipairs(tracker.known()) do
      keys[#keys + 1], seen[key] = key, true
    end
    for _, source in ipairs({ saved.known(), presets.INFO }) do
      for key in pairs(source) do
        if not seen[key] then keys[#keys + 1], seen[key] = key, true end
      end
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
    local groupLists = {}
    for _, name in ipairs(saved.groupNames()) do
      groupLists[#groupLists + 1] = { name = name, title = saved.group(name).title, keys = saved.keys(name, editStyle) }
    end
    for _, section in ipairs(editor.pickerSections(selected, groupLists, keys, pickerStyle)) do
      if #section.keys > 0 then
        entries[#entries + 1] = { title = section.title }
        for _, key in ipairs(section.keys) do entries[#entries + 1] = { key = key, name = models[key].name } end
      end
    end
    if #entries == 0 then
      entries[1] = { title = query ~= "" and "No ability matches" or "Use an ability to add it here" }
    end
    -- Past the last row, a note counts the abilities left out and points to the search box.
    if #entries > MAX_PICKER_ROWS then
      local hidden = 0
      for i = MAX_PICKER_ROWS, #entries do
        if entries[i].key ~= nil then hidden = hidden + 1 end
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
        if icon ~= nil then set(r.icon, "sprite", icon) end
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
    if wasOpen then return end
    pickerOpen, pickerStyle = true, editStyle
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
    pickerOpen, menuKey = false, nil
  end

  -- Buffs page ----------------------------------------------------------------------------------------

  local buffsTooltip = deps.view.tooltip(root)
  buffsPage = buffspage.create(pages.buffs, PAGE_W, PAGE_H, {
    saved = saved,
    info = deps.auraInfo,
    tooltip = buffsTooltip,
    toScreen = function(px, py) return window.x + PAGE_X + px, window.y + PAGE_Y + py end,
    refresh = deps.refresh,
  })

  -- Resource bar page ---------------------------------------------------------------------------------

  -- Each row a - number + stepper from low to high reading value() and saving through save(n).
  local resourcePage = pages.resource
  local resourceRows = {}
  local function resourceRow(i, label, low, high, value, save)
    local ry = 18 + (i - 1) * 50
    rect(resourcePage, i % 2 == 1 and COLOURS.row or COLOURS.rowAlt, 24, ry, PAGE_W - 48, 50)
    set(text(resourcePage, FONTS.body, ui.AlignMode.TOPLEFT, 40, ry, 200, 50), "content", label)
    local right = PAGE_W - 40
    local field
    local function choose(n)
      if n == value() then return end
      save(n)
      field.show(value())
      deps.refresh()
    end
    field = draw.numberField(resourcePage, right - 104, ry + 13, 56, 24, low, high, choose)
    button(resourcePage, "-", right - 136, ry + 11, 28, 28, "dark", function() choose(math.max(low, value() - 1)) end)
    button(resourcePage, "+", right - 44, ry + 11, 28, 28, "dark", function() choose(math.min(high, value() + 1)) end)
    resourceRows[#resourceRows + 1] = function() field.show(value()) end
  end
  for i, entry in ipairs({ { id = "threshold", label = "Threshold" }, { id = "ultimate", label = "Ultimate" } }) do
    resourceRow(i, entry.label .. " marker", 0, 100, function() return saved.markers()[entry.id] end,
      function(n) saved.setMarker(entry.id, n) end)
  end
  for i, entry in ipairs({ { field = "barWidth", label = "Bar width", range = settings.BAR_WIDTH },
    { field = "barHeight", label = "Bar height", range = settings.BAR_HEIGHT } }) do
    resourceRow(i + 2, entry.label, entry.range.min, entry.range.max,
      function() return saved.appearance()[entry.field] end, function(n) saved.setAppearance(entry.field, n) end)
  end

  -- Appearance page ----------------------------------------------------------------------------------

  local appearance = appearancepage.create(pages.appearance, PAGE_W, PAGE_H, {
    saved = saved, view = deps.view, tooltip = buffsTooltip, auraInfo = deps.auraInfo, tracker = tracker,
    refresh = deps.refresh,
  })
  local showHide = { { id = false, label = "Show" }, { id = true, label = "Hide" } }
  appearance.choiceRow(buffsPage.display, 24, 18, PAGE_W - 48, "Game buff bars", showHide, "hideBuffBars", 120)
  local auraIcons = { { id = false, label = "Plain" }, { id = true, label = "With bars" } }
  appearance.choiceRow(buffsPage.display, 24, 68, PAGE_W - 48, "Aura icons", auraIcons, "auraBars", 120)

  -- Edit mode ----------------------------------------------------------------------------------------

  local resetPositions, openWindow
  local editMode = editmode.create(root, {
    saved = saved, elements = elements, view = deps.view,
    label = function(name)
      local group = saved.group(name)
      return group and group.title
    end,
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
    "Every frame, bar, ability group and aura row goes back to its default spot. Your groups and settings stay.")
  set(dialogBody, "rgb", COLOURS.dimText)
  rect(dialog, COLOURS.line, dialogX + 1, dialogY + DIALOG_H - 56, DIALOG_W - 2, 1)
  local dialogOpen = false

  local function closeDialog()
    dialogOpen = false
    set(dialog, "hidden", true)
  end
  closeDialog()

  local buttonsY = dialogY + DIALOG_H - 44
  button(dialog, "Cancel", dialogX + DIALOG_W - 264, buttonsY, 90, 32, "dark", closeDialog)
  button(dialog, "Reset positions", dialogX + DIALOG_W - 166, buttonsY, 150, 32, "gold", function()
    closeDialog()
    saved.resetPositions()
    editMode.placeAll()
  end)

  local windowOpen = false

  local function closeWindow()
    closeDialog()
    editorDrag.cancel()
    appearance.cancel()
    closePopups()
    confirmDelete = false
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

  -- An unticked Edit mode checkbox: edit mode hides the window, which covers the HUD, and its toolbar's Done
  -- returns to the window.
  local footerY = HEIGHT - FOOTER
  local toggleHit = hitArea(rect(window, COLOURS.panel, PAGE_X + 16, footerY, 130, FOOTER))
  rect(window, COLOURS.bronze, PAGE_X + 24, footerY + 20, 16, 16)
  rect(window, COLOURS.sidebar, PAGE_X + 25, footerY + 21, 14, 14)
  local toggleLabel = text(window, FONTS.body, ui.AlignMode.TOPLEFT, PAGE_X + 50, footerY, 90, FOOTER)
  set(toggleLabel, "content", "Edit mode")
  on(toggleHit, "ONCLICK", function()
    closeWindow()
    editMode.open()
  end)
  button(window, "Reset positions", PAGE_X + 160, footerY + 12, 140, 32, "dark", resetPositions)
  button(window, "Done", WIDTH - 24 - 90, footerY + 12, 90, 32, "gold", closeWindow)

  function openWindow()
    for _, show in ipairs(resourceRows) do show() end
    appearance.open()
    editStyle = tracker.style() or editStyle
    rebuildEditor()
    showPage("appearance")
    windowOpen = true
    set(window, "hidden", false)
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Moves a drag with the cursor. It runs every frame through Event.Draw so a drag keeps up with the mouse,
  -- and on Event.Logic as well in case Draw does not fire. Each returns before reading the mouse unless a
  -- press is held.
  local function followCursor()
    buffsPage.follow()
    editorDrag.follow()
    appearance.follow()
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
    redrawBuffs = function()
      if windowOpen and currentPage == "buffs" then buffsPage.redraw() end
    end,
    shutdown = function()
      buffsPage.destroy()
      window:Destroy()
      editMode.shutdown()
      dialog:Destroy()
    end,
  }
end

return options
