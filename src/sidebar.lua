-- The group sidebar: a flat panel drawn over the game's group window, with the group's title, a row per
-- member and a tile at each button the game shows. Every part but the Hide button keeps a plain component's
-- defaults, so a click lands on the game's own button or row under it. Its header covers the window's own title
-- strip. Folded, only the header shows, over the window src/gameui holds transparent, and a hit area keeps
-- clicks off the unseen window. While the party grid stands in for the window's list, there is no header and
-- no hit area: the panel is the block of the game's buttons under the list, with a tab on its right edge that
-- folds it to a thin bar and back, so clicks reach the member rows' click areas under the grid's cells.
local sidebar = {}

local controls = require("src/controls")
local draw = require("src/draw")
local party = require("src/party")
local style = require("src/style")

local set = draw.set
local pos = draw.pos
local size = draw.size
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS

-- The least height of the header, for a window whose title strip reads shorter.
local MIN_HEADER = 16
-- The Hide button's size, and the space kept right of it for the window's close button.
local FOLD_W = 46
local FOLD_H = 14
-- The folded controls block's bar, and the tab that folds and unfolds the block.
local BAR_W = 8
local TAB_W = 16
local TAB_H = 36
-- The tab's arrow in columns, each two pixels taller than the last from its point.
local ARROW = 5
local CLOSE_SPACE = 26
local PAD = 8
local VALUE_W = 60
local LEADER = 12
local BAR_H = 8
local NO_ROWS = {}

-- Puts c at x, y sized w by h.
local function fit(c, x, y, w, h)
  pos(c, x, y)
  size(c, w, h)
end

