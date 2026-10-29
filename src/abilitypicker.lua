-- The cooldown manager's ability picker: a popup under the "+" tile listing abilities in titled sections, one
-- combat style tab at a time, narrowed by a search box that covers every style. It stays open for several adds.
local controls = require("src/controls")
local draw = require("src/draw")

local abilitypicker = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local hitArea = draw.hitArea
local on = draw.on
local hideAll = draw.hideAll
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW

local WIDTH = 340
local ROW = 26
local SEARCH_H = 36
local TABS_H = 34
local HEAD = SEARCH_H + TABS_H
local MAX_ROWS = 14
-- Tabs left to right; style nil lists every style.
local TAB_LIST = {
  { label = "All", width = 34 },
  { label = "Necromancy", style = "necromancy", width = 100 },
  { label = "Magic", style = "magic", width = 58 },
  { label = "Ranged", style = "ranged", width = 66 },
  { label = "Melee", style = "melee", width = 58 },
}

-- A picker on page, pageW by pageH. deps: { entries(query, style) listing what to show, each { title } for a
-- section heading or { key, name, icon } for an ability, with style nil for every style; choose(key) when an
-- ability row is clicked; close() when its X is clicked }. Returns { open(x, y, style), close(), isOpen() }:
-- open shows it on style with its top left at x, y, moved left or up as far as it must be to fit on the page.
function abilitypicker.create(page, pageW, pageH, deps)
  local picker = draw.new(ui.Layer, page)
  local rows = {}
  local tabs = {}
  local isOpen = false
  local style = nil
  local query = ""
  local anchorX = 0
  local anchorY = 0
  local fill
  picker:SetSize(WIDTH, HEAD + MAX_ROWS * ROW + 2)
  local edge = hitArea(rect(picker, COLOURS.border, 0, 0, WIDTH, 0))
  local bg = rect(picker, COLOURS.popup, 1, 1, WIDTH - 2, 0)
  rect(picker, COLOURS.line, 1, HEAD, WIDTH - 2, 1)
  local search = controls.inputField(picker, 10, 6, WIDTH - 49, 24, 30, true)
  set(search, "emptyText", "Find an ability")
  -- The field also reports its contents on Enter, Esc and focus loss, which can come after the picker closed.
  on(search, "ONCONTENTCHANGED", function(_, _, contents)
    query = (contents or ""):lower()
    if not isOpen then
      return
    end
    if query ~= "" then
      style = nil
    end
    fill()
  end)
  local tabX = 10
  for _, tab in ipairs(TAB_LIST) do
    local hit = hitArea(rect(picker, COLOURS.popup, tabX, SEARCH_H, tab.width, TABS_H))
    local t = {
      style = tab.style,
      label = text(picker, FONTS.body, ui.AlignMode.CENTRE, tabX, SEARCH_H, tab.width, TABS_H - 2),
      underline = rect(picker, COLOURS.accent, tabX, HEAD - 2, tab.width, 2),
    }
    set(t.label, "content", tab.label)
    on(hit, "ONCLICK", function()
      style = t.style
      fill()
    end)
    tabs[#tabs + 1] = t
    tabX = tabX + tab.width
  end
  controls.closeButton(picker, WIDTH - 29, 8, function()
    deps.close()
  end)
  for i = 1, MAX_ROWS do
    local ry = HEAD + 1 + (i - 1) * ROW
    local r = {
      bg = hitArea(rect(picker, COLOURS.popup, 1, ry, WIDTH - 2, ROW)),
      hover = rect(picker, COLOURS.buttonHover, 1, ry, WIDTH - 2, ROW),
      label = text(picker, FONTS.body, ui.AlignMode.TOPLEFT, 10, ry, WIDTH - 50, ROW),
      iconEdge = rect(picker, COLOURS.border, WIDTH - 30, ry + 2, 22, 22),
      icon = draw.new(ui.Sprite, picker),
    }
    r.icon:SetSize(20, 20)
    r.icon:SetPos(WIDTH - 29, ry + 3)
    set(r.hover, "hidden", true)
    on(r.bg, "ONMOUSEOVER", function()
      set(r.hover, "hidden", r.key == nil)
    end)
    on(r.bg, "ONMOUSELEAVE", function()
      set(r.hover, "hidden", true)
    end)
    on(r.bg, "ONCLICK", function()
      if r.key == nil or not isOpen then
        return
      end
      deps.choose(r.key)
      fill()
    end)
    rows[i] = r
  end
  set(picker, "hidden", true)

  -- Lists deps.entries for the query and tab, with a note when nothing matches, and past the last row a note
  -- counting the abilities left out that points to the search box.
  function fill()
    for _, t in ipairs(tabs) do
      set(t.label, "rgb", t.style == style and COLOURS.text or COLOURS.mutedText)
      set(t.underline, "hidden", t.style ~= style)
    end
    local entries = deps.entries(query, style)
    if #entries == 0 then
      entries[1] = { title = query ~= "" and "No ability matches" or "Use an ability to add it here" }
    end
    if #entries > MAX_ROWS then
      local hidden = 0
      for i = MAX_ROWS, #entries do
        if entries[i].key ~= nil then
          hidden = hidden + 1
        end
      end
      entries[MAX_ROWS] = { title = hidden .. " more. Search to find them." }
    end
    for i, r in ipairs(rows) do
      local entry = entries[i]
      r.key = entry and entry.key
      hideAll({ r.bg, r.label, r.iconEdge, r.icon, r.hover }, entry == nil)
      set(r.hover, "hidden", true)
      if entry ~= nil then
        set(r.label, "content", entry.title or entry.name)
        set(r.label, "rgb", entry.title and COLOURS.mutedText or COLOURS.text)
        hideAll({ r.iconEdge, r.icon }, entry.icon == nil)
        if entry.icon ~= nil then
          set(r.icon, "sprite", entry.icon)
        end
      end
    end
    local shown = math.min(#entries, MAX_ROWS)
    local h = HEAD + shown * ROW + 2
    edge:SetSize(WIDTH, h)
    bg:SetSize(WIDTH - 2, h - 2)
    draw.pos(picker, math.min(anchorX, pageW - WIDTH - 8), math.min(anchorY, pageH - h))
  end

  local p = {}

  function p.open(x, y, openStyle)
    isOpen = true
    style = openStyle
    anchorX = x
    anchorY = y
    if query ~= "" then
      query = ""
      search.content = ""
    end
    fill()
    set(picker, "hidden", false)
  end

  function p.close()
    set(picker, "hidden", true)
    isOpen = false
  end

  function p.isOpen()
    return isOpen
  end

  return p
end

return abilitypicker
