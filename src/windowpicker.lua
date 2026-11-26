-- The Windows page's Add window popup: a header with its title, a search field and a close button over a list of
-- the game windows, open ones under Open now and the rest under Closed, each with a check box ticked while the
-- window has its own opacity. The list scrolls by the wheel and a src/scrollbar, reusing a fixed set of rows; a
-- click lands only where its row shows. It draws on open and on a query, scroll or tick, never on a page redraw.
local controls = require("src/controls")
local draw = require("src/draw")
local scrollbar = require("src/scrollbar")

local windowpicker = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local hitArea = draw.hitArea
local on = draw.on
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW

local HEAD = 40
local CLOSE = controls.CLOSE_SIZE
local ROW = 34
local CHECK = 22
local BAR_SPACE = scrollbar.WIDTH + 4

-- A w by h popup at x, y on parent, hidden until opened. deps: { windows() returning src/windowskin's windows(),
-- picked(name) saying whether the window has its own opacity, toggle(name, on) giving it one or taking it away }.
-- Returns { open, close, isOpen, follow, cancel }: follow runs every frame to move a held scrollbar thumb, and
-- cancel ends that drag.
function windowpicker.create(parent, x, y, w, h, deps)
  local layer = draw.new(ui.Layer, parent)
  draw.pos(layer, x, y)
  draw.size(layer, w, h)
  hitArea(rect(layer, COLOURS.edge, 0, 0, w, h))
  rect(layer, COLOURS.border, 1, 1, w - 2, h - 2)
  rect(layer, COLOURS.popup, 2, 2, w - 4, h - 4)

  local shown = false
  local query = ""
  local items = {}
  local scroll = 0
  local close

  local title = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, 14, 2, 110, HEAD - 2)
  set(title, "content", "Add window")
  local field = controls.inputField(layer, 126, 9, w - 126 - CLOSE - 20, 24, 30, true)
  set(field, "emptyText", "Search windows")
  controls.closeButton(layer, w - CLOSE - 10, 11, function()
    close()
  end)
  rect(layer, COLOURS.line, 2, HEAD, w - 4, 1)

  local listY = HEAD + 1
  local listW = w - 4
  local listH = h - listY - 2
  local rowW = listW - BAR_SPACE
  local viewport = draw.new(ui.Layer, layer)
  draw.pos(viewport, 2, listY)
  draw.size(viewport, listW, listH)
  local back = hitArea(rect(viewport, COLOURS.popup, 0, 0, listW, listH))
  local empty = text(layer, FONTS.body, ui.AlignMode.CENTRE, 2, listY, listW, 60)
  set(empty, "rgb", COLOURS.mutedText)
  set(empty, "content", "No window matches")
  local rows = {}
  local bar

  -- Shows the items from scroll down on the reused rows.
  local function scrollTo(to)
    scroll = bar.set(to, #items * ROW)
    local first = scroll // ROW
    for i, row in ipairs(rows) do
      local item = items[first + i]
      row.y = (i - 1) * ROW - scroll % ROW
      row.item = item
      draw.pos(row.layer, 0, row.y)
      set(row.layer, "hidden", item == nil)
      if item ~= nil then
        local window = item.frame ~= nil
        set(row.label, "content", item.label)
        set(row.label, "rgb", window and COLOURS.text or COLOURS.accent)
        draw.pos(row.label, window and 44 or 12, 0)
        set(row.check.check, "hidden", not window)
        row.check.show(window and deps.picked(item.frame.name))
      end
    end
  end

  -- Whether a click at cy inside row lands where the list shows it.
  local function allowed(row, cy)
    local at = row.y + cy
    return at >= 0 and at < listH
  end

  -- Gives row's window its own opacity or takes it away, then shows every row's tick again.
  local function toggle(row, cy, ticked)
    if row.item ~= nil and row.item.frame ~= nil and allowed(row, cy) then
      deps.toggle(row.item.frame.name, ticked)
    end
    scrollTo(scroll)
  end

  bar = scrollbar.create(viewport, listW - scrollbar.WIDTH - 2, 0, listH, scrollTo)
  bar.wheel(back)
  for i = 1, listH // ROW + 2 do
    local row = { layer = draw.new(ui.Layer, viewport), y = 0 }
    draw.size(row.layer, rowW, ROW)
    row.bg = hitArea(rect(row.layer, COLOURS.popup, 0, 0, rowW, ROW))
    rect(row.layer, COLOURS.rowAlt, 0, ROW - 1, rowW, 1)
    row.label = text(row.layer, FONTS.body, ui.AlignMode.TOPLEFT, 44, 0, rowW - 56, ROW)
    row.check = controls.check(row.layer, 12, (ROW - CHECK) // 2, CHECK, function(ticked)
      toggle(row, ROW // 2, ticked)
    end)
    on(row.bg, "ONCLICK", function(_, _, cy)
      if row.item ~= nil and row.item.frame ~= nil then
        toggle(row, cy, not deps.picked(row.item.frame.name))
      end
    end)
    bar.wheel(row.bg)
    bar.wheel(row.check.check)
    rows[i] = row
  end
  bar.grip(layer, 2 + listW - scrollbar.WIDTH - 2, listY)

  -- Lists the windows whose label holds the query, under a heading for each group that has any.
  local function fill()
    local split = deps.windows()
    items = {}
    for _, group in ipairs({ { "Open now", split.open }, { "Closed", split.closed } }) do
      local heading = { label = group[1] }
      for _, frame in ipairs(group[2]) do
        if query == "" or frame.label:lower():find(query, 1, true) then
          if heading ~= nil then
            items[#items + 1] = heading
            heading = nil
          end
          items[#items + 1] = { label = frame.label, frame = frame }
        end
      end
    end
    set(empty, "hidden", #items > 0)
    scrollTo(0)
  end

  -- The field also reports its contents on Enter, Esc and focus loss, which can come after the popup closed.
  on(field, "ONCONTENTCHANGED", function(_, _, contents)
    local typed = (contents or ""):lower()
    if not shown or typed == query then
      return
    end
    query = typed
    fill()
  end)
  set(layer, "hidden", true)

  function close()
    if not shown then
      return
    end
    shown = false
    bar.cancel()
    set(layer, "hidden", true)
  end

  return {
    open = function()
      shown = true
      if query ~= "" then
        query = ""
        field.content = ""
      end
      fill()
      set(layer, "hidden", false)
    end,
    close = close,
    isOpen = function()
      return shown
    end,
    follow = bar.follow,
    cancel = bar.cancel,
  }
end

return windowpicker
