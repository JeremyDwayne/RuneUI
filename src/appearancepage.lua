-- The options window's Appearance page: a preview strip of HUD elements, drawn by src/view from sample models
-- over a Dark, Light or Game backdrop, fixed above the Text, Unit frames and Game interfaces settings. The
-- settings scroll by pixels inside a clipping layer, moved by the wheel and a scrollbar. Rows wholly out of view
-- hide, and a click lands only where its row shows. Every change saves, then redraws the preview and the HUD.
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
  { id = "dark", label = "Dark", rgb = 0x15120f }, { id = "light", label = "Light", rgb = 0xd8c6da },
  { id = "game", label = "Game" },
}
local ROW_H, HEADING_H, END_SPACE, MARGIN = 50, 40, 32, 16
local SCROLLBAR_W, WHEEL_STEP = 10, 40
local OPTION_H = 28

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
local SAMPLE_PLAYER = { available = true, name = "Player", lifepoints = 12242, lifepointsLabel = "12,242/15,695",
  prayerValue = 640, prayerLabel = "64/99" }
local SAMPLE_TARGET = { target = 1, name = "Rasial", lifepointsLabel = "58,000", healthPercent = 58 }
local TILE_SIZE, PREVIEW_X, PREVIEW_Y, PREVIEW_GAP = 36, 20, 14, 6

local function labelled(list, format)
  local out = {}
  for i, value in ipairs(list) do out[i] = { id = value, label = format(value) } end
  return out
end

local TEXTURES = { { id = "flat", label = "Flat" }, { id = "vertical", label = "Vertical" },
  { id = "horizontal", label = "Horizontal" } }
local SHOW_HIDE = { { id = false, label = "Show" }, { id = true, label = "Hide" } }
local IDLE_ALPHAS = labelled(settings.IDLE_ALPHAS, function(percent) return percent .. "%" end)

