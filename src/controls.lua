-- Controls for the options window and edit mode, built on src/draw: buttons, text and number fields, steppers,
-- choice buttons and the close X, and the game's own button, radio group and check box, which cost one
-- component each.
local draw = require("src/draw")
local util = require("src/util")

local controls = {}

-- Button fills: normal and hover colours, dark text for the bright ones, and an edge colour for the edged ones.
-- plain and accent suit edit mode; dark and gold suit the options window.
local FILLS = {
  plain = { draw.COLOURS.button, draw.COLOURS.buttonHover },
  accent = { draw.COLOURS.accent, draw.COLOURS.accentHover, dark = draw.COLOURS.accentText },
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
  draw.set(t, "rgb", colours.dark or colours.text or draw.COLOURS.text)
  draw.set(t, "isShadowed", colours.dark == nil)
  draw.on(bg, "ONMOUSEOVER", function()
    draw.set(face, "rgb", hover)
  end)
  draw.on(bg, "ONMOUSELEAVE", function()
    draw.set(face, "rgb", normal)
  end)
  draw.on(bg, "ONCLICK", function(_, cx, cy)
    onClick(cx, cy)
  end)
  return { bg = bg, label = t, group = group }
end

-- Gives c the game stylesheet named sheet, when the client has it.
local function styled(c, sheet)
  local sheetID = id.StyleSheet[sheet]
  if sheetID ~= nil then
    draw.set(c, "stylesheetID", sheetID)
  end
  return c
end

-- A w by h text field at x, y taking up to maxLength characters, drawn with the plain input style, or the search
-- box style when search is true.
function controls.inputField(parent, x, y, w, h, maxLength, search)
  local field = draw.new(ui.InputField, parent)
  draw.pos(field, x, y)
  draw.size(field, w, h)
  field:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, maxLength)
  return styled(field, search and "INPUT_SEARCHBOX_24PX" or "INPUT_DEFAULT")
end

-- A typed whole number from low to high in steps of step in a w by h field at x, y. A keystroke
-- leaving a number in range on a step calls onChoose(n); Enter, Esc or focus loss calls it with the typed number
-- rounded to a step and clamped, then shows the chosen value again, so the field never keeps text it did not
-- take. Returns { field, show(n), clip(clipped) }: clip blanks the field's text while clipped.
local function numberField(parent, x, y, w, h, low, high, onChoose, step)
  local field = controls.inputField(parent, x, y, w, h, #tostring(high))
  local number = { field = field }
  local shown
  local clipped = false

  local function showText()
    draw.set(field, "content", clipped and "" or tostring(shown))
  end

  function number.show(n)
    shown = n
    showText()
  end

  function number.clip(c)
    if c ~= clipped then
      clipped = c
      if shown ~= nil then
        showText()
      end
    end
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
    showText()
  end)
  return number
end

-- The game's own button, w by h at x, y on parent, reading label. onPress runs on each press. Returns the button.
function controls.gameButton(parent, label, x, y, w, h, onPress)
  local button = styled(draw.new(ui.Button, parent), "BUTTON_DEFAULT")
  draw.pos(button, x, y)
  draw.size(button, w, h)
  draw.set(button, "label", label)
  draw.on(button, "ONBUTTONPRESSED", function()
    onPress()
  end)
  return button
end

-- The game's radio group, w by h at x, y on parent: a round button left of each choice's label, { id, label },
-- in columns columns, one choice at a time. onChoose(id) runs on the player's choice. Returns { group,
-- show(id) }: show marks id chosen, or none when no choice has it, writing only when that changes.
function controls.radio(parent, x, y, w, h, choices, columns, onChoose)
  local group = styled(draw.new(ui.RadioGroup, parent), "RADIO_DEFAULT")
  draw.pos(group, x, y)
  draw.size(group, w, h)
  group:SetVisualParams(columns, 4, 16, 6)
  local entryOf = {}
  for i, choice in ipairs(choices) do
    group:Add(i, choice.label)
    entryOf[choice.id] = i
  end
  local shownEntry = nil
  draw.on(group, "ONSELECTIONCHANGED", function(_, entry, selected)
    if selected ~= 1 or entry == shownEntry or choices[entry] == nil then
      return
    end
    shownEntry = entry
    onChoose(choices[entry].id)
  end)
  return {
    group = group,
    -- With one choice at a time the client refuses to clear or move the choice itself, so the limits open
    -- while it moves.
    show = function(value)
      local entry = entryOf[value]
      if entry == shownEntry then
        return
      end
      group:SetSelectionLimits(0, 1)
      if shownEntry ~= nil then
        group:SetOptionSelected(shownEntry, false, false)
      end
      if entry ~= nil then
        group:SetOptionSelected(entry, true, false)
        group:SetSelectionLimits(1, 1)
      end
      shownEntry = entry
    end,
  }
end

-- The game's check box, size by size at x, y on parent. onToggle(ticked) runs when the player ticks or unticks
-- it. Returns { check, show(ticked), fade(faded) }: show ticks it or not, writing only when that changes, and
-- fade dims it while its setting has no effect.
function controls.check(parent, x, y, size, onToggle)
  local check = styled(draw.new(ui.Check, parent), "CHECKBOX_DEFAULT")
  draw.pos(check, x, y)
  draw.size(check, size, size)
  local shown = false
  draw.on(check, "ONBUTTONPRESSED", function(self)
    local ticked = self.value == true
    if ticked == shown then
      return
    end
    shown = ticked
    onToggle(ticked)
  end)
  return {
    check = check,
    show = function(ticked)
      -- The player's ticks change value outside src/draw, so this writes it directly.
      if ticked ~= shown then
        shown = ticked
        check.value = ticked
      end
    end,
    fade = function(faded)
      draw.set(check, "alpha", faded and controls.FADED or 1)
    end,
  }
