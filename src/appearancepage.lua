-- The options window's Appearance and Bars pages. Each has a preview strip of HUD elements, drawn by src/view
-- from sample models over a Dark, Light or Game backdrop, fixed above its settings: Text, Unit frames and Game
-- interfaces on Appearance, the adrenaline bar and the cast bar on Bars. The settings scroll by pixels inside a
-- clipping layer, moved by the wheel and a scrollbar. Rows wholly out of view hide, and a click lands only where
-- its row shows. Every change saves, then redraws the preview and the HUD.
local draw = require("src/draw")
local frames = require("src/frames")
local settings = require("src/settings")
local style = require("src/style")

local appearancepage = {}

local set, rect, text, hitArea, on = draw.set, draw.rect, draw.windowText, draw.hitArea, draw.on
local FONTS, COLOURS = draw.FONTS, draw.WINDOW

local STRIP_H = 168
-- Preview backdrops: black, light lilac, or none to show the game world.
local BACKDROPS = {
  { id = "dark", label = "Dark", rgb = 0x15120f },
  { id = "light", label = "Light", rgb = 0xd8c6da },
  { id = "game", label = "Game" },
}
local ROW_H, HEADING_H, END_SPACE, MARGIN = 50, 40, 32, 16
-- The wheel reports many small deltas per turn, negative while scrolling down; each moves WHEEL_STEP px.
local SCROLLBAR_W, WHEEL_STEP = 10, 8
-- Side of the transparent square that holds a thumb drag under the cursor, which a fast move cannot leave.
local GRAB = 160
local OPTION_H = 28
-- Alpha of a stepper whose setting another choice overrides.
local FADED = 0.45
-- Colour rows: two lines of swatches and the hex field, and the picker's shade square and hue strip under them.
local SWATCH_W, SWATCH_GAP, HEX_W, HEX_H = 84, 4, 86, 24
local COLOUR_ROW_H = 10 + 2 * OPTION_H + 8 + 10
local PICKER_W, PICKER_H, HUE_W, PICKER_SPACE = 180, 110, 18, 12
-- The hue strip's colours from top to bottom, at hues 360 down to 0.
local HUE_STOPS = { 0xFF0000FF, 0xFF00FFFF, 0x0000FFFF, 0x00FFFFFF, 0x00FF00FF, 0xFFFF00FF, 0xFF0000FF }

-- Sample models the preview draws: tiles with keybinds on light and dark icons, one cooling, an aura with its
-- timer, and the two unit frames.
local SAMPLE_TILES = {
  { key = "A", name = "Living Death", initials = "LD", icon = 30078, keybind = "T", ready = true },
  { key = "B", name = "Death Skulls", initials = "DS", icon = 30074, keybind = "R", ready = true },
  { key = "C", name = "Split Soul", initials = "SS", icon = 30706, keybind = "V", remaining = 12, ready = false },
  { key = "D", name = "Touch of Death", initials = "TD", icon = 30076, keybind = "2", ready = true },
  { key = "E", name = "Soul Sap", initials = "SS", icon = 30080, keybind = "Q", ready = true },
}
local SAMPLE_AURAS = { { sprite = 14766, text = "4m", left = 240, full = 300, fill = 0.8 } }
local SAMPLE_PLAYER = {
  available = true,
  name = "Player",
  lifepoints = 12242,
  lifepointsLabel = "12,242/15,695",
  prayerValue = 640,
  prayerLabel = "64/99",
}
local SAMPLE_TARGET = { target = 1, name = "Rasial", lifepointsLabel = "58,000", healthPercent = 58 }
local TILE_SIZE, PREVIEW_X, PREVIEW_Y, PREVIEW_GAP = 36, 20, 14, 6
-- The Bars preview: adrenaline at 89% with two souls and six necrosis stacks, and a channel two ticks from its
-- end with two hits ahead.
local SAMPLE_ADRENALINE = {
  adrenaline = 890,
  necromancy = true,
  spenders = { COMBATV2_BUFF_NECROMANCY_RESIDUAL_SOUL_STACKS = 2, COMBATV2_BUFF_NECROMANCY_NECROSIS_STACKS = 6 },
}
local SAMPLE_CAST = {
  start = 1,
  name = "Greater Concentrated Blast",
  icon = 13310,
  style = "magic",
  duration = 3.6,
  ticksLeft = 2,
  hits = { 0, 1.2, 2.4 },
}