-- root is the plugin layer that draws over game windows. deps: { saved = src/settings, blocked = function
-- saying whether the options window or edit mode is open, changed = function redrawing after the fold button }.
-- Returns { update(layout, reads, standIn), layout(), destroy() }. update runs each server tick, and on a frame
-- the window moved, with src/adapter's groupLayout and groupReads and whether the party grid stands in for the
-- folded window: it builds the panel once the window is open and the
-- sidebar is on, never while blocked so it cannot stack over the options window, follows the window's place, and
-- destroys the panel when the window closes or the sidebar is turned off. A tick where nothing changed writes
-- nothing. layout() is the layout the panel last drew, nil with no panel.
function sidebar.create(root, deps)
  local saved = deps.saved
  local s = {}
  -- The built panel's parts, nil while there is none.
  local p = nil
  local drawn = nil

  local function build()
    local layer = draw.new(ui.Layer, root)
    size(layer, tonumber(root.width) or 4096, tonumber(root.height) or 4096)
    local parts = { layer = layer, tiles = {}, rows = {} }
    parts.top = rect(layer, COLOURS.panel, 0, 0, 0, 0)
    parts.list = rect(layer, COLOURS.panel, 0, 0, 0, 0)
    parts.bottom = rect(layer, COLOURS.panel, 0, 0, 0, 0)
    parts.block = draw.hitArea(rect(layer, COLOURS.panel, 0, 0, 0, 0))
    set(parts.block, "alpha", 0)
    parts.title = draw.text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 0, 0, 0, 0)
    -- Marks the window's own close button, which sits under the header's right end and takes the click.
    parts.close = draw.text(layer, FONTS.body, ui.AlignMode.CENTRE, 0, 0, CLOSE_SPACE, 0)
    set(parts.close, "content", "x")
    local function toggle()
      saved.setSidebar("collapsed", not saved.sidebar().collapsed)
      deps.changed()
    end
    parts.fold = controls.button(layer, "Hide", 0, 0, FOLD_W, FOLD_H, "plain", toggle)
    parts.tab = controls.button(layer, "", 0, 0, TAB_W, TAB_H, "plain", toggle)
    parts.arrow = parts.tab.group.add(draw.new(ui.Canvas, layer), 0, 0)
    size(parts.arrow, TAB_W, TAB_H)
    return parts
  end

  -- Draws the tab's arrow, pointing left to fold the block and right to unfold it. A label cannot, as one
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

  local function showTile(t, model)
    local inset = model.plain and 0 or 2
    set(t.face, "hidden", model.plain == true)
    fit(t.face, model.x, model.y, model.w, model.h)
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
        fit(t.icon, model.x + inset, model.y + inset, model.w - 2 * inset, model.h - 2 * inset)
        draw.icon(t.icon, sprite)
      end
    end
    if t.label ~= nil then
      set(t.label, "hidden", model.text == nil)
      if model.text ~= nil then
        fit(t.label, model.x, model.y, model.w, model.h)
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

  -- Row i, built the first time the list shows that many members: name, leader icon, lifepoints and a bar.
  local function row(i)
    local r = p.rows[i]
    if r == nil then
      local layer = p.layer
      r = {
        name = draw.text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 0, 0, 0, 0),
        leader = draw.new(ui.Sprite, layer),
        value = draw.text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, 0, 0),
        track = rect(layer, COLOURS.healthTrack, 0, 0, 0, 0),
        fill = rect(layer, style.FRAME_COLOURS.player, 0, 0, 0, 0),
      }
      size(r.leader, LEADER, LEADER)
      r.all = { r.name, r.leader, r.value, r.track, r.fill }
      p.rows[i] = r
    end
    return r
  end

  local function showRow(r, box, model)
    local inner = box.w - 2 * PAD
    set(r.name, "hidden", false)
    fit(r.name, box.x + PAD, box.y + 3, inner - VALUE_W - LEADER - 8, 16)
    set(r.name, "content", model.name)
    set(r.leader, "hidden", model.leader == nil)
    pos(r.leader, box.x + box.w - PAD - VALUE_W - LEADER - 4, box.y + 5)
    if model.leader ~= nil then
      draw.icon(r.leader, model.leader)
    end
    set(r.value, "hidden", false)
    fit(r.value, box.x + box.w - PAD - VALUE_W, box.y + 3, VALUE_W, 16)
    set(r.value, "content", model.text)
    set(r.track, "hidden", false)
    fit(r.track, box.x + PAD, box.y + 23, inner, BAR_H)
    local filled = model.fill and math.floor(inner * model.fill + 0.5) or 0
    set(r.fill, "hidden", filled == 0)
    if filled > 0 then
      fit(r.fill, box.x + PAD, box.y + 23, filled, BAR_H)
    end
  end

  function s.destroy()
    if p ~= nil then
      p.layer:Destroy()
      p = nil
    end
    drawn = nil
  end

  function s.layout()
    return drawn
  end

  function s.update(layout, reads, standIn)
    local state = saved.sidebar()
    if not state.on or layout == nil or not layout.open or (p == nil and deps.blocked()) then
      s.destroy()
      return
    end
    p = p or build()
    drawn = layout
    local folded = state.collapsed
    local bottom = layout.y + layout.h
    local blockY = layout.listY + layout.listH
    local places = not folded and not standIn and layout.rows or nil
    set(p.list, "hidden", places == nil)
    fit(p.list, layout.x, layout.listY, layout.w, layout.listH)
    set(p.bottom, "hidden", folded)
    fit(p.bottom, layout.x, blockY, layout.w, bottom - blockY)
    p.fold.group.set("hidden", standIn == true)
    p.tab.group.set("hidden", not standIn)
    set(p.title, "hidden", standIn == true)
    set(p.close, "hidden", folded or standIn == true)
    set(p.block, "hidden", not folded or standIn == true)
    if standIn then
      -- The block under the list with the tab on its right edge, or folded, a bar at its left end with the tab.
      set(p.top, "hidden", not folded)
      fit(p.top, layout.x, blockY, BAR_W, bottom - blockY)
      p.tab.group.place(layout.x + (folded and BAR_W or layout.w), blockY + (bottom - blockY - TAB_H) // 2)
      pointArrow(folded)
    else
      local top = layout.y
      local header = math.max(layout.top - top, MIN_HEADER)
      set(p.top, "hidden", false)
      fit(p.top, layout.x, top, layout.w, folded and header or layout.listY - top)
      fit(p.block, layout.x, top + header, layout.w, bottom - top - header)
      fit(p.title, layout.x + PAD, top, layout.w - PAD - FOLD_W - CLOSE_SPACE - 4, header)
      set(p.title, "content", reads.title or "Group")
      fit(p.close, layout.x + layout.w - CLOSE_SPACE, top, CLOSE_SPACE, header)
      p.fold.group.place(layout.x + layout.w - FOLD_W - CLOSE_SPACE, top + (header - FOLD_H) // 2)
      set(p.fold.label, "content", folded and "Show" or "Hide")
    end

    local tiles = folded and NO_ROWS or layout.tiles
    for i, model in ipairs(tiles) do
      showTile(tile(i), model)
    end
    for i = #tiles + 1, #p.tiles do
      hideTile(p.tiles[i])
    end
    local models = places and party.rows(reads) or NO_ROWS
    local count = places and math.min(#places, #models) or 0
    for i = 1, count do
      showRow(row(i), places[i], models[i])
    end
    for i = count + 1, #p.rows do
      draw.hideAll(p.rows[i].all, true)
    end
  end

  return s
end

return sidebar
