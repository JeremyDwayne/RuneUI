local fake = require("spec/support/fake_ui")
local appearancepage = require("src/appearancepage")
local cooldowns = require("src/cooldowns")
local settings = require("src/settings")
local style = require("src/style")
local view = require("src/view")

local function fakeStore()
  local data = {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end }
end

-- An open Appearance page on a 698 by 562 page layer. Returns the page, its settings and a count of HUD refreshes.
local function open()
  local root = fake.component()
  local saved = settings.load(fakeStore())
  local refreshed = { count = 0 }
  local page = appearancepage.create(root, 698, 562, {
    saved = saved, view = view, tooltip = view.tooltip(root), auraInfo = function() end,
    tracker = cooldowns.tracker(), refresh = function() refreshed.count = refreshed.count + 1 end,
  })
  page.open()
  return page, saved, refreshed
end

local function label(content)
  return fake.find(function(_, d) return d.content == content end)
end

-- An open Bars page on a 698 by 562 page layer. Returns its settings.
local function openBars()
  local root = fake.component()
  local saved = settings.load(fakeStore())
  local page = appearancepage.bars(root, 698, 562, {
    saved = saved, view = view, tooltip = view.tooltip(root), auraInfo = function() end,
    tracker = cooldowns.tracker(), refresh = function() end,
  })
  page.open()
  return saved
end

-- The player colour's hex field, the first field showing a #RRGGBB code.
local function hexField()
  return fake.find(function(c, d)
    return fake.hasHook(c, "ONCONTENTCHANGED") and type(d.content) == "string" and d.content:sub(1, 1) == "#"
  end)
end

-- The settings' viewport, content layer and the row holding the label reading content, shown or not.
local function scrollParts(content)
  for _, c in ipairs(fake.created) do
    if c.content == content then
      local row = c.parent
      return row.parent.parent, row.parent, row
    end
  end
end

-- Turns the wheel over the viewport by delta, times times.
local function wheel(delta, times)
  local viewport = scrollParts("Font")
  local bg = fake.find(function(c, d) return d.parent == viewport and fake.hasHook(c, "ONSCROLLWHEEL") end)
  for _ = 1, times do fake.hook(bg, "ONSCROLLWHEEL", delta) end
end

-- The option button's hit area under the label reading content.
local function optionHit(content)
  local t = label(content)
  return fake.find(function(c, d)
    return c ~= t and d.parent == t.parent and fake.hasHook(c, "ONCLICK") and d.x == t.x and d.y == t.y
  end)
end