local TEXTURES = {
  { id = "flat", label = "Flat" },
  { id = "vertical", label = "Vertical" },
  { id = "horizontal", label = "Horizontal" },
}
local SHOW_HIDE = { { id = false, label = "Show" }, { id = true, label = "Hide" } }
local WIDTH_FROM = { { id = false, label = "Own width" }, { id = true, label = "Same as adrenaline" } }
local MATCH_HUD = { id = "hud", label = "Match HUD" }

-- A settings page on page, width by height. deps: { saved = src/settings, view = src/view, tooltip =
-- view.tooltip, auraInfo(sprite), tracker = src/cooldowns tracker for the equipped style, refresh() redrawing the
-- HUD }. define(b) builds the preview's elements on b.preview and the rows through b, and returns
-- drawPreview(look, appearance). Returns { open, choiceRow, follow, cancel }: open redraws the page from settings,
-- choiceRow(parent, x, y, w, label, choices, field, optionW) builds a row of option buttons on another page,
-- such as the Buffs page's Display tab, follow runs every frame to move a held scrollbar thumb, and cancel ends
-- one.
local function settingsPage(page, width, height, deps, define)
  local saved = deps.saved
  local redraw

  -- Option rows -------------------------------------------------------------------------------------------

  -- Every choice row, each { choices = { [id] = draw.option }, field }, and every stepper's redraw.
  local choiceRows, steppers = {}, {}

  local function showChoices()
    local appearance = saved.appearance()
    for _, row in ipairs(choiceRows) do
      for value, option in pairs(row.choices) do
        draw.showOption(option, value == appearance[row.field])
      end
    end
    for _, show in ipairs(steppers) do
      show(appearance)
    end
  end

  local function choose(field, value)
    saved.setAppearance(field, value)
    redraw()
    deps.refresh()
  end

  -- A row's background, which takes clicks, and its label on parent at x, y, w wide and h tall, ROW_H when nil.
  -- Returns the background.
  local function rowBox(parent, x, y, w, label, shade, h)
    local bg = hitArea(rect(parent, shade and COLOURS.rowAlt or COLOURS.row, x, y, w, h or ROW_H))
    local t = text(parent, FONTS.body, ui.AlignMode.TOPLEFT, x + 16, y, 200, ROW_H)
    set(t, "content", label)
    return bg
  end

  -- Right-aligned option buttons optionW wide, ending at right, choosing the saved appearance field from
  -- choices, { { id, label } }. allowed(y), when given, takes the y of a click inside a button and says whether
  -- it lands where the row shows. Returns the buttons by id.
  local function options(parent, right, y, choices, field, optionW, allowed)
    local row = { choices = {}, field = field }
    for i, choice in ipairs(choices) do
      local x = right - (#choices - i + 1) * (optionW + 4) + 4
      local by = y + (ROW_H - OPTION_H) // 2
      row.choices[choice.id] = draw.option(parent, choice.label, x, by, optionW, OPTION_H, function(_, cy)
        if allowed == nil or allowed(by + cy) then
          choose(field, choice.id)
        end
      end)
    end
    choiceRows[#choiceRows + 1] = row
    return row.choices
  end

  local function choiceRow(parent, x, y, w, label, choices, field, optionW)
    rowBox(parent, x, y, w, label, false)
    return options(parent, x + w - 12, y, choices, field, optionW)
  end

  -- Preview strip -----------------------------------------------------------------------------------------

  local backdrop = hitArea(rect(page, COLOURS.panel, 0, 0, width, STRIP_H))
  local preview = ui.Layer.new(page)
  preview:SetSize(width, STRIP_H)
  rect(page, COLOURS.border, 0, STRIP_H, width, 1)
  local backdropChoice = "light"
  local backdropOptions = {}

  local function showBackdrop()
    local chosen = style.find(BACKDROPS, backdropChoice)
    set(backdrop, "alpha", chosen.rgb and 1 or 0)
    if chosen.rgb then
      set(backdrop, "rgb", chosen.rgb)
    end
    for id_, option in pairs(backdropOptions) do
      draw.showOption(option, id_ == backdropChoice)
    end
  end

  for i, entry in ipairs(BACKDROPS) do
    backdropOptions[entry.id] = draw.option(page, entry.label, width - 70, 8 + (i - 1) * 26, 62, 22, function()
      backdropChoice = entry.id
      showBackdrop()
    end)
  end

  -- Scrolling settings ------------------------------------------------------------------------------------

  local viewH = height - STRIP_H - 1
  local viewport = ui.Layer.new(page)
  draw.pos(viewport, 0, STRIP_H + 1)
  draw.size(viewport, width, viewH)
  local viewportBg = hitArea(rect(viewport, COLOURS.panel, 0, 0, width, viewH))
  local content = ui.Layer.new(viewport)
  local rowW = width - 2 * MARGIN - SCROLLBAR_W - 4
  local rowRight = MARGIN + rowW - 12
  local track = hitArea(rect(viewport, COLOURS.sidebar, width - SCROLLBAR_W - 4, 0, SCROLLBAR_W, viewH))
  local thumb = rect(viewport, COLOURS.bronze, width - SCROLLBAR_W - 3, 0, SCROLLBAR_W - 2, 0)
  -- Rows from the top: { layer, y, h }, the content's height and how far it is scrolled.
  local rows, contentH, scroll = {}, 0, 0

  local function maxScroll()
    return math.max(0, contentH - viewH)
  end

  local function thumbBox()
    local h = math.max(24, viewH * math.min(1, viewH / contentH))
    local max = maxScroll()
    return max == 0 and 0 or math.floor((viewH - h) * scroll / max + 0.5), math.floor(h)
  end

  -- The thumb's grab area, built on the page above the settings, and the drag it holds: { origin, y, scroll },
  -- with the cursor's offset from page coordinates, or nil.
  local grip, held

  -- Puts the grab area over the thumb.
  local function placeGrip()
    local ty, th = thumbBox()
    draw.pos(grip, width - SCROLLBAR_W - 4, STRIP_H + 1 + ty)
    draw.size(grip, SCROLLBAR_W, th)
    set(grip, "hidden", maxScroll() == 0)
  end

  local function scrollTo(y)
    scroll = math.max(0, math.min(maxScroll(), y))
    draw.pos(content, 0, -scroll)
    for _, row in ipairs(rows) do
      set(row.layer, "hidden", row.y + row.h <= scroll or row.y >= scroll + viewH)
    end
    local ty, th = thumbBox()
    draw.pos(thumb, width - SCROLLBAR_W - 3, ty)
    draw.size(thumb, SCROLLBAR_W - 2, th)
    set(thumb, "hidden", maxScroll() == 0)
    if grip ~= nil and held == nil then
      placeGrip()
    end
  end

  local function wheel(c)
    on(c, "ONSCROLLWHEEL", function(_, delta)
      scrollTo(scroll - delta * WHEEL_STEP)
    end)
  end
  wheel(viewportBg)
  wheel(track)
  on(track, "ONCLICK", function(_, _, y)
    local ty, th = thumbBox()
    if y < ty then
      scrollTo(scroll - viewH)
    elseif y > ty + th then
      scrollTo(scroll + viewH)
    end
  end)

  -- A layer at the content's end, h tall, which hides once scrolled wholly out of view. relayout places it.
  local function addRow(h)
    local row = { layer = ui.Layer.new(content), h = h }
    rows[#rows + 1] = row
    return row
  end

  -- Stacks the rows at their heights, with END_SPACE below the last, and keeps the scroll in range.
  local function relayout()
    local y = 0
    for _, row in ipairs(rows) do
      row.y = y
      draw.pos(row.layer, 0, y)
      draw.size(row.layer, width, row.h)
      y = y + row.h
    end
    contentH = y + END_SPACE
    draw.size(content, width, contentH)
    scrollTo(scroll)
  end

  -- Whether a click at y inside row's layer lands where the viewport shows it.
  local function shows(row, y)
    local top = row.y + y - scroll
    return top >= 0 and top < viewH
  end

  local shade = false

  local function heading(label)
    local row = addRow(HEADING_H)
    local t = text(row.layer, FONTS.smallSeconds, ui.AlignMode.TOPLEFT, MARGIN, 14, rowW, HEADING_H - 14)
    set(t, "content", label)
    set(t, "rgb", COLOURS.accent)
    shade = false
  end

  -- A settings row with its label, h tall or ROW_H; its background, row.bg, takes the wheel.
  local function settingRow(label, h)
    local row = addRow(h or ROW_H)
    row.bg = rowBox(row.layer, MARGIN, 0, rowW, label, shade, h)
    wheel(row.bg)
    shade = not shade
    return row
  end

  -- Option buttons on row's layer ending at right, choosing field from choices; returns the buttons by id.
  local function rowOptions(row, right, choices, field, optionW)
    local buttons = options(row.layer, right, 0, choices, field, optionW, function(y)
      return shows(row, y)
    end)
    for _, option in pairs(buttons) do
      wheel(option.bg)
    end
    return buttons
  end

  local function scrolledChoices(label, choices, field, optionW)
    return rowOptions(settingRow(label), rowRight, choices, field, optionW)
  end

  -- A - number + stepper from low to high, its number typed: value(appearance) gives the number shown and
  -- save(n) takes a new one. Returns the row, whose fade(faded) dims the stepper while the setting has no effect.
  local function numberRow(label, low, high, value, save)
    local row = settingRow(label)
    local by = (ROW_H - OPTION_H) // 2
    local field = draw.numberField(row.layer, rowRight - 92, (ROW_H - HEX_H) // 2, 56, HEX_H, low, high, save)
    local function move(delta)
      return function(_, y)
        if shows(row, by + y) then
          save(math.max(low, math.min(high, value(saved.appearance()) + delta)))
        end
      end
    end
    local minus = draw.button(row.layer, "-", rowRight - 124, by, 28, OPTION_H, "dark", move(-1))
    local plus = draw.button(row.layer, "+", rowRight - 28, by, 28, OPTION_H, "dark", move(1))
    wheel(minus.bg)
    wheel(plus.bg)
    steppers[#steppers + 1] = function(appearance)
      field.show(value(appearance))
    end
    function row.fade(faded)
      local alpha = faded and FADED or 1
      minus.group.set("alpha", alpha)
      plus.group.set("alpha", alpha)
      set(field.field, "alpha", alpha)
    end
    return row
  end

  -- A number row for the appearance field, from low to high.
  local function stepperRow(label, field, low, high)
    return numberRow(label, low, high, function(appearance)
      return appearance[field]
    end, function(n)
      if n ~= saved.appearance()[field] then
        choose(field, n)
      end
    end)
  end

  -- A preset swatch on parent at x, y in its colour with its name on it, a white ring when chosen.
  local function swatch(parent, x, y, label, onClick)
    local sw = {
      ring = rect(parent, COLOURS.ring, x - 2, y - 2, SWATCH_W + 4, OPTION_H + 4),
      bg = hitArea(rect(parent, COLOURS.border, x, y, SWATCH_W, OPTION_H)),
      label = draw.edgedText(parent, FONTS.small, ui.AlignMode.CENTRE, x, y, SWATCH_W, OPTION_H),
    }
    set(sw.label, "content", label)
    set(sw.label, "isShadowed", false)
    draw.setEdge(sw.label, COLOURS.border)
    on(sw.bg, "ONCLICK", function(_, _, cy)
      onClick(y + cy)
    end)
    wheel(sw.bg)
    return sw
  end

  -- Each colour row's redraw, given the appearance.
  local colourRows = {}

  -- A colour row choosing field: a swatch per preset, { id, label }, in presetRgb(id), Custom, and a hex field
  -- taking "#RRGGBB". shownRgb(look) is the colour the field draws in. Custom opens a shade square and hue strip
  -- under them, built on first open.
  local function colourRow(label, field, presets, presetRgb, shownRgb)
    local row = settingRow(label, COLOUR_ROW_H)
    local function allowed(y)
      return shows(row, y)
    end
    local lineY = { 10, 10 + OPTION_H + 8 }
    local swatches, perLine = {}, 5
    for i, preset in ipairs(presets) do
      local line, slot = (i - 1) // perLine + 1, (i - 1) % perLine
      local x = rowRight - perLine * (SWATCH_W + SWATCH_GAP) + SWATCH_GAP + slot * (SWATCH_W + SWATCH_GAP)
      swatches[preset.id] = swatch(row.layer, x, lineY[line], preset.label, function(y)
        if allowed(y) then
          choose(field, preset.id)
        end
      end)
    end
    local customX = rowRight - 2 * (SWATCH_W + SWATCH_GAP) + SWATCH_GAP
    local hexX = rowRight - HEX_W
    local hex = draw.inputField(row.layer, hexX, lineY[2] + (OPTION_H - HEX_H) // 2, HEX_W, HEX_H, 7)
    -- The field also reports its contents on Enter, Esc and focus loss, so an unchanged colour is skipped.
    on(hex, "ONCONTENTCHANGED", function(_, _, contents)
      local rgb = style.parseHex(contents)
      if rgb ~= nil and rgb ~= saved.appearance()[field] then
        choose(field, rgb)
      end
    end)

    -- The picker, built on first open: { square, hue, mark, hueMark, hue value }.
    local picker, open = nil, false
    local pickerY = COLOUR_ROW_H
    local squareX = rowRight - PICKER_W - HUE_W - 8

    local function paintSquare(hue)
      picker.square:Clear()
      picker.square:AddRectangle(0, 0, PICKER_W, PICKER_H, draw.opaque(style.rgb(hue, 1, 1)))
      picker.square:AddGradientH(0, 0, PICKER_W, PICKER_H, 0xFFFFFFFF, 0xFFFFFF00)
      picker.square:AddGradientV(0, 0, PICKER_W, PICKER_H, 0x00000000, 0x000000FF)
    end

    local function showPicker(rgb)
      local h, sat, v = style.hsv(rgb)
      if sat == 0 or v == 0 then
        h = picker.hueValue
      end
      if h ~= picker.painted then
        picker.painted = h
        paintSquare(h)
      end
      picker.hueValue = h
      draw.pos(picker.mark, squareX + math.floor(sat * PICKER_W) - 3, pickerY + math.floor((1 - v) * PICKER_H) - 3)
      draw.pos(picker.hueMark, squareX + PICKER_W + 6, pickerY + math.floor((1 - h / 360) * PICKER_H) - 2)
    end

    -- Saves the colour picked at x, y on the shade square, or at y on the hue strip when onHue.
    local function pick(x, y, onHue)
      local _, sat, v = style.hsv(colourRows[field].rgb)
      local h, fy = picker.hueValue, math.max(0, math.min(1, y / PICKER_H))
      if onHue then
        h = (1 - fy) * 360 % 360
      else
        sat, v = math.max(0, math.min(1, x / PICKER_W)), 1 - fy
      end
      picker.hueValue = h
      choose(field, style.rgb(h, sat, v))
    end

    local function build()
      picker = { hueValue = 0 }
      picker.square = hitArea(ui.Canvas.new(row.layer))
      draw.pos(picker.square, squareX, pickerY)
      draw.size(picker.square, PICKER_W, PICKER_H)
      picker.hue = hitArea(ui.Canvas.new(row.layer))
      draw.pos(picker.hue, squareX + PICKER_W + 8, pickerY)
      draw.size(picker.hue, HUE_W, PICKER_H)
      local segment = PICKER_H / (#HUE_STOPS - 1)
      for i = 1, #HUE_STOPS - 1 do
        local top = math.floor((i - 1) * segment)
        picker.hue:AddGradientV(0, top, HUE_W, math.floor(i * segment) - top, HUE_STOPS[i], HUE_STOPS[i + 1])
      end
      picker.mark = rect(row.layer, COLOURS.ring, 0, 0, 6, 6)
      picker.hueMark = rect(row.layer, COLOURS.ring, 0, 0, HUE_W + 4, 4)
      for _, part in ipairs({ picker.square, picker.hue }) do
        wheel(part)
      end
      on(picker.square, "ONCLICK", function(_, x, y)
        if allowed(pickerY + y) then
          pick(x, y, false)
        end
      end)
      on(picker.hue, "ONCLICK", function(_, x, y)
        if allowed(pickerY + y) then
          pick(x, y, true)
        end
      end)
    end

    local custom = draw.option(row.layer, "Custom", customX, lineY[2], SWATCH_W, OPTION_H, function(_, y)
      if not allowed(lineY[2] + y) then
        return
      end
      open = not open
      if open and picker == nil then
        build()
      end
      draw.hideAll({ picker.square, picker.hue, picker.mark, picker.hueMark }, not open)
      row.h = COLOUR_ROW_H + (open and PICKER_H + PICKER_SPACE or 0)
      draw.size(row.bg, rowW, row.h)
      relayout()
      if open then
        showPicker(colourRows[field].rgb)
      end
    end)
    wheel(custom.bg)

    colourRows[field] = {
      draw = function(look, appearance)
        local rgb = shownRgb(look)
        colourRows[field].rgb = rgb
        local chosen = appearance[field]
        for presetID, sw in pairs(swatches) do
          set(sw.bg, "rgb", presetRgb(presetID))
          set(sw.ring, "hidden", presetID ~= chosen)
        end
        draw.showOption(custom, type(chosen) == "number")
        if style.parseHex(hex.content) ~= rgb then
          hex.content = style.formatHex(rgb)
        end
        if open then
          showPicker(rgb)
        end
      end,
    }
  end

  local drawPreview = define({
    preview = preview,
    rowRight = rowRight,
    heading = heading,
    choices = scrolledChoices,
    options = rowOptions,
    number = numberRow,
    stepper = stepperRow,
    colour = colourRow,
    choose = choose,
    -- Redraws the page and the HUD after a change saved outside the appearance, such as a marker.
    changed = function()
      redraw()
      deps.refresh()
    end,
  })

  grip = hitArea(rect(page, COLOURS.panel, 0, 0, 0, 0))
  set(grip, "alpha", 0)
  wheel(grip)
  on(grip, "ONCLICK", function(_, x, y)
    draw.pressAt(grip, x)
    local mx, my = draw.cursor()
    if mx == nil then
      return
    end
    local ty = thumbBox()
    held = {
      origin = { x = mx - (width - SCROLLBAR_W - 4 + x), y = my - (STRIP_H + 1 + ty + y) },
      y = my,
      scroll = scroll,
    }
  end)
  on(grip, "ONRELEASE", function()
    held = nil
    placeGrip()
  end)
  relayout()

  -- Moves a held thumb with the cursor, every frame. Returns before reading the mouse unless it is held.
  local function follow()
    if held == nil then
      return
    end
    local mx, my = draw.cursor()
    if mx == nil or (mx == held.lastX and my == held.lastY) then
      return
    end
    held.lastX, held.lastY = mx, my
    local _, th = thumbBox()
    if viewH > th then
      scrollTo(held.scroll + (my - held.y) * maxScroll() / (viewH - th))
    end
    draw.size(grip, GRAB, GRAB)
    draw.pos(grip, math.floor(mx - held.origin.x) - GRAB // 2, math.floor(my - held.origin.y) - GRAB // 2)
  end

  function redraw()
    local appearance = saved.appearance()
    local look = style.look(appearance, deps.tracker.style())
    drawPreview(look, appearance)
    for _, row in pairs(colourRows) do
      row.draw(look, appearance)
    end
    showChoices()
  end

  return {
    open = function()
      redraw()
      showBackdrop()
      scrollTo(scroll)
    end,
    choiceRow = choiceRow,
    follow = follow,
    -- Ends a thumb drag, as when the window closes.
    cancel = function()
      held = nil
      placeGrip()
    end,
  }
end

-- The Appearance page; see settingsPage.
function appearancepage.create(page, width, height, deps)
  local view = deps.view
  return settingsPage(page, width, height, deps, function(b)
    local tiles = view.cooldownGroup(b.preview, deps.tooltip)
    tiles.configure({ size = TILE_SIZE, perRow = #SAMPLE_TILES, grow = "down" })
    local aura = view.auraRow(b.preview, view.AURA_STYLES.combatBuffs, deps.tooltip, deps.auraInfo)
    local player, target = view.playerFrame(b.preview), view.targetFrame(b.preview)
    local elements = { tiles, aura, player, target }

    b.heading("Text")
    local fonts = b.choices("Font", style.FAMILIES, "font", 112)
    for _, family in ipairs(style.FAMILIES) do
      set(fonts[family.id].label, "font", id.Font[family.sizes[13]])
    end
    b.number(
      "Text size",
      style.ROLES.body + settings.TEXT_STEP_MIN,
      style.ROLES.body + settings.TEXT_STEP_MAX,
      function(appearance)
        return style.ROLES.body + appearance.textStep
      end,
      function(n)
        if n - style.ROLES.body ~= deps.saved.appearance().textStep then
          b.choose("textStep", n - style.ROLES.body)
        end
      end
    )
    b.choices("Text edge", style.EDGES, "edge", 124)
    b.choices("Text colour", style.TEXT_COLOURS, "textColour", 112)

    b.heading("Unit frames")
    for _, frame in ipairs({ "player", "target" }) do
      local function presetRgb(presetID)
        if presetID == "runeui" then
          return style.FRAME_COLOURS[frame]
        end
        if presetID == "equipped" then
          return style.STYLE_COLOURS[deps.tracker.style()] or style.FRAME_COLOURS[frame]
        end
        return style.find(style.PRESETS, presetID).rgb
      end
      b.colour(
        frame == "player" and "Player colour" or "Target colour",
        frame .. "Colour",
        style.PRESETS,
        presetRgb,
        function(look)
          return look[frame]
        end
      )
    end
    b.choices("Bar texture", TEXTURES, "texture", 112)
    b.choices("Frame border", style.BORDERS, "border", 112)
    b.choices("Lifepoints text", frames.LIFEPOINTS, "lifepoints", 118)
    b.stepper("Frame width", "frameWidth", settings.FRAME_WIDTH.min, settings.FRAME_WIDTH.max)
    b.stepper("Frame height", "frameHeight", settings.FRAME_HEIGHT.min, settings.FRAME_HEIGHT.max)

    b.heading("Game interfaces")
    b.choices("Default target panel", SHOW_HIDE, "hideTargetPanel", 90)
    b.choices("Game cast bar", SHOW_HIDE, "hideCastBar", 90)

    return function(look, appearance)
      view.setLook(elements, look)
      tiles.update(SAMPLE_TILES, 0)
      aura.update(SAMPLE_AURAS, false)
      player.update(frames.player(SAMPLE_PLAYER, appearance.lifepoints))
      target.update(frames.target(SAMPLE_TARGET, appearance.lifepoints))
      local tilesW = #SAMPLE_TILES * (TILE_SIZE + 2) - 2
      draw.pos(tiles.layer, PREVIEW_X, PREVIEW_Y)
      draw.pos(aura.layer, PREVIEW_X + tilesW + 2 * PREVIEW_GAP - aura.bounds.x, PREVIEW_Y - aura.bounds.y)
      local framesY = PREVIEW_Y + TILE_SIZE + 2 * PREVIEW_GAP
      draw.pos(player.layer, PREVIEW_X, framesY)
      draw.pos(target.layer, PREVIEW_X + player.width + PREVIEW_GAP, framesY)
    end
  end)
end

-- The Bars page: the adrenaline bar's markers and size, where the spender rows sit, and the cast bar's width,
-- height, colour, font and text size; see settingsPage.
function appearancepage.bars(page, width, height, deps)
  local view, saved = deps.view, deps.saved
  return settingsPage(page, width, height, deps, function(b)
    local resource, cast = view.resourceBar(b.preview), view.castBar(b.preview)

    b.heading("Adrenaline bar")
    for _, marker in ipairs({
      { id = "threshold", label = "Threshold marker" },
      { id = "ultimate", label = "Ultimate marker" },
    }) do
      b.number(marker.label, 0, 100, function()
        return saved.markers()[marker.id]
      end, function(n)
        if n == saved.markers()[marker.id] then
          return
        end
        saved.setMarker(marker.id, n)
        b.changed()
      end)
    end
    b.stepper("Bar width", "barWidth", settings.BAR_WIDTH.min, settings.BAR_WIDTH.max)
    b.stepper("Bar height", "barHeight", settings.BAR_HEIGHT.min, settings.BAR_HEIGHT.max)
    b.choices("Spenders", style.SPENDER_PLACES, "spenders", 150)

    b.heading("Cast bar")
    b.choices("Width from", WIDTH_FROM, "castMatchWidth", 160)
    local widthRow = b.stepper("Width", "castWidth", settings.CAST_WIDTH.min, settings.CAST_WIDTH.max)
    b.stepper("Height", "castHeight", settings.CAST_HEIGHT.min, settings.CAST_HEIGHT.max)
    local function presetRgb(presetID)
      if presetID == "ability" then
        return style.STYLE_COLOURS[deps.tracker.style()] or style.CAST_COLOUR
      end
      return style.find(style.CAST_PRESETS, presetID).rgb
    end
    b.colour("Colour", "castColour", style.CAST_PRESETS, presetRgb, function(look)
      return look.castColour or presetRgb("ability")
    end)
    local fontChoices = { MATCH_HUD }
    for _, family in ipairs(style.FAMILIES) do
      fontChoices[#fontChoices + 1] = family
    end
    local fonts = b.choices("Font", fontChoices, "castFont", 104)
    for _, family in ipairs(style.FAMILIES) do
      set(fonts[family.id].label, "font", id.Font[family.sizes[13]])
    end
    local low, high = style.ROLES.body + settings.TEXT_STEP_MIN, style.ROLES.body + settings.TEXT_STEP_MAX
    local size = b.number("Text size", low, high, function(appearance)
      return appearance.castTextSize == "hud" and style.ROLES.body + appearance.textStep or appearance.castTextSize
    end, function(n)
      if n ~= saved.appearance().castTextSize then
        b.choose("castTextSize", n)
      end
    end)
    b.options(size, b.rowRight - 132, { MATCH_HUD }, "castTextSize", 104)

    return function(look, appearance)
      widthRow.fade(appearance.castMatchWidth)
      size.fade(appearance.castTextSize == "hud")
      view.setLook({ resource, cast }, look)
      resource.update(frames.resource(SAMPLE_ADRENALINE, saved.markers()))
      cast.update(SAMPLE_CAST)
      draw.pos(resource.layer, PREVIEW_X, PREVIEW_Y - resource.bounds.y)
      draw.pos(cast.layer, PREVIEW_X, PREVIEW_Y + resource.bounds.h + PREVIEW_GAP)
    end
  end)
end

return appearancepage
