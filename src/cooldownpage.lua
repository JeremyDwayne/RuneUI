-- The options window's Cooldown manager page: combat style tabs, a group list with New group, and the chosen
-- group's display settings and abilities with a "+" picker, drag to swap or insert, and a Remove menu.
local dragdrop = require("src/dragdrop")
local draw = require("src/draw")
local editor = require("src/editor")
local presets = require("src/presets")
local settings = require("src/settings")

local cooldownpage = {}

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

local GAP = 2
-- Style tabs across the top, the group list on the left, and the chosen group's setting rows then its ability
-- tiles, in rows of as many as fit, on the right.
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
local SETTING_H = 46
local SETTING_ROWS = 5
local TILE = 36
local STEP = TILE + GAP
local GRID_Y = LIST_Y + SETTING_ROWS * SETTING_H + 16
local PICKER_WIDTH = 340
local PICKER_ROW = 26
local PICKER_SEARCH = 36
local PICKER_TABS = 34
local PICKER_HEAD = PICKER_SEARCH + PICKER_TABS
local MAX_PICKER_ROWS = 14
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

-- page: the options window's page layer, width by height. deps: { saved = src/settings, tracker = src/cooldowns
-- tracker, refresh() redrawing the HUD }. Returns { open, rebuild, close, closePopups, popupOpen, follow }: open
-- shows the page on the equipped style; rebuild redraws it from settings; close ends a drag and closes its
-- popups, as when the window closes; popupOpen says whether the picker or menu is open; follow runs every
-- frame to move a drag.
function cooldownpage.create(page, width, height, deps)
  local saved = deps.saved
  local tracker = deps.tracker
  local DETAIL_W = width - DETAIL_X - 24
  local GRID_PER_ROW = (DETAIL_W + GAP) // STEP
  local manager = {}
  local fillPicker, openPicker, editorDrag

  local function changed()
    manager.rebuild()
    deps.refresh()
  end

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
      manager.closePopups()
      manager.rebuild()
    end)
    styleTabs[#styleTabs + 1] = t
    styleX = styleX + tab.width + 4
  end
  rect(page, COLOURS.line, 0, TABS_H, width, 1)

  -- Group list: one row per group in use, the chosen one lit with an accent bar, then New group.
  rect(page, COLOURS.line, LIST_W, TABS_H + 1, 1, height - TABS_H - 1)
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
      manager.closePopups()
      manager.rebuild()
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
    manager.closePopups()
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

  -- A row's - number + stepper moving field by 1 from low to high, its number typed. Returns the stepper.
  local function stepper(i, field, low, high)
    return draw.stepper(page, detailRight - draw.STEPPER_W, rowY(i) + 9, low, high, 1, function(n)
      local group = saved.group(selected)
      if group ~= nil and n ~= group[field] then
        saved.setGroup(selected, field, n)
        changed()
      end
    end)
  end
  settingLabel(2, "Icon size")
  local sizeStepper = stepper(2, "size", settings.SIZE_MIN, settings.SIZE_MAX)
  local perRowLabel = settingLabel(3, "Icons per row")
  local perRowStepper = stepper(3, "perRow", 1, settings.MAX_GROUP_KEYS)

  -- Rows of right-aligned draw.option buttons that save one display setting.
  local settingChoices = {}
  local function settingChoice(i, field, choices, optionW)
    local row = { field = field, buttons = {} }
    for k, option in ipairs(choices) do
      local x = detailRight - (#choices - k + 1) * (optionW + 4) + 4
      local b = draw.option(page, option.label, x, rowY(i) + 9, optionW, 28, function()
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

  function manager.rebuild()
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
    sizeStepper.show(group.size)
    perRowStepper.show(group.perRow)
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
      manager.closePopups()
      changed()
    end
  end)

  local function openMenu(t)
    menuKey = t.key
    menu:SetPos(t.group.x, math.min(t.group.y + TILE + 4, height - 30))
    set(menu, "hidden", false)
  end

  editorDrag = dragdrop.create(page, TILE // 2, {
    press = function(t)
      if t.key == nil then
        return false
      end
      manager.closePopups()
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
    manager.closePopups()
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
    local pickerH = PICKER_HEAD + shown * PICKER_ROW + 2
    pickerEdge:SetSize(PICKER_WIDTH, pickerH)
    pickerBg:SetSize(PICKER_WIDTH - 2, pickerH - 2)
    -- Under the "+" tile, raised as far as it must be to fit on the page.
    draw.pos(picker, math.min(plus.x, width - PICKER_WIDTH - 8), math.min(plus.y + TILE + 4, height - pickerH))
  end

  function openPicker()
    local wasOpen = pickerOpen
    manager.closePopups()
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

  function manager.closePopups()
    set(menu, "hidden", true)
    set(picker, "hidden", true)
    pickerOpen = false
    menuKey = nil
  end

  function manager.open()
    editStyle = tracker.style() or editStyle
    manager.rebuild()
  end

  function manager.close()
    editorDrag.cancel()
    manager.closePopups()
    confirmDelete = false
  end

  function manager.popupOpen()
    return pickerOpen or menuKey ~= nil
  end

  manager.follow = editorDrag.follow
  return manager
end

return cooldownpage
