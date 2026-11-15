-- The group sidebar: the game's group window buttons as a two wide column, a HUD element that sits on the
-- screen's left edge until edit mode moves it. It draws a panel and a tile over each button, and src/gameui
-- moves the game's own buttons under the tiles. Every part but the tab keeps a plain component's defaults, so a
-- click lands on the game's button. The tab on its right edge folds it to a thin bar and back.
local sidebar = {}

local controls = require("src/controls")
local draw = require("src/draw")
local hudparts = require("src/hudparts")

local set = draw.set
local pos = draw.pos
local size = draw.size
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS

-- The column's edge padding, an icon button's size and the gap between tiles.
local PAD = 6
local SLOT = 24
local GAP = 4
local INNER = 2 * SLOT + GAP
local COLUMN_W = INNER + 2 * PAD
local LABEL_H = 16
local TEXT_H = 22
-- The folded column's bar, the column's height before one has been drawn, and the tab that folds and unfolds.
local BAR_W = 8
local BAR_H = 88
local TAB_W = 16
local TAB_H = 36
-- The tab's arrow in columns, each two pixels taller than the last from its point.
local ARROW = 5
local NO_TILES = {}

-- Puts c at x, y sized w by h.
local function fit(c, x, y, w, h)
  pos(c, x, y)
  size(c, w, h)
end