-- page: the options window's page layer, width by height. deps: { saved = src/settings, view = src/view,
-- tooltip = view.tooltip, auraInfo(sprite), tracker = src/cooldowns tracker for the equipped style, refresh()
-- redrawing the HUD }. Returns { open, choiceRow }: open redraws the page from settings, and choiceRow(parent,
-- x, y, w, label, choices, field, optionW) builds a row of option buttons on another page, such as the Buffs
-- page's Display tab.
function appearancepage.create(page, width, height, deps)
  local saved, view = deps.saved, deps.view
  local redraw

  -- Option rows -------------------------------------------------------------------------------------------

  -- Every choice row, each { choices = { [id] = draw.option }, field }, and every stepper's redraw.
  local choiceRows, steppers = {}, {}

  local function showChoices()
    local appearance = saved.appearance()
    for _, row in ipairs(choiceRows) do
      for value, option in pairs(row.choices) do draw.showOption(option, value == appearance[row.field]) end
    end
    for _, show in ipairs(steppers) do show(appearance) end
  end

  local function choose(field, value)
    saved.setAppearance(field, value)
    redraw()
    deps.refresh()
  end

  -- A row's background, which takes clicks, and its label on parent at x, y, w wide. Returns the background.
  local function rowBox(parent, x, y, w, label, shade)
    local bg = hitArea(rect(parent, shade and COLOURS.rowAlt or COLOURS.row, x, y, w, ROW_H))
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
        if allowed == nil or allowed(by + cy) then choose(field, choice.id) end
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
  local tiles = view.cooldownGroup(preview, deps.tooltip)
  tiles.configure({ size = TILE_SIZE, perRow = #SAMPLE_TILES, grow = "down" })
  local aura = view.auraRow(preview, view.AURA_STYLES.combatBuffs, deps.tooltip, deps.auraInfo)
  local player, target = view.playerFrame(preview), view.targetFrame(preview)
  local previewElements = { tiles, aura, player, target }
  rect(page, COLOURS.border, 0, STRIP_H, width, 1)
  local backdropChoice = "light"
  local backdropOptions = {}

  local function showBackdrop()
    local chosen = style.find(BACKDROPS, backdropChoice)
    set(backdrop, "alpha", chosen.rgb and 1 or 0)
    if chosen.rgb then set(backdrop, "rgb", chosen.rgb) end
    for id_, option in pairs(backdropOptions) do draw.showOption(option, id_ == backdropChoice) end
  end

  for i, entry in ipairs(BACKDROPS) do
    backdropOptions[entry.id] = draw.option(page, entry.label, width - 70, 8 + (i - 1) * 26, 62, 22, function()
      backdropChoice = entry.id
      showBackdrop()
    end)
  end

  local function drawPreview(appearance)
    view.setLook(previewElements, style.look(appearance, deps.tracker.style()))
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
  -- Rows by top: { layer, y, h }, the content's height and how far it is scrolled.
  local rows, contentH, scroll = {}, 0, 0

  local function maxScroll() return math.max(0, contentH - viewH) end

  local function thumbBox()
    local h = math.max(24, viewH * math.min(1, viewH / contentH))
    local max = maxScroll()
    return max == 0 and 0 or math.floor((viewH - h) * scroll / max + 0.5), math.floor(h)
  end

  local function scrollTo(y)
    scroll = math.max(0, math.min(maxScroll(), y))
    draw.pos(content, 0, -scroll)
    for _, row in ipairs(rows) do set(row.layer, "hidden", row.y + row.h <= scroll or row.y >= scroll + viewH) end
    local ty, th = thumbBox()
    draw.pos(thumb, width - SCROLLBAR_W - 3, ty)
    draw.size(thumb, SCROLLBAR_W - 2, th)
    set(thumb, "hidden", maxScroll() == 0)
  end

  local function wheel(c)
    on(c, "ONSCROLLWHEEL", function(_, delta) scrollTo(scroll - delta * WHEEL_STEP) end)
  end
  wheel(viewportBg)
  wheel(track)
  on(track, "ONCLICK", function(_, _, y)
    local ty, th = thumbBox()
    if y < ty then scrollTo(scroll - viewH) elseif y > ty + th then scrollTo(scroll + viewH) end
  end)

  -- A layer in the content at its current end, h tall, which hides once scrolled wholly out of view.
  local function addRow(h)
    local row = { layer = ui.Layer.new(content), y = contentH, h = h }
    draw.pos(row.layer, 0, row.y)
    draw.size(row.layer, width, h)
    rows[#rows + 1] = row
    contentH = contentH + h
    return row
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

  -- A settings row with its label; its background takes the wheel.
  local function settingRow(label)
    local row = addRow(ROW_H)
    wheel(rowBox(row.layer, MARGIN, 0, rowW, label, shade))
    shade = not shade
    return row
  end

  local function scrolledChoices(label, choices, field, optionW)
    local row = settingRow(label)
    local buttons = options(row.layer, rowRight, 0, choices, field, optionW, function(y) return shows(row, y) end)
    for _, option in pairs(buttons) do wheel(option.bg) end
    return buttons
  end

  -- A - value + stepper moving field by step from low to high, showing format(value).
  local function stepperRow(label, field, step, low, high, format)
    local row = settingRow(label)
    local by = (ROW_H - OPTION_H) // 2
    local value = text(row.layer, FONTS.body, ui.AlignMode.CENTRE, rowRight - 92, 0, 64, ROW_H)
    local function move(delta)
      return function(_, y)
        if not shows(row, by + y) then return end
        local next = saved.appearance()[field] + delta
        if next >= low and next <= high then choose(field, next) end
      end
    end
    wheel(draw.button(row.layer, "-", rowRight - 124, by, 28, OPTION_H, "dark", move(-step)).bg)
    wheel(draw.button(row.layer, "+", rowRight - 28, by, 28, OPTION_H, "dark", move(step)).bg)
    steppers[#steppers + 1] = function(appearance) set(value, "content", format(appearance[field])) end
  end

  heading("Text")
  local fonts = scrolledChoices("Font", style.FAMILIES, "font", 112)
  for _, family in ipairs(style.FAMILIES) do set(fonts[family.id].label, "font", id.Font[family.sizes[13]]) end
  stepperRow("Text size", "textStep", 1, settings.TEXT_STEP_MIN, settings.TEXT_STEP_MAX,
    function(step) return (style.ROLES.body + step) .. " pt" end)
  scrolledChoices("Text edge", style.EDGES, "edge", 124)
  scrolledChoices("Text colour", style.TEXT_COLOURS, "textColour", 112)

  heading("Unit frames")
  scrolledChoices("Bar texture", TEXTURES, "texture", 112)
  scrolledChoices("Frame border", style.BORDERS, "border", 112)
  scrolledChoices("Lifepoints text", frames.LIFEPOINTS, "lifepoints", 118)
  local px = function(n) return n .. " px" end
  stepperRow("Frame width", "frameWidth", settings.FRAME_WIDTH.step, settings.FRAME_WIDTH.min,
    settings.FRAME_WIDTH.max, px)
  stepperRow("Frame height", "frameHeight", settings.FRAME_HEIGHT.step, settings.FRAME_HEIGHT.min,
    settings.FRAME_HEIGHT.max, px)
  scrolledChoices("Out of combat", IDLE_ALPHAS, "idleAlpha", 80)

  heading("Game interfaces")
  scrolledChoices("Default target panel", SHOW_HIDE, "hideTargetPanel", 90)
  scrolledChoices("Game cast bar", SHOW_HIDE, "hideCastBar", 90)
  contentH = contentH + END_SPACE
  draw.size(content, width, contentH)

  function redraw()
    drawPreview(saved.appearance())
    showChoices()
  end

  return {
    open = function()
      redraw()
      showBackdrop()
      scrollTo(scroll)
    end,
    choiceRow = choiceRow,
    showChoices = showChoices,
  }
end

return appearancepage
