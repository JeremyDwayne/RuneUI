-- The options window's Buffs page: tabs for buffs on you, debuffs on you, debuffs you inflict and display
-- options. Each icon tab holds wrapping groups of icons in their sorted order. Dragging an icon swaps it with
-- the icon it lands on or inserts it between two, within its group or into another, as the cooldown editor
-- does; clicking one opens a menu of the group moves, plus Keep up for upkeep buffs. Hovering shows the icon's
-- name. A group that is a HUD aura row sets its Icon size and Text size between its heading and its icons.
-- Each icon tab's Find button opens a src/aurasearch popup over every effect of the tab's kind the game
-- defines.
local auralists = require("src/auralists")
local aurasearch = require("src/aurasearch")
local dragdrop = require("src/dragdrop")
local controls = require("src/controls")
local draw = require("src/draw")
local editor = require("src/editor")
local search = require("src/search")
local savedappearance = require("src/savedappearance")
local style = require("src/style")

local buffspage = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local hitArea = draw.hitArea
local on = draw.on
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW
local SIZE = 30
local GAP = 3
local STEP = SIZE + GAP
-- Icons a tab can show, and Keep up marks the upkeep group can show.
local TILES = 120
local KEEP_MARKS = 24
local MARK = 11
-- Untracked and hidden icons draw dim inside a dashed box.
local DIM = 0.38
local MARGIN = 24
local TAB_Y = 14
local TAB_H = 28
local HEADER = 20
local PAD = 6
local MENU_W = 160
local MENU_ROW = 28
local FIND_W = 130
local FIND_H = 24
local SEARCH_Y = 84
local SEARCH_H = 440
-- A sized group's Icon size and Text size line: its height, and the x of each part from the group's left.
local SIZES_H = 36
local OPTION_H = 28
local ICON_X = 76
local TEXT_LABEL_X = 236
local TEXT_X = 312
local MATCH_X = 448
local MATCH_W = 104

-- Each group lists the sprites groups(...) files under kind and value: a buff row, or a debuff kind's
-- tracked or untracked list. row names the HUD aura row a group shows, whose sizes it sets. A tab's search
-- lists catalog rows of its kind.
local TABS = {
  {
    id = "buffs",
    label = "Buffs on you",
    w = 130,
    find = { label = "Find buffs", kind = "buff", empty = "Find a buff or boss" },
    groups = {
      {
        label = "Combat buffs",
        note = "Above the cooldowns row",
        kind = "buff",
        value = "combat",
        row = "combatBuffs",
      },
      {
        label = "Upkeep buffs",
        note = "Below the player frame. K keeps a tile while missing",
        kind = "buff",
        value = "upkeep",
        row = "upkeepBuffs",
      },
      { label = "Hidden", note = "Never shown", kind = "buff", value = "hidden", dim = true },
    },
  },
  {
    id = "player",
    label = "Debuffs on you",
    w = 140,
    find = { label = "Find debuffs", kind = "debuff", empty = "Find a debuff or boss" },
    groups = {
      {
        label = "Tracked",
        note = "Shown above the player frame",
        kind = "player",
        value = true,
        row = "playerDebuffs",
      },
      { label = "Not tracked", note = "Seen but not shown", kind = "player", value = false, dim = true },
    },
  },
  {
    id = "target",
    label = "Debuffs you inflict",
    w = 160,
    find = { label = "Find debuffs", kind = "target", empty = "Find a debuff or ability" },
    groups = {
      {
        label = "Tracked",
        note = "Shown above the target frame",
        kind = "target",
        value = true,
        row = "targetDebuffs",
      },
      { label = "Not tracked", note = "Seen but not shown", kind = "target", value = false, dim = true },
    },
  },
  { id = "display", label = "Display", w = 100 },
}
local MAX_GROUPS = 3