-- Lays src/adapter's groupButtons out as a column whose corner is at left, top on the screen. Returns
-- { x, y, w, h, tiles, bands }.
-- tiles holds each button's { x, y, w, h, sprite, text, plain, static }: the labels first, then each strip's
-- buttons in the order the strips come, icons two to a row above that strip's text buttons. bands holds a
-- { strip, x, y, w, h } per click-stopping strip, around its buttons and never over another strip's.
function sidebar.column(buttons, left, top)
  local tiles, bands = {}, {}
  local y = top + PAD
  for _, b in ipairs(buttons) do
    if b.plain then
      tiles[#tiles + 1] = { x = left + PAD, y = y, w = INNER, h = LABEL_H, text = b.text, plain = true }
      y = y + LABEL_H + GAP
    end
  end
  -- Each strip's buttons, by the strip or false for none, and the strips in the order they first come.
  local groups, order = {}, {}
  for _, b in ipairs(buttons) do
    if not b.plain then
      local key = b.strip or false
      if groups[key] == nil then
        groups[key] = {}
        order[#order + 1] = key
      end
      table.insert(groups[key], b)
    end
  end
  for _, key in ipairs(order) do
    local bandTop, side = y, 0
    for _, b in ipairs(groups[key]) do
      if b.text == nil then
        local x = left + PAD + side * (SLOT + GAP)
        tiles[#tiles + 1] = { x = x, y = y, w = SLOT, h = SLOT, sprite = b.sprite, static = b.static }
        side = 1 - side
        if side == 0 then
          y = y + SLOT + GAP
        end
      end
    end
    if side == 1 then
      y = y + SLOT + GAP
    end
    for _, b in ipairs(groups[key]) do
      if b.text ~= nil then
        tiles[#tiles + 1] = { x = left + PAD, y = y, w = INNER, h = TEXT_H, text = b.text, static = b.static }
        y = y + TEXT_H + GAP
      end
    end
    if key then
      bands[#bands + 1] = { strip = key, x = left, y = bandTop, w = COLUMN_W, h = y - bandTop }
    end
  end
  return { x = left, y = top, w = COLUMN_W, h = y - GAP + PAD - top, tiles = tiles, bands = bands }
end

-- root is the plugin layer that draws over game windows. deps: { saved = src/settings, blocked = function
-- saying whether the options window or edit mode is open, changed = function redrawing after the tab }.
-- Returns a src/view element, { layer, bounds, inUse, setLook, update(shown, buttons), canDraw(), destroy() }.
-- The layer holds nothing but its panel, so it stays for src/view and edit mode to place. update runs each
-- server tick with whether the group window stands open behind the HUD and src/adapter's groupButtons, nil
-- while folded. It builds the panel once shown with the sidebar on, never while blocked so it cannot stack over
-- the options window, and destroys it once not. It returns the column it drew at its layer's place on the
-- screen, for src/gameui to put the game's buttons under, or nil while it drew none, and whether its bounds
-- changed. A tick where nothing changed writes nothing.
function sidebar.create(root, deps)
  local saved = deps.saved
  local layer = draw.new(ui.Layer, root)
  size(layer, COLUMN_W + TAB_W, BAR_H)
  local bounds = { x = 0, y = 0, w = COLUMN_W, h = BAR_H }
  local s = { layer = layer, bounds = bounds, inUse = saved.sidebar().on }
  -- The built panel's parts, nil while there is none.
  local p = nil

  local function build()
    local panel = draw.new(ui.Layer, layer)
    local parts = { layer = panel, tiles = {} }
    parts.face = rect(panel, COLOURS.panel, 0, 0, 0, 0)
    parts.tab = controls.button(panel, "", 0, 0, TAB_W, TAB_H, "plain", function()
      saved.setSidebar("collapsed", not saved.sidebar().collapsed)
      deps.changed()
    end)
    parts.arrow = parts.tab.group.add(draw.new(ui.Canvas, panel), 0, 0)
    size(parts.arrow, TAB_W, TAB_H)
    return parts
  end

  -- Draws the tab's arrow, pointing left to fold the column and right to unfold it. A label cannot, as one
  -- reading "<" draws nothing.
  local function pointArrow(folded)
    if p.arrowFolded == folded then
      return
    end
    p.arrowFolded = folded
    p.arrow:Clear()
    local rgba = draw.opaque(COLOURS.text)
    for i = 0, ARROW - 1 do
      local x = folded and (TAB_W + ARROW) // 2 - 1 - i or (TAB_W - ARROW) // 2 + i
      p.arrow:AddRectangle(x, TAB_H // 2 - i, 1, 2 * i + 1, rgba)
    end
  end

  -- Tile i, built the first time the game shows that many buttons: a flat face, with an icon or a label added
  -- when the tile first needs one.
  local function tile(i)
    local t = p.tiles[i]
    if t == nil then
      t = { face = rect(p.layer, COLOURS.button, 0, 0, 0, 0) }
      p.tiles[i] = t
    end
    return t
  end

  -- Draws model, a column tile, on t. left and top are the layer's place on the screen.
  local function showTile(t, model, left, top)
    local x, y = model.x - left, model.y - top
    local inset = model.plain and 0 or 2
    set(t.face, "hidden", model.plain == true)
    fit(t.face, x, y, model.w, model.h)
    local sprite = model.text == nil and model.sprite or nil
    if sprite ~= nil and t.icon == nil then
      t.icon = draw.new(ui.Sprite, p.layer)
    end
    if model.text ~= nil and t.label == nil then
      t.label = draw.text(p.layer, FONTS.small, ui.AlignMode.CENTRE, 0, 0, 0, 0)
    end
    if t.icon ~= nil then
      set(t.icon, "hidden", sprite == nil)
      if sprite ~= nil then
        fit(t.icon, x + inset, y + inset, model.w - 2 * inset, model.h - 2 * inset)
        draw.icon(t.icon, sprite)
      end
    end
    if t.label ~= nil then
      set(t.label, "hidden", model.text == nil)
      if model.text ~= nil then
        fit(t.label, x, y, model.w, model.h)
        set(t.label, "content", model.text)
      end
    end
  end

  local function hideTile(t)
    set(t.face, "hidden", true)
    if t.icon ~= nil then
      set(t.icon, "hidden", true)
    end
    if t.label ~= nil then
      set(t.label, "hidden", true)
    end
  end

  -- Destroys the panel, leaving the layer for src/view to place.
  function s.destroy()
    if p ~= nil then
      p.layer:Destroy()
      p = nil
    end
  end

  -- The panel takes no look.
  function s.setLook()
    return false
  end

  -- Whether update would draw: the panel is built, or nothing blocks building it. While it would not, the
  -- game's buttons have no tiles over them.
  function s.canDraw()
    return p ~= nil or not deps.blocked()
  end

  function s.update(shown, buttons)
    local state = saved.sidebar()
    s.inUse = state.on
    if not state.on or not shown or (p == nil and deps.blocked()) then
      s.destroy()
      return nil, false
    end
    p = p or build()
    local left, top = hudparts.screenPos(layer, 0, 0)
    local folded = state.collapsed or buttons == nil
    local column = not folded and sidebar.column(buttons, left, top) or nil
    local w, h = folded and BAR_W + TAB_W or column.w, column and column.h or bounds.h
    local moved = bounds.w ~= w or bounds.h ~= h
    bounds.w, bounds.h = w, h
    size(layer, COLUMN_W + TAB_W, h)
    size(p.layer, COLUMN_W + TAB_W, h)
    fit(p.face, 0, 0, folded and BAR_W or column.w, h)
    p.tab.group.place(folded and BAR_W or column.w, (h - TAB_H) // 2)
    pointArrow(folded)
    local tiles = column and column.tiles or NO_TILES
    for i, model in ipairs(tiles) do
      showTile(tile(i), model, left, top)
    end
    for i = #tiles + 1, #p.tiles do
      hideTile(p.tiles[i])
    end
    return column, moved
  end

  return s
end

return sidebar
