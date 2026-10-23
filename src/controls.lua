-- Controls for the options window and edit mode, built on src/draw: buttons, text and number fields, steppers,
-- choice buttons and the close X.
local draw = require("src/draw")
local util = require("src/util")

local controls = {}

-- Button fills: normal and hover colours, dark text for the bright ones, and an edge colour for the edged ones.
-- plain, accent and light suit edit mode; dark and gold suit the options window.
local FILLS = {
  plain = { draw.COLOURS.button, draw.COLOURS.buttonHover },
  accent = { draw.COLOURS.accent, draw.COLOURS.accentHover, dark = draw.COLOURS.accentText },
  light = { draw.COLOURS.highlight, draw.COLOURS.dimText, dark = draw.COLOURS.accentText },
  dark = { draw.WINDOW.button, draw.WINDOW.buttonHover, edge = draw.WINDOW.bronze, text = draw.WINDOW.text },
  gold = { draw.WINDOW.accent, draw.WINDOW.accentHover, dark = draw.WINDOW.accentText },
}

-- A flat button with a centred label that lightens on hover. fill names a FILLS entry, plain when nil. An edged
-- fill draws a 1px edge inside the button's box. onClick takes the click's x and y inside the button. Returns
-- { bg, label, group }: bg is the hit area, and group, a draw.group of every part, moves and hides the button.
function controls.button(parent, label, x, y, w, h, fill, onClick)
  local colours = FILLS[fill or "plain"]
  local normal = colours[1]
  local hover = colours[2]
  local group = draw.group()
  local bg = group.add(draw.hitArea(draw.rect(parent, colours.edge or normal, x, y, w, h)), 0, 0)
  local face = colours.edge and group.add(draw.rect(parent, normal, x + 1, y + 1, w - 2, h - 2), 1, 1) or bg
  local t = group.add(draw.text(parent, draw.FONTS.body, ui.AlignMode.CENTRE, x, y, w, h), 0, 0)
  draw.set(t, "content", label)
  if colours.text then
    draw.set(t, "rgb", colours.text)
  end
  if colours.dark then
    draw.set(t, "rgb", colours.dark)
    draw.set(t, "isShadowed", false)
  end
  draw.on(bg, "ONMOUSEOVER", function()
    draw.set(face, "rgb", hover)
  end)
  draw.on(bg, "ONMOUSELEAVE", function()
    draw.set(face, "rgb", normal)
  end)
  draw.on(bg, "ONCLICK", function(_, cx, cy)
    onClick(cx, cy)
  end)
  group.x = x
  group.y = y
  return { bg = bg, label = t, group = group }
end

-- A w by h text field at x, y taking up to maxLength characters, drawn with the plain input style, or the search
-- box style when search is true.
function controls.inputField(parent, x, y, w, h, maxLength, search)
  local field = ui.InputField.new(parent)
  draw.pos(field, x, y)
  draw.size(field, w, h)
  field:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, maxLength)
  local sheet = search and id.StyleSheet.INPUT_SEARCHBOX_24PX or id.StyleSheet.INPUT_DEFAULT
  if sheet ~= nil then
    draw.set(field, "stylesheetID", sheet)
  end
  return field
end

