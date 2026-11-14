-- The group sidebar: a flat panel drawn over the game's group window, with the group's title, a row per
-- member and a tile at each button the game shows. Every part but the Hide button keeps a plain component's
-- defaults, so a click lands on the game's own button or row under it. Folded, only its header shows, over
-- the window src/gameui holds transparent, and a hit area keeps clicks off the unseen window.
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

local HEADER_H = 22
-- The Hide button's width, and the space kept right of it for the window's close button.
local FOLD_W = 46
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
-- Returns { update(layout, reads), destroy() }. update runs each server tick with src/adapter's groupLayout and
-- groupReads: it builds the panel once the window is open and the sidebar is on, never while blocked so it cannot
-- stack over the options window, follows the window's place, and destroys the panel when the window closes or
-- the sidebar is turned off. A tick where nothing changed writes nothing.
function sidebar.create(root, deps)
  local saved = deps.saved
  local s = {}
  -- The built panel's parts, nil while there is none.
  local p = nil

  local function build()
    local layer = draw.new(ui.Layer, root)
    size(layer, tonumber(root.width) or 4096, tonumber(root.height) or 4096)
    local parts = { layer = layer, tiles = {}, rows = {} }
    parts.top = rect(layer, COLOURS.panel, 0, 0, 0, 0)
    parts.list = rect(layer, COLOURS.panel, 0, 0, 0, 0)
    parts.bottom = rect(layer, COLOURS.panel, 0, 0, 0, 0)
    parts.block = draw.hitArea(rect(layer, COLOURS.panel, 0, 0, 0, 0))
    set(parts.block, "alpha", 0)
    parts.title = draw.text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 0, 0, 0, HEADER_H)
    parts.fold = controls.button(layer, "Hide", 0, 0, FOLD_W, HEADER_H - 4, "plain", function()
      saved.setSidebar("collapsed", not saved.sidebar().collapsed)
      deps.changed()
    end)
    return parts
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
  end

  function s.update(layout, reads)
    local state = saved.sidebar()
    if not state.on or layout == nil or not layout.open or (p == nil and deps.blocked()) then
      s.destroy()
      return
    end
    p = p or build()
    local folded = state.collapsed
    -- The header sits over the window's top edge, above its content and never over its buttons.
    local top = math.min(layout.y, layout.top - HEADER_H)
    local bottom = layout.y + layout.h
    local places = not folded and layout.rows or nil
    fit(p.top, layout.x, top, layout.w, folded and HEADER_H or layout.listY - top)
    set(p.list, "hidden", places == nil)
    fit(p.list, layout.x, layout.listY, layout.w, layout.listH)
    set(p.bottom, "hidden", folded)
    fit(p.bottom, layout.x, layout.listY + layout.listH, layout.w, bottom - layout.listY - layout.listH)
    set(p.block, "hidden", not folded)
    fit(p.block, layout.x, top + HEADER_H, layout.w, bottom - top - HEADER_H)
    fit(p.title, layout.x + PAD, top, layout.w - PAD - FOLD_W - CLOSE_SPACE - 4, HEADER_H)
    set(p.title, "content", reads.title or "Group")
    p.fold.group.place(layout.x + layout.w - FOLD_W - CLOSE_SPACE, top + 2)
    set(p.fold.label, "content", folded and "Show" or "Hide")

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
