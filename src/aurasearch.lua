-- The Buffs page's search popup: a header with the tab's title, a search field and a close button over a
-- column of sources and the chosen source's effects, each effect with a Track or Tracked button. Both columns
-- scroll by the wheel and a src/scrollbar, reusing a fixed set of rows; a click lands only where its row shows.
-- It draws on open and on a query, scroll, source or choice, never on a page redraw.
local controls = require("src/controls")
local draw = require("src/draw")
local scrollbar = require("src/scrollbar")
local search = require("src/search")

local aurasearch = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local hitArea = draw.hitArea
local on = draw.on
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW

local HEAD = 40
local CLOSE = controls.CLOSE_SIZE
local SOURCE_W = 196
local SOURCE_ROW = 28
local LIST_HEAD = 30
local EFFECT_ROW = 45
local ICON = 28
local BUTTON_W = 92
local BUTTON_H = 24
local BAR_SPACE = scrollbar.WIDTH + 4
-- Characters of an effect's second line that surely fit beside its button.
local INFO_CHARS = 42

-- line cut at a word to fit INFO_CHARS, ending "..." when cut.
local function cut(line)
  if #line <= INFO_CHARS then
    return line
  end
  return line:sub(1, INFO_CHARS - 3):gsub("[%s,]+%S*$", "") .. "..."
end

-- The first paragraph of a description, without tags or surrounding quotes, cut to fit.
local function firstLine(info)
  local line = (info:match("^(.-)<br>") or info):gsub("<[^>]*>", "")
  return cut(line:match('^[%s"]*(.-)[%s";]*$'))
end

