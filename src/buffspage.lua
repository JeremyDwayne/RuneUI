-- The options window's Buffs page: tabs for buffs, target debuffs, your debuffs and display options. Each
-- tab holds wrapping groups of icons in their sorted order. Dragging an icon swaps it with the icon it lands
-- on or inserts it between two, within its group or into another, as the cooldown editor does; clicking one
-- opens a menu of the group moves, plus Keep up for upkeep buffs. Hovering shows the icon's name.
local auralists = require("src/auralists")
local dragdrop = require("src/dragdrop")
local draw = require("src/draw")
local editor = require("src/editor")

local buffspage = {}

local set, rect, text, hitArea, on = draw.set, draw.rect, draw.windowText, draw.hitArea, draw.on
local FONTS, COLOURS = draw.FONTS, draw.WINDOW
local SIZE, GAP = 30, 3
local STEP = SIZE + GAP
-- Icons a tab can show, and Keep up marks the upkeep group can show.
local TILES, KEEP_MARKS = 120, 24
local MARK = 11
-- Untracked and hidden icons draw dim inside a dashed box.
local DIM = 0.38
local MARGIN, TAB_Y, TAB_H, TAB_W = 24, 14, 28, 130
local HEADER = 20
local PAD = 6
local MENU_W, MENU_ROW = 160, 28

-- Each group lists the sprites groups(...) files under kind and value: a buff row, or a debuff kind's
-- tracked or untracked list.
local TABS = {
  { id = "buffs", label = "Buffs", groups = {
    { label = "Combat buffs", note = "Above the cooldowns row", kind = "buff", value = "combat" },
    { label = "Upkeep buffs", note = "Below the player frame. K keeps a tile while missing", kind = "buff",
      value = "upkeep" },
    { label = "Hidden", note = "Never shown", kind = "buff", value = "hidden", dim = true },
  } },
  { id = "target", label = "Target debuffs", groups = {
    { label = "Tracked", note = "Shown above the target frame", kind = "target", value = true },
    { label = "Not tracked", note = "Seen but not shown", kind = "target", value = false, dim = true },
  } },
  { id = "player", label = "Your debuffs", groups = {
    { label = "Tracked", note = "Shown above the player frame", kind = "player", value = true },
    { label = "Not tracked", note = "Seen but not shown", kind = "player", value = false, dim = true },
  } },
  { id = "display", label = "Display" },
}
local MAX_GROUPS = 3