describe("appearance page", function()
  before_each(fake.reset)

  it("saves a choice and redraws the preview and the HUD", function()
    local _, saved, refreshed = open()
    fake.press("Outline")
    assert.are.equal("outline", saved.appearance().edge)
    assert.are.equal(1, refreshed.count)
    local copies = 0
    for _, c in ipairs(fake.created) do
      if c.content == "Player" and fake.shown(c) then copies = copies + 1 end
    end
    assert.are.equal(5, copies)
    fake.press("+")
    assert.are.equal(1, saved.appearance().textStep)
    assert.is_not_nil(label("14"))
  end)

  it("scrolls by the wheel and stops with 32 px below the last row", function()
    open()
    local viewport, content, last = scrollParts("Game cast bar")
    wheel(-1, 200)
    assert.are.equal(viewport.height - 32, last.y + last.height + content.y)
    wheel(1, 200)
    assert.are.equal(0, content.y)
  end)

  it("scrolls by dragging the scrollbar's thumb, in proportion to its travel", function()
    local page = open()
    local viewport, content = scrollParts("Game cast bar")
    local grip = fake.find(function(c, d)
      return d.parent ~= viewport and d.alpha == 0 and fake.hasHook(c, "ONRELEASE")
    end)
    fake.mouse.x, fake.mouse.y = 690, 200
    fake.hook(grip, "ONCLICK", 2, 2)
    fake.mouse.y = 260
    page.follow()
    local moved = -content.y
    assert.is_true(moved > 60)
    fake.writes = 0
    page.follow()
    assert.are.equal(0, fake.writes)
    fake.mouse.y = 2000
    page.follow()
    fake.hook(grip, "ONRELEASE")
    local _, _, last = scrollParts("Game cast bar")
    assert.are.equal(viewport.height - 32, last.y + last.height + content.y)
    fake.writes, fake.mouse.y = 0, 100
    page.follow()
    assert.are.equal(0, fake.writes)
  end)

  it("takes no click on a row scrolled out of view or on its clipped part", function()
    local _, saved = open()
    wheel(-1, 10)
    fake.hook(optionHit("Noto Sans"), "ONCLICK", 4, 2)
    assert.are.equal("museo", saved.appearance().font)
    wheel(-1, 100)
    assert.is_nil(label("Noto Sans"))
    wheel(1, 200)
    fake.press("Noto Sans")
    assert.are.equal("noto", saved.appearance().font)
  end)

  it("saves a typed number once it is in range, and on Enter saves it clamped and shows what it saved", function()
    local _, saved = open()
    local field = fake.find(function(c, d) return fake.hasHook(c, "ONCONTENTCHANGED") and d.content == "13" end)
    -- The client holds the typed text in the field before it reports it.
    local function type_(reason, contents)
      field.content = contents
      fake.hook(field, "ONCONTENTCHANGED", ui.InputFieldActionResult[reason], contents)
    end
    type_("CONTENT_CHANGE", "1")
    assert.are.equal(0, saved.appearance().textStep)
    type_("CONTENT_CHANGE", "16")
    assert.are.equal(3, saved.appearance().textStep)
    type_("SUBMIT", "40")
    assert.are.same({ 6, "19" }, { saved.appearance().textStep, field.content })
    type_("SUBMIT", "big")
    assert.are.same({ 6, "19" }, { saved.appearance().textStep, field.content })
  end)

  -- A swatch's name draws over four outline copies, so its label is the fifth shown text reading it.
  local SWATCH_LABEL = 5

  it("saves a preset colour and shows its hex", function()
    local _, saved = open()
    fake.press("Game green", SWATCH_LABEL)
    assert.are.equal("gameGreen", saved.appearance().playerColour)
    local field = hexField()
    assert.are.equal("#2B8A1E", field.content)
  end)

  it("saves a valid typed hex colour and ignores an invalid one", function()
    local _, saved, refreshed = open()
    local field = hexField()
    fake.hook(field, "ONCONTENTCHANGED", 0, "#12345")
    fake.hook(field, "ONCONTENTCHANGED", 0, "#12345G")
    assert.are.same({ "runeui", 0 }, { saved.appearance().playerColour, refreshed.count })
    fake.hook(field, "ONCONTENTCHANGED", 0, "#123456")
    assert.are.same({ 0x123456, 1 }, { saved.appearance().playerColour, refreshed.count })
  end)

  it("saves a colour picked on the shade square Custom opens, still scrolling 32 px past the last row", function()
    local _, saved = open()
    fake.press("Custom")
    local square = fake.find(function(c, d)
      return d.width == 180 and d.height == 110 and fake.hasHook(c, "ONCLICK")
    end)
    fake.hook(square, "ONCLICK", 180, 0)
    local hue = style.hsv(style.FRAME_COLOURS.player)
    assert.are.equal(style.rgb(hue, 1, 1), saved.appearance().playerColour)
    local viewport, content, last = scrollParts("Game cast bar")
    wheel(-1, 200)
    assert.are.equal(viewport.height - 32, last.y + last.height + content.y)
  end)

  it("lets the cast bar take the adrenaline bar's width, and its own text size until Match HUD", function()
    local saved = openBars()
    wheel(-1, 200)
    fake.press("Same as adrenaline")
    assert.is_true(saved.appearance().castMatchWidth)
    local size = fake.find(function(c, d) return fake.hasHook(c, "ONCONTENTCHANGED") and d.content == "13" end)
    size.content = "16"
    fake.hook(size, "ONCONTENTCHANGED", ui.InputFieldActionResult.SUBMIT, "16")
    assert.are.equal(16, saved.appearance().castTextSize)
    fake.press("Match HUD", 2)
    assert.are.same({ "hud", "13" }, { saved.appearance().castTextSize, size.content })
  end)
end)