-- page: the options window's page layer, width by height. deps: { saved = src/settings, info(sprite) naming
-- an icon as src/icons does, tooltip = view.tooltip, toScreen(x, y) turning page into screen coordinates,
-- refresh() redrawing the HUD, catalog = src/catalog rows, describe(struct) reading a struct's description }.
-- Returns { display, redraw, follow, close, popupOpen }: display is the Display tab's layer for option
-- rows; redraw draws the page from settings; follow runs each frame to move a drag; close ends a drag and closes
-- the menu and the search; popupOpen says whether either is open.
function buffspage.create(page, width, height, deps)
  local saved = deps.saved
  local cols = (width - 2 * MARGIN - 2 * PAD + GAP) // STEP
  local tab = "buffs"
  -- The TABS entry of tab, from the last redraw.
  local tabDef = nil
  local redraw, closeMenu, drag, finder, openSearch

  -- Tabs ------------------------------------------------------------------------------------------------

  local tabParts = {}
  local tabX = MARGIN
  local tabGroup = controls.optionGroup(page)
  for _, def in ipairs(TABS) do
    tabParts[def.id] = controls.option(page, def.label, tabX, TAB_Y, def.w, TAB_H, function()
      closeMenu()
      finder.close()
      tab = def.id
      redraw()
    end, tabGroup)
    tabX = tabX + def.w + 6
  end

  local top = TAB_Y + TAB_H + 12
  local display = draw.new(ui.Layer, page)
  display:SetSize(width, height - top)
  display:SetPos(0, top)

  -- Sizes ----------------------------------------------------------------------------------------------

  local function changed()
    redraw()
    deps.refresh()
  end

  -- A sized group's Icon size and Text size line on its own layer, saving the fields of slot.def.row. Returns
  -- { layer, show(appearance) }.
  local function sizeLine(slot)
    local layer = draw.new(ui.Layer, page)
    layer:SetSize(width - 2 * MARGIN, SIZES_H)
    local function field(name)
      return slot.def.row .. name
    end
    local function textSize(appearance)
      local own = appearance[field("Text")]
      if own == "hud" then
        return style.ROLES[style.AURA_TEXT[slot.def.row]] + appearance.textStep
      end
      return own
    end
    local function save(name)
      return function(value)
        if value ~= saved.appearance()[field(name)] then
          saved.setAppearance(field(name), value)
          changed()
        end
      end
    end
    for _, label in ipairs({ { "Icon size", 0 }, { "Text size", TEXT_LABEL_X } }) do
      set(text(layer, FONTS.body, ui.AlignMode.TOPLEFT, label[2], 0, 80, SIZES_H), "content", label[1])
    end
    local y = (SIZES_H - OPTION_H) // 2
    local icon =
      controls.stepper(layer, ICON_X, y, savedappearance.AURA_ICON.min, savedappearance.AURA_ICON.max, 1, save("Icon"))
    local textStepper =
      controls.stepper(layer, TEXT_X, y, savedappearance.TEXT_SIZE.min, savedappearance.TEXT_SIZE.max, 1, save("Text"))
    local match = controls.option(layer, "Match HUD", MATCH_X, y, MATCH_W, OPTION_H, function()
      save("Text")("hud")
    end)
    return {
      layer = layer,
      show = function(appearance)
        local matched = appearance[field("Text")] == "hud"
        icon.show(appearance[field("Icon")])
        textStepper.show(textSize(appearance))
        textStepper.fade(matched)
        controls.showOption(match, matched)
      end,
    }
  end

  -- Groups ----------------------------------------------------------------------------------------------

  local slots = {}
  for i = 1, MAX_GROUPS do
    local slot = {
      label = text(page, FONTS.body, ui.AlignMode.TOPLEFT, MARGIN, 0, 200, 18),
      note = text(page, FONTS.small, ui.AlignMode.TOPLEFT, MARGIN + 140, 0, width - 2 * MARGIN - 140, 18),
      box = rect(page, COLOURS.row, MARGIN, 0, width - 2 * MARGIN, 0),
      dashes = draw.new(ui.Canvas, page),
    }
    set(slot.note, "rgb", COLOURS.mutedText)
    slot.dashes:SetSize(width, height)
    slot.dashes:SetPos(0, 0)
    slot.sizes = sizeLine(slot)
    slots[i] = slot
  end

  local findButton = controls.button(page, "", width - MARGIN - FIND_W, top - 4, FIND_W, FIND_H, "dark", function()
    openSearch()
  end)

  local tiles = {}
  for i = 1, TILES do
    local t = {
      edge = hitArea(rect(page, COLOURS.border, 0, 0, SIZE, SIZE)),
      icon = draw.new(ui.Sprite, page),
      size = SIZE,
    }
    t.icon:SetSize(SIZE - 2, SIZE - 2)
    tiles[i] = t
  end

  local marks = {}
  for i = 1, KEEP_MARKS do
    local m = { bg = rect(page, COLOURS.highlight, 0, 0, MARK, MARK) }
    m.label = text(page, FONTS.small, ui.AlignMode.CENTRE, 0, 0, MARK, MARK)
    set(m.label, "content", "K")
    set(m.label, "rgb", COLOURS.darkText)
    set(m.label, "isShadowed", false)
    marks[i] = m
  end

  -- Drop feedback: a swap outline or an insertion line.
  local swapBox = draw.outline(page, COLOURS.accent, 2)
  local insertLine = rect(page, COLOURS.accent, 0, 0, 2, SIZE + 8)

  local function hideDropFeedback()
    draw.hideAll(swapBox, true)
    set(insertLine, "hidden", true)
  end
  hideDropFeedback()

  -- Each kind's full display order, from the last redraw.
  local orders = {}

  local function sprites(groups, def)
    if def.kind == "buff" then
      return groups[def.value]
    end
    return def.value and groups[def.kind].tracked or groups[def.kind].untracked
  end

  -- The saved order kind of a group def: "buffs", "target" or "player".
  local function kindOf(def)
    return def.kind == "buff" and "buffs" or def.kind
  end

  -- Puts sprite in the group def describes.
  local function assign(def, sprite)
    if def.kind == "buff" then
      saved.setAuraCategory(sprite, def.value)
    else
      saved.setTracked(def.kind, sprite, def.value)
    end
  end

  -- Drops t's icon on target, a src/editor drop target, in slot's group: it joins that group at the target,
  -- or trades places and groups with the icon it lands on.
  local function place(t, slot, target)
    local kind = kindOf(t.def)
    local moved = auralists.drop(orders[kind], slot.list, t.sprite, target)
    if moved == nil then
      return
    end
    if slot.def ~= t.def then
      if moved.other ~= nil then
        assign(t.def, moved.other)
      end
      assign(slot.def, t.sprite)
    end
    saved.setOrder(kind, moved.order)
    changed()
  end

  -- Draws the page, unless an icon is being dragged, so a refresh cannot move the grab area.
  function redraw()
    if drag ~= nil and drag.dragging() then
      return
    end
    local choices = { target = saved.tracked("target"), player = saved.tracked("player") }
    local groups = auralists.groups(saved.auras(), choices, saved.orders())
    orders = groups.order
    for _, def in ipairs(TABS) do
      local active = def.id == tab
      if active then
        tabDef = def
      end
      controls.showOption(tabParts[def.id], active)
    end
    set(display, "hidden", tabDef.groups ~= nil)
    findButton.group.set("hidden", tabDef.find == nil)
    if tabDef.find ~= nil then
      set(findButton.label, "content", tabDef.find.label)
    end
    local keepUp = saved.keepUp()
    local appearance = saved.appearance()
    local y = top
    local used = 0
    local marked = 0
    for i, slot in ipairs(slots) do
      local def = tabDef.groups and tabDef.groups[i]
      draw.hideAll({ slot.label, slot.note, slot.box, slot.dashes }, def == nil)
      set(slot.sizes.layer, "hidden", def == nil or def.row == nil)
      slot.def = def
      if def ~= nil then
        local list = sprites(groups, def)
        local lines = math.max(1, (#list + cols - 1) // cols)
        local boxY = y + HEADER
        if def.row ~= nil then
          draw.pos(slot.sizes.layer, MARGIN, boxY)
          slot.sizes.show(appearance)
          boxY = boxY + SIZES_H
        end
        local boxH = lines * STEP - GAP + 2 * PAD
        set(slot.label, "content", def.label)
        draw.pos(slot.label, MARGIN, y)
        set(slot.note, "content", #list .. ". " .. def.note)
        draw.pos(slot.note, MARGIN + 140, y + 2)
        draw.pos(slot.box, MARGIN, boxY)
        draw.size(slot.box, width - 2 * MARGIN, boxH)
        slot.top = boxY
        slot.bottom = boxY + boxH
        slot.list = list
        slot.lines = lines
        local shown = 0
        for k, sprite in ipairs(list) do
          if used >= TILES then
            break
          end
          used = used + 1
          shown = k
          local t = tiles[used]
          t.sprite = sprite
          t.def = def
          t.x = MARGIN + PAD + ((k - 1) % cols) * STEP
          t.y = boxY + PAD + ((k - 1) // cols) * STEP
          draw.pos(t.edge, t.x, t.y)
          draw.pos(t.icon, t.x + 1, t.y + 1)
          draw.hideAll({ t.edge, t.icon }, false)
          draw.icon(t.icon, sprite)
          set(t.icon, "alpha", def.dim and DIM or 1)
          if def.value == "upkeep" and keepUp[tostring(sprite)] and marked < KEEP_MARKS then
            marked = marked + 1
            local m = marks[marked]
            draw.pos(m.bg, t.x + SIZE - MARK, t.y + SIZE - MARK)
            draw.pos(m.label, t.x + SIZE - MARK, t.y + SIZE - MARK)
            draw.hideAll({ m.bg, m.label }, false)
          end
        end
        -- Dim groups draw a dashed box around each icon, redrawn only when their icons moved.
        local dashKey = def.dim and (boxY .. ":" .. shown) or ""
        if slot.dashKey ~= dashKey then
          slot.dashKey = dashKey
          slot.dashes:Clear()
          for k = 1, def.dim and shown or 0 do
            local x = MARGIN + PAD + ((k - 1) % cols) * STEP
            local ty = boxY + PAD + ((k - 1) // cols) * STEP
            draw.dashedBoxAt(slot.dashes, x - 1, ty - 1, SIZE + 2, SIZE + 2, 1, draw.opaque(COLOURS.dimText))
          end
        end
        y = slot.bottom + 12
      end
    end
    for i = used + 1, TILES do
      tiles[i].sprite, tiles[i].def = nil, nil
      draw.hideAll({ tiles[i].edge, tiles[i].icon }, true)
    end
    for i = marked + 1, KEEP_MARKS do
      draw.hideAll({ marks[i].bg, marks[i].label }, true)
    end
  end

  -- Menu ------------------------------------------------------------------------------------------------

  local menu = draw.new(ui.Layer, page)
  local menuEdge = hitArea(rect(menu, COLOURS.border, 0, 0, MENU_W, MENU_ROW))
  local menuRows = {}
  local menuTile = nil
  for i = 1, 4 do
    local r = {
      bg = hitArea(rect(menu, COLOURS.popup, 1, 1 + (i - 1) * MENU_ROW, MENU_W - 2, MENU_ROW)),
      label = text(menu, FONTS.body, ui.AlignMode.TOPLEFT, 12, 1 + (i - 1) * MENU_ROW, MENU_W - 20, MENU_ROW),
    }
    on(r.bg, "ONCLICK", function()
      local action = r.action
      local t = menuTile
      closeMenu()
      if action ~= nil and t ~= nil and t.sprite ~= nil then
        action(t)
      end
    end)
    menuRows[i] = r
  end
  set(menu, "hidden", true)

  function closeMenu()
    set(menu, "hidden", true)
    menuTile = nil
  end

  -- The menu's rows for t: every other group on its tab, and Keep up for an upkeep buff.
  local function menuEntries(t)
    local entries = {}
    for _, slot in ipairs(slots) do
      local def = slot.def
      if def ~= nil then
        local current = def == t.def
        local label
        if def.kind == "buff" then
          label = def.label
        elseif def.value then
          label = "Track"
        else
          label = "Stop tracking"
        end
        local action = nil
        if not current then
          action = function(tile)
            place(tile, slot, { kind = "insert", index = #slot.list + 1 })
          end
        end
        if not current or t.def.kind == "buff" then
          entries[#entries + 1] = { label = label, current = current, action = action }
        end
      end
    end
    if t.def.value == "upkeep" then
      local keeping = saved.keepUp()[tostring(t.sprite)] == true
      entries[#entries + 1] = {
        label = keeping and "Keep up: on" or "Keep up: off",
        action = function(tile)
          saved.setKeepUp(tile.sprite, not keeping)
          changed()
        end,
      }
    end
    return entries
  end

  local function openMenu(t)
    menuTile = t
    local entries = menuEntries(t)
    for i, r in ipairs(menuRows) do
      local e = entries[i]
      r.action = e and e.action
      draw.hideAll({ r.bg, r.label }, e == nil)
      if e ~= nil then
        set(r.label, "content", e.label)
        set(r.label, "rgb", e.current and COLOURS.accent or COLOURS.text)
      end
    end
    draw.size(menuEdge, MENU_W, #entries * MENU_ROW + 2)
    menu:SetSize(MENU_W, #entries * MENU_ROW + 2)
    menu:SetPos(math.min(t.x, width - MENU_W - MARGIN), t.y + SIZE + 4)
    set(menu, "hidden", false)
  end

  -- Drag ------------------------------------------------------------------------------------------------

  -- The group slot under page position (px, py) with the src/editor drop target there, its index counted
  -- through the whole group, and the wrapped line holding it; or nil.
  local function targetAt(px, py)
    for _, slot in ipairs(slots) do
      if slot.def ~= nil and py >= slot.top - PAD and py <= slot.bottom + PAD then
        local y = py - slot.top - PAD
        local grid = { count = #slot.list, step = STEP, size = SIZE, perRow = cols }
        return slot, editor.gridDropTarget(grid, px - MARGIN - PAD, y), math.max(0, math.min(slot.lines - 1, y // STEP))
      end
    end
  end

  local dropSlot = nil
  local dropTarget = nil
  drag = dragdrop.create(page, SIZE // 2, {
    -- A press while the search is open only closes it, as a click anywhere outside a popup does.
    press = function(t)
      if finder.isOpen() then
        finder.close()
        return false
      end
      if t.sprite == nil then
        return false
      end
      closeMenu()
      deps.tooltip.hide()
      return true
    end,
    ghost = function(t)
      return { icon = t.sprite, initials = "" }
    end,
    start = function(t)
      set(t.icon, "alpha", 0.3)
    end,
    move = function(_, px, py)
      local slot, target, line = targetAt(px, py)
      dropSlot = slot
      dropTarget = target
      local swap = target ~= nil and target.kind == "swap"
      draw.hideAll(swapBox, not swap)
      set(insertLine, "hidden", target == nil or swap)
      if target == nil then
        return
      end
      local column = target.index - 1 - line * cols
      local x = MARGIN + PAD + column * STEP
      local y = slot.top + PAD + line * STEP
      if swap then
        draw.placeOutline(swapBox, x, y, SIZE, SIZE)
      else
        draw.pos(insertLine, x - GAP, y - 4)
      end
    end,
    drop = function(t)
      if dropTarget ~= nil and t.sprite ~= nil then
        place(t, dropSlot, dropTarget)
      end
    end,
    click = openMenu,
    finish = function(t)
      set(t.icon, "alpha", t.def.dim and DIM or 1)
      hideDropFeedback()
      dropSlot = nil
      dropTarget = nil
    end,
  })
  for _, t in ipairs(tiles) do
    drag.attach(t)
  end

  -- Search ----------------------------------------------------------------------------------------------

  -- Whether the current tab shows sprite: a buff in combat or upkeep, or a tracked debuff.
  local function trackedNow()
    local kind = tab
    return setmetatable({}, {
      __index = function(_, sprite)
        if kind == "buffs" then
          local category = saved.auras()[tostring(sprite)]
          return category == "combat" or category == "upkeep"
        end
        return auralists.tracked(kind, saved.tracked(kind), sprite)
      end,
    })
  end

  -- Tracks or untracks a search row on the current tab.
  local function choose(row, track)
    if tab == "buffs" then
      saved.setAuraCategory(row.sprite, track and "combat" or "hidden")
    else
      saved.setTracked(tab, row.sprite, track)
    end
    changed()
  end

  finder = aurasearch.create(page, MARGIN, SEARCH_Y, width - 2 * MARGIN, math.min(SEARCH_H, height - SEARCH_Y - 16), {
    describe = deps.describe,
    choose = choose,
  })

  function openSearch()
    closeMenu()
    local seen = {}
    for key in pairs(tab == "buffs" and saved.auras() or saved.tracked(tab)) do
      seen[#seen + 1] = tonumber(key)
    end
    table.sort(seen)
    local rows = search.withSeen(deps.catalog, tabDef.find.kind, seen, function(sprite)
      return deps.info(sprite).name
    end)
    finder.open({
      title = tabDef.label,
      empty = tabDef.find.empty,
      kind = tabDef.find.kind,
      rows = rows,
      tracked = trackedNow,
    })
  end

  -- Tooltip ---------------------------------------------------------------------------------------------

  deps.tooltip.hover(tiles, function(i)
    local t = tiles[i]
    if t.sprite == nil or drag.dragging() then
      deps.tooltip.hide()
      return
    end
    local x, y = deps.toScreen(t.x, t.y)
    deps.tooltip.show({
      title = deps.info(t.sprite).name or "Unknown",
      info = "Drag to sort or move it, or click for options",
    }, x, y, SIZE)
  end)

  return {
    display = display,
    redraw = redraw,
    follow = function()
      drag.follow()
      finder.follow()
    end,
    close = function()
      drag.cancel()
      closeMenu()
      finder.close()
      deps.tooltip.hide()
    end,
    popupOpen = function()
      return menuTile ~= nil or finder.isOpen()
    end,
  }
end

return buffspage
