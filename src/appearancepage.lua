-- The options window's Appearance and Bars pages. Each has a preview strip of HUD elements, drawn by src/view
-- from sample models over a Dark or Light backdrop, fixed above its settings: Text, Unit frames and Game
-- interfaces on Appearance, the adrenaline bar and the cast bar on Bars. The settings scroll by pixels inside a
-- clipping layer, moved by the wheel and a scrollbar. Rows wholly out of view hide, and a click lands only where
-- its row shows. Every change saves, then redraws the preview and the HUD.
local colourpicker = require("src/colourpicker")
local controls = require("src/controls")
local draw = require("src/draw")
local frames = require("src/frames")
local scrollbar = require("src/scrollbar")
local savedappearance = require("src/savedappearance")
local style = require("src/style")

local appearancepage = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local hitArea = draw.hitArea
local on = draw.on
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW

local STRIP_H = 168
-- Preview backdrops: black or light lilac.
local BACKDROPS = {
  { id = "dark", label = "Dark", rgb = 0x15120f },
  { id = "light", label = "Light", rgb = 0xd8c6da },
}
local ROW_H = 50
local HEADING_H = 40
local END_SPACE = 32
local MARGIN = 16
local OPTION_H = 28
local COLUMNS_H = 30
-- The Bars page's action bar table: the Fade, Opacity and Show on hover columns' widths, right to left from
-- the row's right edge, and each toggle's width.
local HOVER_COL = 120
local OPACITY_COL = 136
local FADE_COL = 96
local TOGGLE_W = 72
local ACTION_BAR_NAMES = { "Main bar", "Action bar 2", "Action bar 3", "Action bar 4", "Action bar 5" }
-- Colour rows: two lines of swatches and the hex field, and a src/colourpicker under them while Custom is open.
local SWATCH_W = 84
local SWATCH_GAP = 4
local HEX_W = 86
local HEX_H = 24
local COLOUR_ROW_H = 10 + 2 * OPTION_H + 8 + 10
local PICKER_SPACE = 12

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
local TILE_SIZE = 36
local PREVIEW_X = 20
local PREVIEW_Y = 14
local PREVIEW_GAP = 6
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

  -- Every choice row, each { choices = { [id] = controls.option }, field }, and every stepper's redraw.
  local choiceRows = {}
  local steppers = {}

  local function showChoices()
    local appearance = saved.appearance()
    for _, row in ipairs(choiceRows) do
      for value, option in pairs(row.choices) do
        controls.showOption(option, value == appearance[row.field])
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
      row.choices[choice.id] = controls.option(parent, choice.label, x, by, optionW, OPTION_H, function(_, cy)
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
  local backdropChoice = "dark"
  local backdropOptions = {}

  local function showBackdrop()
    set(backdrop, "rgb", style.find(BACKDROPS, backdropChoice).rgb)
    for id_, option in pairs(backdropOptions) do
      controls.showOption(option, id_ == backdropChoice)
    end
  end

  for i, entry in ipairs(BACKDROPS) do
    backdropOptions[entry.id] = controls.option(page, entry.label, width - 70, 8 + (i - 1) * 26, 62, 22, function()
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
  local rowW = width - 2 * MARGIN - scrollbar.WIDTH - 4
  local rowRight = MARGIN + rowW - 12
  -- Rows from the top: { layer, y, h }, the content's height and how far it is scrolled.
  local rows = {}
  local contentH = 0
  local scroll = 0
  local bar

  local function scrollTo(y)
    scroll = bar.set(y, contentH)
    draw.pos(content, 0, -scroll)
    for _, row in ipairs(rows) do
      set(row.layer, "hidden", row.y + row.h <= scroll or row.y >= scroll + viewH)
    end
  end

  bar = scrollbar.create(viewport, width - scrollbar.WIDTH - 4, 0, viewH, scrollTo)
  local wheel = bar.wheel
  wheel(viewportBg)

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

  -- A controls.stepper at x on row, from low to high in steps of step: value(appearance) gives the number shown and
  -- save(n) takes a new one. Returns its fade(faded), which dims the stepper while the setting has no effect.
  local function stepper(row, x, low, high, step, value, save)
    local s = controls.stepper(row.layer, x, (ROW_H - OPTION_H) // 2, low, high, step, save, function(y)
      return shows(row, y)
    end)
    wheel(s.buttons[1].bg)
    wheel(s.buttons[2].bg)
    steppers[#steppers + 1] = function(appearance)
      s.show(value(appearance))
    end
    return s.fade
  end

  -- A settings row with a stepper by 1 at its right, as stepper takes. Returns the row, whose fade(faded) dims
  -- the stepper.
  local function numberRow(label, low, high, value, save)
    local row = settingRow(label)
    row.fade = stepper(row, rowRight - controls.STEPPER_W, low, high, 1, value, save)
    return row
  end

  -- An On or Off button w wide at x on row, flipping the boolean appearance field. Returns its fade(faded).
  local function toggle(row, x, w, field)
    local by = (ROW_H - OPTION_H) // 2
    local o = controls.option(row.layer, "Off", x, by, w, OPTION_H, function(_, y)
      if shows(row, by + y) then
        choose(field, not saved.appearance()[field])
      end
    end)
    wheel(o.bg)
    steppers[#steppers + 1] = function(appearance)
      controls.showOption(o, appearance[field])
      set(o.label, "content", appearance[field] and "On" or "Off")
    end
    return function(faded)
      local alpha = faded and controls.FADED or 1
      for _, part in ipairs({ o.ring, o.bg, o.face, o.label }) do
        set(part, "alpha", alpha)
      end
    end
  end

  -- A row of column labels, each { label, x, w } centred over its column, under the first, which sits left.
  local function columns(heads)
    local row = addRow(COLUMNS_H)
    for i, head in ipairs(heads) do
      local align = i == 1 and ui.AlignMode.TOPLEFT or ui.AlignMode.CENTRE
      local t = text(row.layer, FONTS.small, align, head[2], 0, head[3], COLUMNS_H)
      set(t, "content", head[1])
      set(t, "rgb", COLOURS.mutedText)
    end
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
    local swatches = {}
    local perLine = 5
    for i, preset in ipairs(presets) do
      local line = (i - 1) // perLine + 1
      local slot = (i - 1) % perLine
      local x = rowRight - perLine * (SWATCH_W + SWATCH_GAP) + SWATCH_GAP + slot * (SWATCH_W + SWATCH_GAP)
      swatches[preset.id] = swatch(row.layer, x, lineY[line], preset.label, function(y)
        if allowed(y) then
          choose(field, preset.id)
        end
      end)
    end
    local customX = rowRight - 2 * (SWATCH_W + SWATCH_GAP) + SWATCH_GAP
    local hexX = rowRight - HEX_W
    local hex = controls.inputField(row.layer, hexX, lineY[2] + (OPTION_H - HEX_H) // 2, HEX_W, HEX_H, 7)
    -- The field also reports its contents on Enter, Esc and focus loss, so an unchanged colour is skipped.
    on(hex, "ONCONTENTCHANGED", function(_, _, contents)
      local rgb = style.parseHex(contents)
      if rgb ~= nil and rgb ~= saved.appearance()[field] then
        choose(field, rgb)
      end
    end)

    local open = false
    local picker = colourpicker.create(row.layer, rowRight - colourpicker.W, COLOUR_ROW_H, {
      allowed = allowed,
      wheel = wheel,
      choose = function(rgb)
        choose(field, rgb)
      end,
    })

    local custom = controls.option(row.layer, "Custom", customX, lineY[2], SWATCH_W, OPTION_H, function(_, y)
      if not allowed(lineY[2] + y) then
        return
      end
      open = not open
      if open then
        picker.show(colourRows[field].rgb)
      else
        picker.hide()
      end
      row.h = COLOUR_ROW_H + (open and colourpicker.H + PICKER_SPACE or 0)
      draw.size(row.bg, rowW, row.h)
      relayout()
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
        controls.showOption(custom, type(chosen) == "number")
        if style.parseHex(hex.content) ~= rgb then
          hex.content = style.formatHex(rgb)
        end
        if open then
          picker.show(rgb)
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
    row = settingRow,
    stepperAt = stepper,
    toggle = toggle,
    columns = columns,
    colour = colourRow,
    choose = choose,
    -- Redraws the page and the HUD after a change saved outside the appearance, such as a marker.
    changed = function()
      redraw()
      deps.refresh()
    end,
  })

  bar.grip(page, width - scrollbar.WIDTH - 4, STRIP_H + 1)
  relayout()

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
    follow = bar.follow,
    cancel = bar.cancel,
  }
end

-- The Appearance page; see settingsPage.
function appearancepage.create(page, width, height, deps)
  local view = deps.view
  return settingsPage(page, width, height, deps, function(b)
    local tiles = view.cooldownGroup(b.preview, deps.tooltip)
    tiles.configure({ size = TILE_SIZE, perRow = #SAMPLE_TILES, grow = "down" })
    local aura = view.auraRow(b.preview, view.AURA_STYLES.combatBuffs, deps.tooltip, deps.auraInfo)
    local player = view.playerFrame(b.preview)
    local target = view.targetFrame(b.preview)
    local elements = { tiles, aura, player, target }

    b.heading("Text")
    local fonts = b.choices("Font", style.FAMILIES, "font", 112)
    for _, family in ipairs(style.FAMILIES) do
      set(fonts[family.id].label, "font", id.Font[family.sizes[13]])
    end
    b.number(
      "Text size",
      style.ROLES.body + savedappearance.TEXT_STEP_MIN,
      style.ROLES.body + savedappearance.TEXT_STEP_MAX,
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
    b.stepper("Frame width", "frameWidth", savedappearance.FRAME_WIDTH.min, savedappearance.FRAME_WIDTH.max)
    b.stepper("Frame height", "frameHeight", savedappearance.FRAME_HEIGHT.min, savedappearance.FRAME_HEIGHT.max)

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

-- The Bars page: the adrenaline bar's markers and size, where the spender rows sit, the cast bar's width,
-- height, colour, font and text size, and whether each game action bar fades, to what opacity, and shows at full
-- on hover, with the main bar's stats shown or hidden; see settingsPage.
function appearancepage.bars(page, width, height, deps)
  local view = deps.view
  local saved = deps.saved
  return settingsPage(page, width, height, deps, function(b)
    local resource = view.resourceBar(b.preview)
    local cast = view.castBar(b.preview)

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
    b.stepper("Bar width", "barWidth", savedappearance.BAR_WIDTH.min, savedappearance.BAR_WIDTH.max)
    b.stepper("Bar height", "barHeight", savedappearance.BAR_HEIGHT.min, savedappearance.BAR_HEIGHT.max)
    b.choices("Spenders", style.SPENDER_PLACES, "spenders", 150)

    b.heading("Cast bar")
    b.choices("Width from", WIDTH_FROM, "castMatchWidth", 160)
    local widthRow = b.stepper("Width", "castWidth", savedappearance.CAST_WIDTH.min, savedappearance.CAST_WIDTH.max)
    b.stepper("Height", "castHeight", savedappearance.CAST_HEIGHT.min, savedappearance.CAST_HEIGHT.max)
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
    local low = style.ROLES.body + savedappearance.TEXT_STEP_MIN
    local high = style.ROLES.body + savedappearance.TEXT_STEP_MAX
    local size = b.number("Text size", low, high, function(appearance)
      return appearance.castTextSize == "hud" and style.ROLES.body + appearance.textStep or appearance.castTextSize
    end, function(n)
      if n ~= saved.appearance().castTextSize then
        b.choose("castTextSize", n)
      end
    end)
    b.options(size, b.rowRight - 132, { MATCH_HUD }, "castTextSize", 104)

    b.heading("Action bars")
    local right = b.rowRight
    local hoverX = right - HOVER_COL
    local opacityX = hoverX - OPACITY_COL
    local fadeX = opacityX - FADE_COL
    b.columns({
      { "Bar", 32, 200 },
      { "Fade", fadeX, FADE_COL },
      { "Opacity %", opacityX, OPACITY_COL },
      { "Show on hover", hoverX, HOVER_COL },
    })
    -- Each bar's fade(faded) for its opacity stepper and hover toggle, dimmed while the bar is not faded.
    local barFades = {}
    for bar, name in ipairs(ACTION_BAR_NAMES) do
      local row = b.row(name)
      local opacity = "barOpacity" .. bar
      b.toggle(row, fadeX + (FADE_COL - TOGGLE_W) // 2, TOGGLE_W, "fadeBar" .. bar)
      local step = savedappearance.OPACITY_STEP
      local fadeStepper = b.stepperAt(row, opacityX + (OPACITY_COL - controls.STEPPER_W) // 2, 0, 100, step, function(a)
        return a[opacity]
      end, function(n)
        if n ~= saved.appearance()[opacity] then
          b.choose(opacity, n)
        end
      end)
      local fadeHover = b.toggle(row, hoverX + (HOVER_COL - TOGGLE_W) // 2, TOGGLE_W, "hoverBar" .. bar)
      barFades[bar] = function(faded)
        fadeStepper(faded)
        fadeHover(faded)
      end
    end
    b.toggle(b.row("Hover shows all bars"), hoverX + (HOVER_COL - TOGGLE_W) // 2, TOGGLE_W, "hoverAllBars")

    return function(look, appearance)
      widthRow.fade(appearance.castMatchWidth)
      size.fade(appearance.castTextSize == "hud")
      for bar, fade in ipairs(barFades) do
        fade(not appearance["fadeBar" .. bar])
      end
      view.setLook({ resource, cast }, look)
      resource.update(frames.resource(SAMPLE_ADRENALINE, saved.markers()))
      cast.update(SAMPLE_CAST)
      draw.pos(resource.layer, PREVIEW_X, PREVIEW_Y - resource.bounds.y)
      draw.pos(cast.layer, PREVIEW_X, PREVIEW_Y + resource.bounds.h + PREVIEW_GAP)
    end
  end)
end

return appearancepage
