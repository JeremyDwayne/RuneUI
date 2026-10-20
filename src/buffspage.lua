-- The options window's Buffs page: tabs for buffs, target debuffs, your debuffs and display options. Each
-- tab holds wrapping groups of icons. Dragging an icon to another group moves it there; clicking one opens a
-- menu of the same moves, plus Keep up for upkeep buffs. Hovering shows the icon's name.
local auralists = require("src/auralists")
local draw = require("src/draw")

local buffspage = {}

local set, rect, text, hitArea, on = draw.set, draw.rect, draw.text, draw.hitArea, draw.on
local FONTS, COLOURS = draw.FONTS, draw.COLOURS
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
-- Pixels the cursor must travel after a press before it counts as a drag.
local DRAG_START = 3
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
  local drag = nil
  -- The cursor's offset from page coordinates, measured on each press.
  local origin = { x = 0, y = 0 }
  local redraw, closeMenu

  -- Tabs ------------------------------------------------------------------------------------------------

  local tabParts = {}
  for i, def in ipairs(TABS) do
    local x = MARGIN + (i - 1) * (TAB_W + 2)
    local parts = {
      bg = hitArea(rect(page, COLOURS.button, x, TAB_Y, TAB_W, TAB_H)),
      label = text(page, FONTS.body, ui.AlignMode.CENTRE, x, TAB_Y, TAB_W, TAB_H),
    }
    set(parts.label, "content", def.label)
    on(parts.bg, "ONCLICK", function()
      closeMenu()
      tab = def.id
      redraw()
    end)
    tabParts[def.id] = parts
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
      box = rect(page, COLOURS.sidebar, MARGIN, 0, width - 2 * MARGIN, 0),
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

  local targetBox = draw.outline(page, COLOURS.accent, 2)
  local ghost = ui.Sprite.new(page)
  ghost:SetSize(SIZE // 2, SIZE // 2)
  set(ghost, "alpha", 0.7)

  local function sprites(groups, def)
    if def.kind == "buff" then return groups[def.value] end
    return def.value and groups[def.kind].tracked or groups[def.kind].untracked
  end

  -- Moves sprite into the group def describes.
  local function apply(def, sprite)
    if def.kind == "buff" then
      saved.setAuraCategory(sprite, def.value)
    else
      saved.setTracked(def.kind, sprite, def.value)
    end
    redraw()
    deps.refresh()
  end

  function redraw()
    local choices = { target = saved.tracked("target"), player = saved.tracked("player") }
    local groups = auralists.groups(saved.auras(), choices)
    local current = nil
    for _, def in ipairs(TABS) do
      local active = def.id == tab
      if active then current = def end
      set(tabParts[def.id].bg, "rgb", active and COLOURS.accent or COLOURS.button)
      set(tabParts[def.id].label, "rgb", active and COLOURS.accentText or COLOURS.text)
      set(tabParts[def.id].label, "isShadowed", not active)
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
        slot.top, slot.bottom = boxY, boxY + boxH
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
          set(t.icon, "sprite", sprite)
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
          action = not current and function(tile) apply(def, tile.sprite) end or nil,
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

  local function cancelDrag()
    if drag == nil then return end
    local t = drag.tile
    draw.pos(t.edge, t.x, t.y)
    set(t.icon, "alpha", t.def.dim and DIM or 1)
    draw.hideAll(targetBox, true)
    set(ghost, "hidden", true)
    drag = nil
  end
  draw.hideAll(targetBox, true)
  set(ghost, "hidden", true)

  local function drop()
    local d = drag
    cancelDrag()
    if not d.moved then
      openMenu(d.tile)
    elseif d.target ~= nil and d.tile.sprite ~= nil then
      apply(d.target.def, d.tile.sprite)
    end
  end

  for _, t in ipairs(tiles) do
    on(t.edge, "ONCLICK", function(_, x, y)
      if t.sprite == nil then return end
      closeMenu()
      deps.tooltip.hide()
      draw.pressAt(t.edge, x)
      local mx, my = draw.cursor()
      if mx == nil then return end
      origin.x, origin.y = mx - (t.x + x), my - (t.y + y)
      drag = { tile = t, startX = mx, startY = my, pressX = x, pressY = y, moved = false }
    end)
    on(t.edge, "ONRELEASE", function() if drag ~= nil and drag.tile == t then drop() end end)
  end

  -- The group slot under page y other than the dragged icon's own, or nil.
  local function slotAt(py)
    for _, slot in ipairs(slots) do
      if slot.def ~= nil and slot.def ~= drag.tile.def and py >= slot.top - PAD and py <= slot.bottom + PAD then
        return slot
      end
    end
  end

  local lastX, lastY = nil, nil
  local function follow()
    if drag == nil then return end
    local mx, my = draw.cursor()
    if mx == nil or (mx == lastX and my == lastY) then return end
    lastX, lastY = mx, my
    local t = drag.tile
    if not drag.moved and math.abs(mx - drag.startX) + math.abs(my - drag.startY) > DRAG_START then
      drag.moved = true
      set(t.icon, "alpha", 0.3)
      set(ghost, "sprite", t.sprite)
      set(ghost, "hidden", false)
    end
    if not drag.moved then return end
    local px, py = mx - origin.x, my - origin.y
    -- The client releases a press once the cursor leaves the pressed component, so the hit area follows.
    draw.pos(t.edge, px - drag.pressX, py - drag.pressY)
    draw.pos(ghost, px + 8, py + 8)
    local slot = slotAt(py)
    drag.target = slot
    draw.hideAll(targetBox, slot == nil)
    if slot ~= nil then draw.placeOutline(targetBox, MARGIN, slot.top, width - 2 * MARGIN, slot.bottom - slot.top) end
  end

  -- Tooltip ---------------------------------------------------------------------------------------------

  deps.tooltip.hover(tiles, function(i)
    local t = tiles[i]
    if t.sprite == nil or drag ~= nil then
      deps.tooltip.hide()
      return
    end
    local found = deps.info(t.sprite)
    local x, y = deps.toScreen(t.x, t.y)
    deps.tooltip.show({
      title = found and found.name or "Unknown",
      line = "Drag to another group, or click for options",
    }, x, y, SIZE)
  end)

  return {
    display = display,
    redraw = redraw,
    follow = follow,
    close = function()
      cancelDrag()
      closeMenu()
      deps.tooltip.hide()
    end,
    destroy = deps.tooltip.destroy,
  }
end

return buffspage
