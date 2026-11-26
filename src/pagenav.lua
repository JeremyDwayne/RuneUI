-- The options window's side list of pages: a black column holding each group's name in gold over a button per
-- page. A button is one hit area under its label. The chosen page's button fills gold inside a white ring with
-- dark text, and the rest stay plain parchment on black. Built once with the window.
local draw = require("src/draw")

local pagenav = {}

local set = draw.set
local rect = draw.rect
local COLOURS = draw.WINDOW
local FONTS = draw.FONTS

local GROUP_H = 34
local BUTTON_H = 30
local GAP = 2
local PAD = 6
local RING = 2

-- Builds the list on parent at 0, 0, w wide and h tall. groups is { { label, pages = { { id, label } } } } in
-- order, and choose(id) runs when a page's button is clicked. Returns show(id), which marks page id chosen.
function pagenav.create(parent, w, h, groups, choose)
  rect(parent, COLOURS.sidebar, 0, 0, w, h)
  rect(parent, COLOURS.line, w - 1, 0, 1, h)
  local buttons = {}
  local y = 0
  for _, group in ipairs(groups) do
    local heading = draw.windowText(parent, FONTS.small, ui.AlignMode.TOPLEFT, PAD + 6, y + 14, w - 2 * PAD, 16)
    set(heading, "content", group.label)
    set(heading, "rgb", COLOURS.accent)
    y = y + GROUP_H
    for _, page in ipairs(group.pages) do
      local button = {
        ring = rect(parent, COLOURS.ring, PAD, y, w - 2 * PAD - 1, BUTTON_H),
        fill = draw.hitArea(
          rect(parent, COLOURS.sidebar, PAD + RING, y + RING, w - 2 * PAD - 1 - 2 * RING, BUTTON_H - 2 * RING)
        ),
      }
      button.label = draw.windowText(
        parent,
        FONTS.body,
        ui.AlignMode.TOPLEFT,
        PAD + 8,
        y + RING,
        w - 2 * PAD - 8,
        BUTTON_H - 2 * RING
      )
      set(button.label, "content", page.label)
      draw.on(button.fill, "ONCLICK", function()
        choose(page.id)
      end)
      buttons[page.id] = button
      y = y + BUTTON_H + GAP
    end
  end

  return function(chosen)
    for id, button in pairs(buttons) do
      local on = id == chosen
      set(button.ring, "hidden", not on)
      set(button.fill, "rgb", on and COLOURS.accent or COLOURS.sidebar)
      set(button.label, "rgb", on and COLOURS.darkText or COLOURS.text)
    end
  end
end

return pagenav