-- A w by h popup at x, y on parent, hidden until opened. deps: { describe(struct) returning a description or
-- nil, choose(row, on) tracking or untracking a src/search row }. Returns { open(view), close, isOpen, follow }:
-- open shows view, { title, empty, kind, rows, tracked() }, where empty is the field's placeholder, rows the
-- src/search rows, kind the src/search kind listed and tracked() the tab's current { [sprite] = true } set; follow
-- runs every frame to move a held scrollbar thumb.
function aurasearch.create(parent, x, y, w, h, deps)
  local layer = ui.Layer.new(parent)
  draw.pos(layer, x, y)
  draw.size(layer, w, h)
  hitArea(rect(layer, COLOURS.edge, 0, 0, w, h))
  rect(layer, COLOURS.border, 1, 1, w - 2, h - 2)
  rect(layer, COLOURS.popup, 2, 2, w - 4, h - 4)

  local view = nil
  local query = ""
  local source = "All"
  -- First lines by struct id, false for a struct with no description.
  local infos = {}
  local close

  local title = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 14, 2, 160, HEAD - 2)
  local field = controls.inputField(layer, 182, 9, w - 182 - CLOSE - 20, 24, 30, true)
  controls.closeButton(layer, w - CLOSE - 10, 11, function()
    close()
  end)
  rect(layer, COLOURS.line, 2, HEAD, w - 4, 1)

  local top = HEAD + 1
  local bodyH = h - top - 2
  local listX = 2 + SOURCE_W + 1
  local listW = w - listX - 2
  local listY = top + LIST_HEAD + 1
  local listH = bodyH - LIST_HEAD - 1
  rect(layer, COLOURS.line, 2 + SOURCE_W, top, 1, bodyH)
  local heading = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, listX + 12, top, listW - 140, LIST_HEAD)
  set(heading, "rgb", COLOURS.accent)
  local count = text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, listX + listW - 140 - BAR_SPACE, top, 128, LIST_HEAD)
  set(count, "rgb", COLOURS.mutedText)
  rect(layer, COLOURS.line, listX, top + LIST_HEAD, listW, 1)

  -- A clipping viewport at vx, vy, vw by vh with a background that takes the wheel, rows of rowH reused as it
  -- scrolls, and a scrollbar on its right. build(row) adds a row's parts on row.layer and fill(row, item) shows
  -- an item on it. Returns { rows, items, scroll, show(items), shows(row, y) }: show lists items from the top,
  -- and shows says whether a click at y inside row lands where the viewport shows it.
  local function column(vx, vy, vw, vh, rowH, bg, build, fill)
    local col = { rows = {}, items = {}, scroll = 0 }
    local viewport = ui.Layer.new(layer)
    draw.pos(viewport, vx, vy)
    draw.size(viewport, vw, vh)
    local back = hitArea(rect(viewport, bg, 0, 0, vw, vh))
    local bar

    local function scrollTo(to)
      col.scroll = bar.set(to, #col.items * rowH)
      local first = col.scroll // rowH
      for i, row in ipairs(col.rows) do
        local item = col.items[first + i]
        row.y = (i - 1) * rowH - col.scroll % rowH
        draw.pos(row.layer, 0, row.y)
        set(row.layer, "hidden", item == nil)
        row.item = item
        if item ~= nil then
          fill(row, item)
        end
      end
    end

    local barX = vw - scrollbar.WIDTH - 2
    bar = scrollbar.create(viewport, barX, 0, vh, scrollTo)
    bar.wheel(back)
    for i = 1, vh // rowH + 2 do
      local row = { layer = ui.Layer.new(viewport) }
      draw.size(row.layer, vw - BAR_SPACE, rowH)
      build(row)
      bar.wheel(row.bg)
      col.rows[i] = row
    end
    col.bar = bar
    col.barX = vx + barX
    col.barY = vy

    function col.show(items)
      col.items = items
      scrollTo(0)
    end

    function col.refill()
      scrollTo(col.scroll)
    end

    function col.shows(row, cy)
      local at = row.y + cy
      return at >= 0 and at < vh
    end

    return col
  end

  local fillEffects

  -- Source column ---------------------------------------------------------------------------------------

  local sourceCol
  sourceCol = column(2, top, SOURCE_W, bodyH, SOURCE_ROW, COLOURS.panel, function(row)
    row.bg = hitArea(rect(row.layer, COLOURS.panel, 0, 0, SOURCE_W - BAR_SPACE, SOURCE_ROW))
    row.name = text(row.layer, FONTS.body, ui.AlignMode.TOPLEFT, 12, 0, SOURCE_W - BAR_SPACE - 52, SOURCE_ROW)
    row.count = text(row.layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, 0, 0, SOURCE_W - BAR_SPACE - 8, SOURCE_ROW)
    on(row.bg, "ONCLICK", function(_, _, cy)
      if row.item == nil or not sourceCol.shows(row, cy) then
        return
      end
      source = row.item.name
      sourceCol.refill()
      fillEffects()
    end)
  end, function(row, item)
    local chosen = item.name == source
    set(row.name, "content", item.name)
    set(row.count, "content", tostring(item.count))
    set(row.bg, "rgb", chosen and COLOURS.accent or COLOURS.panel)
    for _, label in ipairs({ row.name, row.count }) do
      set(label, "rgb", chosen and COLOURS.accentText or COLOURS.text)
      set(label, "isShadowed", not chosen)
    end
  end)

  -- Effect list -----------------------------------------------------------------------------------------

  local function infoOf(item)
    if item.cause ~= nil then
      return cut("From " .. item.cause)
    end
    if item.struct == nil then
      return ""
    end
    if infos[item.struct] == nil then
      local info = deps.describe(item.struct) or item.info
      infos[item.struct] = info and firstLine(info) or false
    end
    return infos[item.struct] or ""
  end

  local effectCol
  local function chooseFrom(row, track, cy)
    if row.item == nil or not effectCol.shows(row, (EFFECT_ROW - BUTTON_H) // 2 + cy) then
      return
    end
    deps.choose(row.item, track)
    fillEffects(true)
  end

  local rowW = listW - BAR_SPACE
  local buttonX = rowW - BUTTON_W - 12
  local buttonY = (EFFECT_ROW - BUTTON_H) // 2
  effectCol = column(listX, listY, listW, listH, EFFECT_ROW, COLOURS.popup, function(row)
    row.bg = hitArea(rect(row.layer, COLOURS.popup, 0, 0, rowW, EFFECT_ROW))
    rect(row.layer, COLOURS.rowAlt, 0, EFFECT_ROW - 1, rowW, 1)
    rect(row.layer, COLOURS.border, 12, (EFFECT_ROW - ICON) // 2, ICON, ICON)
    row.icon = ui.Sprite.new(row.layer)
    draw.pos(row.icon, 13, (EFFECT_ROW - ICON) // 2 + 1)
    draw.size(row.icon, ICON - 2, ICON - 2)
    row.name = text(row.layer, FONTS.body, ui.AlignMode.TOPLEFT, 50, 5, buttonX - 60, 18)
    row.info = text(row.layer, FONTS.small, ui.AlignMode.TOPLEFT, 50, 23, buttonX - 60, 16)
    set(row.info, "rgb", COLOURS.mutedText)
    row.track = controls.button(row.layer, "Track", buttonX, buttonY, BUTTON_W, BUTTON_H, "gold", function(_, cy)
      chooseFrom(row, true, cy)
    end)
    row.tracked = controls.button(row.layer, "Tracked", buttonX, buttonY, BUTTON_W, BUTTON_H, "dark", function(_, cy)
      chooseFrom(row, false, cy)
    end)
  end, function(row, item)
    draw.icon(row.icon, item.sprite)
    set(row.name, "content", item.name)
    set(row.info, "content", infoOf(item))
    row.track.group.set("hidden", item.tracked)
    row.tracked.group.set("hidden", not item.tracked)
  end)
  local empty = text(layer, FONTS.body, ui.AlignMode.CENTRE, listX, listY, listW, 60)
  set(empty, "rgb", COLOURS.mutedText)
  set(empty, "content", "No effect matches")

  -- Lists the chosen source's effects, keeping the scroll when keep is true, as after a choice.
  function fillEffects(keep)
    local effects = search.rows(view.rows, view.kind, source, query, view.tracked())
    local tracked = 0
    for _, item in ipairs(effects) do
      if item.tracked then
        tracked = tracked + 1
      end
    end
    set(heading, "content", source)
    set(count, "content", tracked .. " of " .. #effects .. " tracked")
    set(empty, "hidden", #effects > 0)
    if keep then
      effectCol.items = effects
      effectCol.refill()
    else
      effectCol.show(effects)
    end
  end

  -- Lists the sources matching the query, choosing All while one is typed.
  local function fillSources()
    if query ~= "" then
      source = "All"
    end
    sourceCol.show(search.sources(view.rows, view.kind, query))
    fillEffects()
  end

  -- The field also reports its contents on Enter, Esc and focus loss, which can come after the popup closed.
  on(field, "ONCONTENTCHANGED", function(_, _, contents)
    if view == nil then
      return
    end
    local typed = (contents or ""):lower()
    if typed == query then
      return
    end
    query = typed
    fillSources()
  end)

  local columns = { sourceCol, effectCol }
  for _, col in ipairs(columns) do
    col.bar.grip(layer, col.barX, col.barY)
  end
  set(layer, "hidden", true)

  function close()
    if view == nil then
      return
    end
    view = nil
    for _, col in ipairs(columns) do
      col.bar.cancel()
    end
    set(layer, "hidden", true)
  end

  return {
    open = function(v)
      view = v
      set(title, "content", v.title)
      set(field, "emptyText", v.empty)
      if query ~= "" then
        query = ""
        field.content = ""
      end
      source = "All"
      fillSources()
      set(layer, "hidden", false)
    end,
    close = close,
    isOpen = function()
      return view ~= nil
    end,
    follow = function()
      for _, col in ipairs(columns) do
        col.bar.follow()
      end
    end,
  }
end

return aurasearch