-- page: the options window's page layer, width by height. deps: { saved = src/settings, info(sprite) naming
-- an icon, tooltip = view.tooltip, toScreen(x, y) turning page into screen coordinates, refresh() redrawing
-- the HUD }. Returns { display, redraw, follow, close, destroy }: display is the Display tab's layer for
-- option rows; redraw draws the page from settings; follow runs each frame to move a drag; close ends a drag
-- and closes the menu.
function buffspage.create(page, width, height, deps)
  local saved = deps.saved
  local cols = (width - 2 * MARGIN - 2 * PAD + GAP) // STEP
  local tab = "buffs"
  local redraw, closeMenu, drag

  -- Tabs ------------------------------------------------------------------------------------------------

  local tabParts = {}
  for i, def in ipairs(TABS) do
    local x = MARGIN + (i - 1) * (TAB_W + 6)
    tabParts[def.id] = draw.option(page, def.label, x, TAB_Y, TAB_W, TAB_H, function()
      closeMenu()
      tab = def.id
      redraw()
    end)
  end

  local top = TAB_Y + TAB_H + 12
  local display = ui.Layer.new(page)
  display:SetSize(width, height - top)
  display:SetPos(0, top)

  -- Groups ----------------------------------------------------------------------------------------------

  local slots = {}
  for i = 1, MAX_GROUPS do
    local slot = {
      label = text(page, FONTS.body, ui.AlignMode.TOPLEFT, MARGIN, 0, 200, 18),
      note = text(page, FONTS.small, ui.AlignMode.TOPLEFT, MARGIN + 140, 0, width - 2 * MARGIN - 140, 18),
      box = rect(page, COLOURS.row, MARGIN, 0, width - 2 * MARGIN, 0),
      dashes = ui.Canvas.new(page),
    }
    set(slot.note, "rgb", COLOURS.mutedText)
    slot.dashes:SetSize(width, height)
    slot.dashes:SetPos(0, 0)
    slots[i] = slot
  end

  local tiles = {}
  for i = 1, TILES do
    local t = {
      edge = hitArea(rect(page, COLOURS.border, 0, 0, SIZE, SIZE)),
      icon = ui.Sprite.new(page),
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
    if def.kind == "buff" then return groups[def.value] end
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
    if moved == nil then return end
    if slot.def ~= t.def then
      if moved.other ~= nil then assign(t.def, moved.other) end
      assign(slot.def, t.sprite)
    end
    saved.setOrder(kind, moved.order)
    redraw()
    deps.refresh()
  end

  -- Draws the page, unless an icon is being dragged, so a refresh cannot move the grab area.
  function redraw()
    if drag ~= nil and drag.dragging() then return end
    local choices = { target = saved.tracked("target"), player = saved.tracked("player") }
    local groups = auralists.groups(saved.auras(), choices, saved.orders())
    orders = groups.order
    local current = nil
    for _, def in ipairs(TABS) do
      local active = def.id == tab
      if active then current = def end
      draw.showOption(tabParts[def.id], active)
    end
    set(display, "hidden", current.groups ~= nil)
    local keepUp = saved.keepUp()
    local y, used, marked = top, 0, 0
    for i, slot in ipairs(slots) do
      local def = current.groups and current.groups[i]
      draw.hideAll({ slot.label, slot.note, slot.box, slot.dashes }, def == nil)
      slot.def = def
      if def ~= nil then
        local list = sprites(groups, def)
        local lines = math.max(1, (#list + cols - 1) // cols)
        local boxY = y + HEADER
        local boxH = lines * STEP - GAP + 2 * PAD
        set(slot.label, "content", def.label)
        draw.pos(slot.label, MARGIN, y)
        set(slot.note, "content", #list .. ". " .. def.note)
        draw.pos(slot.note, MARGIN + 140, y + 2)
        draw.pos(slot.box, MARGIN, boxY)
        draw.size(slot.box, width - 2 * MARGIN, boxH)
        slot.top, slot.bottom, slot.list, slot.lines = boxY, boxY + boxH, list, lines
        local shown = 0
        for k, sprite in ipairs(list) do
          if used >= TILES then break end
          used, shown = used + 1, k
          local t = tiles[used]
          t.sprite, t.def = sprite, def
          t.x = MARGIN + PAD + ((k - 1) % cols) * STEP
          t.y = boxY + PAD + ((k - 1) // cols) * STEP
          draw.pos(t.edge, t.x, t.y)
          draw.pos(t.icon, t.x + 1, t.y + 1)
          draw.hideAll({ t.edge, t.icon }, false)
          draw.icon(t.icon, sprite)
          set(t.icon, "alpha", def.dim and DIM or 1)
          -- Asking for a name queues an unnamed icon for the background scan.
          deps.info(sprite)
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
    for i = marked + 1, KEEP_MARKS do draw.hideAll({ marks[i].bg, marks[i].label }, true) end
  end

  -- Menu ------------------------------------------------------------------------------------------------

  local menu = ui.Layer.new(page)
  local menuEdge = hitArea(rect(menu, COLOURS.border, 0, 0, MENU_W, MENU_ROW))
  local menuRows = {}
  local menuTile = nil
  for i = 1, 4 do
    local r = {
      bg = hitArea(rect(menu, COLOURS.popup, 1, 1 + (i - 1) * MENU_ROW, MENU_W - 2, MENU_ROW)),
      label = text(menu, FONTS.body, ui.AlignMode.TOPLEFT, 12, 1 + (i - 1) * MENU_ROW, MENU_W - 20, MENU_ROW),
    }
    on(r.bg, "ONCLICK", function()
      local action, t = r.action, menuTile
      closeMenu()
      if action ~= nil and t ~= nil and t.sprite ~= nil then action(t) end
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
        entries[#entries + 1] = {
          label = def.kind == "buff" and def.label or (def.value and "Track" or "Stop tracking"),
          current = current,
          action = not current and function(tile) place(tile, slot, { kind = "insert", index = #slot.list + 1 }) end
            or nil,
        }
      end
    end
    if t.def.value == "upkeep" then
      local keeping = saved.keepUp()[tostring(t.sprite)] == true
      entries[#entries + 1] = {
        label = keeping and "Keep up: on" or "Keep up: off",
        action = function(tile)
          saved.setKeepUp(tile.sprite, not keeping)
          redraw()
          deps.refresh()
        end,
      }
    end
    if t.def.kind ~= "buff" then
      local kept = {}
      for _, e in ipairs(entries) do
        if not e.current then kept[#kept + 1] = e end
      end
      entries = kept
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
        local line = math.max(0, math.min(slot.lines - 1, (py - slot.top - PAD) // STEP))
        local first = line * cols
        local count = math.max(0, math.min(cols, #slot.list - first))
        local target = editor.dropTarget({ count = count, step = STEP, size = SIZE, offset = 0 }, px - MARGIN - PAD)
        target.index = target.index + first
        return slot, target, line
      end
    end
  end

  local dropSlot, dropTarget = nil, nil
  drag = dragdrop.create(page, SIZE // 2, {
    press = function(t)
      if t.sprite == nil then return false end
      closeMenu()
      deps.tooltip.hide()
      return true
    end,
    ghost = function(t) return { icon = t.sprite, initials = "" } end,
    start = function(t) set(t.icon, "alpha", 0.3) end,
    move = function(_, px, py)
      local slot, target, line = targetAt(px, py)
      dropSlot, dropTarget = slot, target
      local swap = target ~= nil and target.kind == "swap"
      draw.hideAll(swapBox, not swap)
      set(insertLine, "hidden", target == nil or swap)
      if target == nil then return end
      local column = target.index - 1 - line * cols
      local x, y = MARGIN + PAD + column * STEP, slot.top + PAD + line * STEP
      if swap then
        draw.placeOutline(swapBox, x, y, SIZE, SIZE)
      else
        draw.pos(insertLine, x - GAP, y - 4)
      end
    end,
    drop = function(t)
      if dropTarget ~= nil and t.sprite ~= nil then place(t, dropSlot, dropTarget) end
    end,
    click = openMenu,
    finish = function(t)
      set(t.icon, "alpha", t.def.dim and DIM or 1)
      hideDropFeedback()
      dropSlot, dropTarget = nil, nil
    end,
  })
  for _, t in ipairs(tiles) do drag.attach(t) end

  -- Tooltip ---------------------------------------------------------------------------------------------

  deps.tooltip.hover(tiles, function(i)
    local t = tiles[i]
    if t.sprite == nil or drag.dragging() then
      deps.tooltip.hide()
      return
    end
    local found = deps.info(t.sprite)
    local x, y = deps.toScreen(t.x, t.y)
    deps.tooltip.show({
      title = found and found.name or "Unknown",
      left = found == nil and "Looking up name" or nil,
      line = "Drag to sort or move it, or click for options",
    }, x, y, SIZE)
  end)

  return {
    display = display,
    redraw = redraw,
    follow = drag.follow,
    close = function()
      drag.cancel()
      closeMenu()
      deps.tooltip.hide()
    end,
    destroy = deps.tooltip.destroy,
  }
end

return buffspage
