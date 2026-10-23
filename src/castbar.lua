-- The cast bar: the channelled ability's icon, name and time left over a fill that moves smoothly between
-- server ticks, with a spark at its edge and a mark at each hit.
local castbar = {}

local draw = require("src/draw")
local hudparts = require("src/hudparts")
local style = require("src/style")
local set = draw.set
local pos = draw.pos
local rect = draw.rect
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS
local styleText = hudparts.styleText
local DEFAULT_LOOK = hudparts.DEFAULT_LOOK
local barMark = hudparts.barMark
local shadeMark = hudparts.shadeMark
-- Hit marks built for the cast bar, more than any channel deals.
local MAX_HITS = 12
local NO_HITS = {}

-- Ticks left as the game's cast bar writes them: "4.2s", "3s".
local function castSeconds(ticks)
  local tenths = ticks * 6
  if tenths % 10 == 0 then
    return (tenths // 10) .. "s"
  end
  return string.format("%d.%ds", tenths // 10, tenths % 10)
end

-- A cancelled channel shows "Cancelled" for CANCEL_HOLD seconds, then the bar fades out over CANCEL_FADE seconds
-- in CANCEL_STEPS alpha steps, from 0.8 down to 0.
local CANCEL_HOLD = 0.6
local CANCEL_FADE = 0.4
local CANCEL_STEPS = 5

-- Fill colour by the channelled ability's src/cooldowns combat style, for Ability style. A channel with none keeps
-- the RuneUI fill.
local CAST_COLOURS = style.STYLE_COLOURS
-- The time label's width and its gap from the bar's right end.
local CAST_TIME_W = 72
local CAST_TIME_GAP = 6

-- The spark at the fill's edge: a 2px white core with a glow of SPARK_GLOW 1px white strips behind it, their alpha
-- rising evenly to GLOW_PEAK by the core, times the glow level. The level sits at GLOW_BASE and flashes on each
-- server tick, stepping down through FLASH_LEVELS over FLASH seconds, as the game's spark glow does.
local SPARK_GLOW = 12
local SPARK_CORE = 2
local GLOW_PEAK = 0.9
local GLOW_BASE = 0.5
local FLASH = 0.2
local FLASH_LEVELS = { 1, 0.8, 0.65 }

-- look.castWidth by look.castHeight: the channelled ability's icon, its name, and its time left as "1.2s" over a
-- fill of the time spent in look.castColour, or its combat style's colour for Ability style, with a spark at the
-- fill's edge and a bar mark at each hit that lands inside the bar rather than at its ends. A cancelled channel
-- shows "Cancelled" in place of its time, hides its spark and marks, and fades out, whatever updates arrive
-- meanwhile.
-- update takes a src/channel model, or nil to hide the bar while keeping its bounds, so anchored elements stay
-- put. The time steps with the model's ticks left, as the game's label does, and each new count sets the fill to
-- that tick. step(seconds) moves the fill on smoothly up to the next tick, hides the bar once its last tick runs
-- out, and does nothing between channels.
function castbar.create(root)
  local layer = ui.Layer.new(root)
  local border = rect(layer, COLOURS.border, 0, 0, 0, 0)
  local track = rect(layer, COLOURS.track, 1, 1, 0, 0)
  -- The bar's left edge and width, right of the icon, set by resize.
  local barX = 0
  local barWidth = 0
  local fill = draw.bar(layer, style.CAST_COLOUR, COLOURS.track, 0, 1, 0, 0)
  local marks = {}
  for i = 1, MAX_HITS do
    marks[i] = barMark(layer, 0, 1, 0)
    set(marks[i], "hidden", true)
  end
  local sparkWidth = SPARK_GLOW + SPARK_CORE
  local spark = draw.new(ui.Layer, layer)
  local glow = {}
  for i = 1, SPARK_GLOW do
    glow[i] = rect(spark, COLOURS.highlight, i - 1, 0, 1, 0)
  end
  local core = rect(spark, COLOURS.highlight, sparkWidth - SPARK_CORE, 0, SPARK_CORE, 0)
  -- The glow level shown, and seconds left in a flash.
  local glowLevel = nil
  local flashLeft = 0
  local iconBack = rect(layer, COLOURS.tile, 1, 1, 0, 0)
  local icon = draw.new(ui.Sprite, layer)
  icon:SetPos(1, 1)
  local name = draw.edgedText(layer, FONTS.body, ui.AlignMode.TOPLEFT, 0, 1, 0, 0)
  local time = draw.edgedText(layer, FONTS.body, ui.AlignMode.BOTTOMRIGHT, 0, 1, CAST_TIME_W, 0)
  local bounds = { x = 0, y = 0, w = 0, h = 0 }
  local bar = { layer = layer, bounds = bounds }
  -- The look shown.
  local shown = nil
  -- Every component the cancel fade dims. Marks hide on a cancel, so they are left out.
  local faded = { border, track, iconBack, icon, name, time }
  for _, part in ipairs(fill.parts) do
    faded[#faded + 1] = part
  end
  -- Seconds left showing a cancel, or nil.
  local cancelLeft = nil
  set(layer, "hidden", true)
  -- The shown channel's model and seconds left, nil once it ends, the start of the latest channel shown and the
  -- ticks left its label shows.
  local current = nil
  local left = nil
  local shownStart = nil
  local shownTicks = nil
  -- Seconds into the channel of each shown mark, the start and hit count they were placed for, and how many the
  -- fill has passed.
  local markAt = {}
  local placedFor = nil
  local placedHits = nil
  local placed = 0
  local passedShown = nil

  local function placeMarks(model)
    placedFor = model.start
    placedHits = model.hits and #model.hits
    placed = 0
    passedShown = nil
    for _, at in ipairs(model.hits or NO_HITS) do
      if at > 0 and at < model.duration and placed < MAX_HITS then
        placed = placed + 1
        markAt[placed] = at
        pos(marks[placed], barX + math.floor(barWidth * at / model.duration + 0.5), 1)
      end
    end
    for i, mark in ipairs(marks) do
      set(mark, "hidden", i > placed)
    end
  end

  -- Shades the marks for the seconds spent, only when the fill passes one.
  local function shadeMarks(spent)
    local passed = 0
    for i = 1, placed do
      if markAt[i] <= spent then
        passed = i
      end
    end
    if passed == passedShown then
      return
    end
    passedShown = passed
    for i = 1, placed do
      shadeMark(marks[i], i <= passed)
    end
  end

  local function setGlow(level)
    if level == glowLevel then
      return
    end
    glowLevel = level
    for i, strip in ipairs(glow) do
      set(strip, "alpha", GLOW_PEAK * level * i / SPARK_GLOW)
    end
  end

  -- Puts the spark's core at edge, hiding any part of it left of the fill.
  local function placeSpark(edge)
    local x = edge - sparkWidth
    pos(spark, x, 1)
    for i, strip in ipairs(glow) do
      set(strip, "hidden", x + i - 1 < barX)
    end
    set(core, "hidden", edge - SPARK_CORE < barX)
  end

  -- Fills the bar to the share of the channel spent, moves the spark to its edge and shades the marks it passed.
  local function show(remaining)
    local spent = 1 - remaining / current.duration
    fill.setFill(spent)
    placeSpark(barX + math.floor(barWidth * spent))
    shadeMarks(current.duration - remaining)
  end

  local function setAlpha(alpha)
    for _, part in ipairs(faded) do
      set(part, "alpha", alpha)
    end
  end

  -- Hides the bar and ends its channel.
  local function finish()
    current = nil
    left = nil
    cancelLeft = nil
    set(layer, "hidden", true)
    setAlpha(1)
  end

  local function update(model)
    local cancel = model ~= nil and model.cancelled
    if cancelLeft ~= nil and (model == nil or cancel or model.start == shownStart) then
      return
    end
    if cancel then
      if current ~= nil and model.start == shownStart then
        cancelLeft = CANCEL_HOLD + CANCEL_FADE
        set(time, "content", "Cancelled")
        draw.hideAll(marks, true)
        set(spark, "hidden", true)
      else
        finish()
      end
      return
    end
    if cancelLeft ~= nil then
      finish()
    end
    if model ~= nil and model.start ~= shownStart then
      shownStart = model.start
      left = model.duration
      shownTicks = nil
    end
    if model ~= nil and left ~= nil and model.ticksLeft ~= shownTicks then
      shownTicks = model.ticksLeft
      left = model.ticksLeft * 6 / 10
      flashLeft = FLASH
      set(time, "content", castSeconds(shownTicks))
      setGlow(FLASH_LEVELS[1])
    end
    current = left ~= nil and model or nil
    set(layer, "hidden", current == nil)
    if current == nil then
      left = nil
      return
    end
    set(iconBack, "hidden", model.icon == nil)
    set(icon, "hidden", model.icon == nil)
    if model.icon ~= nil then
      set(icon, "sprite", model.icon)
    end
    set(name, "content", model.name or "")
    fill.setColour(shown.castColour or CAST_COLOURS[model.style] or style.CAST_COLOUR)
    set(spark, "hidden", false)
    if model.start ~= placedFor or (model.hits and #model.hits) ~= placedHits then
      placeMarks(model)
    end
    show(left)
  end

  local function step(seconds)
    if current == nil then
      return
    end
    if cancelLeft ~= nil then
      cancelLeft = cancelLeft - seconds
      if cancelLeft <= 0 then
        finish()
      elseif cancelLeft < CANCEL_FADE then
        setAlpha((math.ceil(cancelLeft / CANCEL_FADE * CANCEL_STEPS) - 1) / CANCEL_STEPS)
      end
      return
    end
    if flashLeft > 0 then
      flashLeft = flashLeft - seconds
      local steps = #FLASH_LEVELS
      setGlow(flashLeft > 0 and FLASH_LEVELS[steps + 1 - math.ceil(flashLeft / FLASH * steps)] or GLOW_BASE)
    end
    left = math.max(left - seconds, (shownTicks - 1) * 6 / 10)
    if left > 0 then
      show(left)
    else
      finish()
    end
  end

  -- Sizes every part for a w by h bar, the icon a square filling its height, and redraws a running channel.
  local function resize(w, h)
    local inner = h - 2
    bar.width = w
    bar.height = h
    bounds.w = w
    bounds.h = h
    barX = inner + 2
    barWidth = w - inner - 3
    draw.size(layer, w, h)
    draw.size(border, w, h)
    draw.size(track, w - 2, inner)
    fill.setBox(barX, 1, barWidth, inner)
    for _, mark in ipairs(marks) do
      draw.size(mark, 1, inner)
    end
    draw.size(spark, sparkWidth, inner)
    for _, strip in ipairs(glow) do
      draw.size(strip, 1, inner)
    end
    draw.size(core, SPARK_CORE, inner)
    draw.size(iconBack, inner, inner)
    draw.size(icon, inner, inner)
    pos(name, barX + 5, 1)
    draw.size(name, math.max(0, w - barX - 5 - CAST_TIME_W), inner)
    pos(time, w - CAST_TIME_W - CAST_TIME_GAP, 1)
    draw.size(time, CAST_TIME_W, inner)
    if current ~= nil and cancelLeft == nil then
      placeMarks(current)
      show(left)
    end
  end

  -- Restyles the bar for a src/style look, returning at once for the look it shows. Returns whether its bounds
  -- changed. Its fills are all dark, so Auto keeps the text light.
  function bar.setLook(look)
    if look == shown then
      return false
    end
    shown = look
    local moved = bounds.w ~= look.castWidth or bounds.h ~= look.castHeight
    if moved then
      resize(look.castWidth, look.castHeight)
    end
    fill.setTexture(look.texture)
    if current ~= nil then
      fill.setColour(look.castColour or CAST_COLOURS[current.style] or style.CAST_COLOUR)
    end
    styleText(name, "cast", look, false)
    styleText(time, "cast", look, false)
    return moved
  end

  bar.update = update
  bar.step = step
  bar.setLook(DEFAULT_LOOK)
  return bar
end

return castbar