end

-- The width of a controls.stepper, and the height of its buttons.
controls.STEPPER_W = 124
local STEPPER_H = 28
local STEPPER_FIELD_H = 24
-- Alpha of a control whose setting has no effect at the moment.
controls.FADED = 0.45

-- A "- number +" stepper at x, y on parent, controls.STEPPER_W wide: a numberField between two game buttons
-- that move the shown number by step from low to high. save(n) takes each new number, from a button or the
-- field. Returns { show(n), fade(faded), clip(clipped), field, fieldY, fieldH, buttons }: show puts n in the
-- field, fade dims the stepper while its setting has no effect, clip blanks the field's text while clipped,
-- fieldY and fieldH give the field's top on parent and its height, and buttons holds the two game buttons.
function controls.stepper(parent, x, y, low, high, step, save)
  local field = numberField(parent, x + 32, y + 2, 56, STEPPER_FIELD_H, low, high, save, step)
  local shown = low
  local function move(delta)
    return function()
      save(util.clamp(shown + delta, low, high))
    end
  end
  local minus = controls.gameButton(parent, "-", x, y, STEPPER_H, STEPPER_H, move(-step))
  local plus = controls.gameButton(parent, "+", x + controls.STEPPER_W - STEPPER_H, y, STEPPER_H, STEPPER_H, move(step))
  return {
    field = field.field,
    clip = field.clip,
    fieldY = y + 2,
    fieldH = STEPPER_FIELD_H,
    buttons = { minus, plus },
    show = function(n)
      shown = n
      field.show(n)
    end,
    fade = function(faded)
      local alpha = faded and controls.FADED or 1
      draw.set(minus, "alpha", alpha)
      draw.set(plus, "alpha", alpha)
      draw.set(field.field, "alpha", alpha)
    end,
  }
end

-- A group of options window choice buttons, such as a row of choices, that draws every button's frame on one
-- canvas on parent. controls.option adds a button to it; a hover or a change of choice redraws the canvas.
function controls.optionGroup(parent)
  local canvas = draw.new(ui.Canvas, parent)
  draw.pos(canvas, 0, 0)
  return { canvas = canvas, options = {}, w = 0, h = 0 }
end

-- Adds o's frame to canvas: a 2px white ring when chosen, then its edge and face.
local function addFrame(canvas, o)
  local W = draw.WINDOW
  if o.chosen then
    canvas:AddRectangle(o.x - 2, o.y - 2, o.w + 4, o.h + 4, draw.opaque(W.ring))
  end
  canvas:AddRectangle(o.x, o.y, o.w, o.h, draw.opaque(o.chosen and W.accent or W.bronze))
  local face = o.chosen and W.accent or o.hovered and W.buttonHover or W.button
  canvas:AddRectangle(o.x + 1, o.y + 1, o.w - 2, o.h - 2, draw.opaque(face))
end

local function redrawFrames(group)
  group.canvas:Clear()
  for _, o in ipairs(group.options) do
    addFrame(group.canvas, o)
  end
end

-- An options window choice button at x, y sized w by h: dark with a bronze edge and lighter while hovered, or once
-- controls.showOption marks it chosen, gold with dark text and a 2px white ring outside its box. Its frame draws
-- on group, a controls.optionGroup, or on a group of its own. onClick takes the click's x and y inside the button.
-- Returns { bg, label, canvas }: bg is the transparent hit area, which onClick and hover hang from, and canvas
-- the group's.
function controls.option(parent, label, x, y, w, h, onClick, group)
  group = group or controls.optionGroup(parent)
  local o = { x = x, y = y, w = w, h = h, chosen = false, hovered = false, canvas = group.canvas }
  group.options[#group.options + 1] = o
  group.w = math.max(group.w, x + w + 2)
  group.h = math.max(group.h, y + h + 2)
  draw.size(group.canvas, group.w, group.h)
  addFrame(group.canvas, o)
  o.bg = draw.hitArea(draw.rect(parent, draw.WINDOW.bronze, x, y, w, h))
  draw.set(o.bg, "alpha", 0)
  o.label = draw.windowText(parent, draw.FONTS.body, ui.AlignMode.CENTRE, x, y, w, h)
  draw.set(o.label, "content", label)
  draw.on(o.bg, "ONMOUSEOVER", function()
    if not o.chosen and not o.hovered then
      o.hovered = true
      redrawFrames(group)
    end
  end)
  draw.on(o.bg, "ONMOUSELEAVE", function()
    if o.hovered then
      o.hovered = false
      redrawFrames(group)
    end
  end)
  draw.on(o.bg, "ONCLICK", function(_, cx, cy)
    onClick(cx, cy)
  end)
  o.group = group
  return o
end

-- Marks a controls.option chosen or not, redrawing its group's frames when that changes.
function controls.showOption(o, chosen)
  local W = draw.WINDOW
  draw.set(o.label, "rgb", chosen and W.accentText or W.text)
  draw.set(o.label, "isShadowed", not chosen)
  if o.chosen ~= chosen then
    o.chosen = chosen
    o.hovered = false
    redrawFrames(o.group)
  end
end

-- The game's window close X, as PrettyUI's window draws it: its normal and hovered sprites and its size.
local CLOSE =
  { normal = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_NML, hover = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_OVR }
controls.CLOSE_SIZE = 20

-- A close X at x, y on parent, lit while hovered, calling onClick when clicked. A click unlights it, since its
-- popup hides with the cursor still over it. Returns the sprite.
function controls.closeButton(parent, x, y, onClick)
  local button = draw.hitArea(draw.new(ui.Sprite, parent))
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