-- A typed whole number from low to high in steps of step, 1 when nil, in a w by h field at x, y. A keystroke
-- leaving a number in range on a step calls onChoose(n); Enter, Esc or focus loss calls it with the typed number
-- rounded to a step and clamped, then shows the chosen value again, so the field never keeps text it did not
-- take. Returns { field, show(n) }.
function controls.numberField(parent, x, y, w, h, low, high, onChoose, step)
  step = step or 1
  local field = controls.inputField(parent, x, y, w, h, #tostring(high))
  local number = { field = field }
  local shown

  function number.show(n)
    shown = n
    draw.set(field, "content", tostring(n))
  end

  draw.on(field, "ONCONTENTCHANGED", function(_, reason, contents)
    local n = math.tointeger(tonumber((contents or ""):match("^%s*(%d+)%s*$")))
    if reason == ui.InputFieldActionResult.CONTENT_CHANGE then
      if n ~= nil and n >= low and n <= high and n % step == 0 then
        onChoose(n)
      end
      return
    end
    if n ~= nil then
      onChoose(util.clamp((n + step // 2) // step * step, low, high))
    end
    if shown == nil then
      return
    end
    draw.forget(field, "content")
    draw.set(field, "content", tostring(shown))
  end)
  return number
end

-- The width of a controls.stepper, and the height of its buttons.
controls.STEPPER_W = 124
local STEPPER_H = 28
-- Alpha of a control whose setting has no effect at the moment.
controls.FADED = 0.45

-- A "- number +" stepper at x, y on parent, controls.STEPPER_W wide: a controls.numberField between two dark buttons
-- that move the shown number by step from low to high. save(n) takes each new number, from a button or the
-- field. allowed(y), when given, takes a button click's y on parent and says whether it lands where the stepper
-- shows, for a stepper in a clipped list. Returns { show(n), fade(faded), field, buttons }: show puts n in the
-- field, fade dims the stepper while its setting has no effect, and buttons holds the two draw.buttons.
function controls.stepper(parent, x, y, low, high, step, save, allowed)
  local field = controls.numberField(parent, x + 32, y + 2, 56, 24, low, high, save, step)
  local shown = low
  local function move(delta)
    return function(_, cy)
      if allowed == nil or allowed(y + cy) then
        save(util.clamp(shown + delta, low, high))
      end
    end
  end
  local minus = controls.button(parent, "-", x, y, STEPPER_H, STEPPER_H, "dark", move(-step))
  local plus =
    controls.button(parent, "+", x + controls.STEPPER_W - STEPPER_H, y, STEPPER_H, STEPPER_H, "dark", move(step))
  return {
    field = field.field,
    buttons = { minus, plus },
    show = function(n)
      shown = n
      field.show(n)
    end,
    fade = function(faded)
      local alpha = faded and controls.FADED or 1
      minus.group.set("alpha", alpha)
      plus.group.set("alpha", alpha)
      draw.set(field.field, "alpha", alpha)
    end,
  }
end

-- An options window choice button at x, y sized w by h: dark with a bronze edge, or once controls.showOption marks
-- it chosen, gold with dark text and a 2px white ring outside its box. onClick takes the click's x and y inside
-- the button. Returns { ring, bg, face, label }; bg is the hit area, which onClick and hover hang from.
function controls.option(parent, label, x, y, w, h, onClick)
  local W = draw.WINDOW
  local o = {
    ring = draw.rect(parent, W.ring, x - 2, y - 2, w + 4, h + 4),
    bg = draw.hitArea(draw.rect(parent, W.bronze, x, y, w, h)),
    face = draw.rect(parent, W.button, x + 1, y + 1, w - 2, h - 2),
    label = draw.windowText(parent, draw.FONTS.body, ui.AlignMode.CENTRE, x, y, w, h),
    chosen = false,
  }
  draw.set(o.ring, "hidden", true)
  draw.set(o.label, "content", label)
  draw.on(o.bg, "ONMOUSEOVER", function()
    if not o.chosen then
      draw.set(o.face, "rgb", W.buttonHover)
    end
  end)
  draw.on(o.bg, "ONMOUSELEAVE", function()
    if not o.chosen then
      draw.set(o.face, "rgb", W.button)
    end
  end)
  draw.on(o.bg, "ONCLICK", function(_, cx, cy)
    onClick(cx, cy)
  end)
  return o
end

-- Marks a controls.option chosen or not.
function controls.showOption(o, chosen)
  local W = draw.WINDOW
  o.chosen = chosen
  draw.set(o.ring, "hidden", not chosen)
  draw.set(o.bg, "rgb", chosen and W.accent or W.bronze)
  draw.set(o.face, "rgb", chosen and W.accent or W.button)
  draw.set(o.label, "rgb", chosen and W.accentText or W.text)
  draw.set(o.label, "isShadowed", not chosen)
end

-- The game's window close X, as PrettyUI's window draws it: its normal and hovered sprites and its size.
local CLOSE =
  { normal = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_NML, hover = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_OVR }
controls.CLOSE_SIZE = 20

-- A close X at x, y on parent, lit while hovered, calling onClick when clicked. A click unlights it, since its
-- popup hides with the cursor still over it. Returns the sprite.
function controls.closeButton(parent, x, y, onClick)
  local button = draw.hitArea(ui.Sprite.new(parent))
  draw.pos(button, x, y)
  draw.size(button, controls.CLOSE_SIZE, controls.CLOSE_SIZE)
  draw.set(button, "sprite", CLOSE.normal)
  draw.on(button, "ONMOUSEOVER", function()
    draw.set(button, "sprite", CLOSE.hover)
  end)
  draw.on(button, "ONMOUSELEAVE", function()
    draw.set(button, "sprite", CLOSE.normal)
  end)
  draw.on(button, "ONCLICK", function()
    draw.set(button, "sprite", CLOSE.normal)
    onClick()
  end)
  return button
end

return controls
