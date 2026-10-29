local fake = require("spec/support/fake_ui")
local appearancepage = require("src/appearancepage")
local cooldowns = require("src/cooldowns")
local settings = require("src/settings")
local style = require("src/style")
local view = require("src/view")

local function fakeStore()
  local data = {}
  return {
    get = function(key)
      return data[key]
    end,
    set = function(key, value)
      data[key] = value
    end,
  }
end

-- An open Appearance page on a 698 by 562 page layer. Returns the page, its settings, a count of HUD refreshes
-- and the number of components the page built.
local function open()
  local root = fake.component()
  local saved = settings.load(fakeStore())
  local refreshed = { count = 0 }
  local tooltip = view.tooltip(root)
  local before = fake.live(root)
  local page = appearancepage.create(root, 698, 562, {
    saved = saved,
    view = view,
    tooltip = tooltip,
    auraInfo = function()
      return {}
    end,
    tracker = cooldowns.tracker(),
    refresh = function()
      refreshed.count = refreshed.count + 1
    end,
  })
  page.open()
  return page, saved, refreshed, fake.live(root) - before
end

local function label(content)
  return fake.find(function(_, d)
    return d.content == content
  end)
end

-- An open Bars page on a 698 by 562 page layer. Returns its settings.
local function openBars()
  local root = fake.component()
  local saved = settings.load(fakeStore())
  local page = appearancepage.bars(root, 698, 562, {
    saved = saved,
    view = view,
    tooltip = view.tooltip(root),
    auraInfo = function()
      return {}
    end,
    tracker = cooldowns.tracker(),
    refresh = function() end,
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

-- Turns the wheel over the viewport by delta, times times. A positive delta scrolls down, as in the game's own
-- lists.
local function wheel(delta, times)
  local viewport = scrollParts("Font")
  local bg = fake.find(function(c, d)
    return d.parent == viewport and fake.hasHook(c, "ONSCROLLWHEEL")
  end)
  for _ = 1, times do
    fake.hook(bg, "ONSCROLLWHEEL", delta)
  end
end

-- The option button's hit area under the label reading content.
local function optionHit(content)
  local t = label(content)
  return fake.find(function(c, d)
    return c ~= t and d.parent == t.parent and fake.hasHook(c, "ONCLICK") and d.x == t.x and d.y == t.y
  end)
end

-- Presses the game button labelled content in the row labelled row.
local function pressInRow(row, content)
  local parent = label(row).parent
  local button = fake.find(function(c, d)
    return d.parent == parent and d.label == content and fake.hasHook(c, "ONBUTTONPRESSED")
  end)
  fake.hook(button, "ONBUTTONPRESSED", 0, 1)
end

-- The nth check box from the left, default the first, in the row labelled row.
local function checkInRow(row, nth)
  local parent = label(row).parent
  local boxes = {}
  for _, c in ipairs(fake.created) do
    if c.parent == parent and c.check then
      boxes[#boxes + 1] = c
    end
  end
  table.sort(boxes, function(a, b)
    return a.x < b.x
  end)
  return boxes[nth or 1]
end

-- The number field in the row labelled row.
local function fieldInRow(row)
  local parent = label(row).parent
  return fake.find(function(c, d)
    return d.parent == parent and fake.hasHook(c, "ONCONTENTCHANGED")
  end)
end

-- The label of the Appearance page's last row.
local LAST_ROW = "Show while you have a target"

describe("appearance page", function()
  before_each(fake.reset)

  it("saves a choice and redraws the preview and the HUD", function()
    local _, saved, refreshed = open()
    fake.press("Outline")
    assert.are.equal("outline", saved.appearance().edge)
    assert.are.equal(1, refreshed.count)
    local copies = 0
    for _, c in ipairs(fake.created) do
      if c.content == "Player" and fake.shown(c) then
        copies = copies + 1
      end
    end
    assert.are.equal(5, copies)
    fake.press("+")
    assert.are.equal(1, saved.appearance().textStep)
    assert.is_not_nil(label("14"))
  end)

  it("scrolls by the wheel and stops with 32 px below the last row", function()
    open()
    local viewport, content, last = scrollParts(LAST_ROW)
    wheel(1, 200)
    assert.are.equal(viewport.height - 32, last.y + last.height + content.y)
    wheel(-1, 200)
    assert.are.equal(0, content.y)
  end)

  it("scrolls 32 px a click on the scrollbar's arrows, within the list", function()
    open()
    local _, content = scrollParts("Font")
    local function arrow(sprite)
      return fake.find(function(c, d)
        return d.sprite == sprite and fake.hasHook(c, "ONCLICK")
      end)
    end
    fake.hook(arrow("SCROLLBAR_V2_0"), "ONCLICK")
    assert.are.equal(0, content.y)
    fake.hook(arrow("SCROLLBAR_V2_1"), "ONCLICK")
    assert.are.equal(-32, content.y)
    fake.hook(arrow("SCROLLBAR_V2_0"), "ONCLICK")
    assert.are.equal(0, content.y)
  end)

  it("scrolls by dragging the scrollbar's thumb, in proportion to its travel", function()
    local page = open()
    local viewport, content = scrollParts(LAST_ROW)
    local grip = fake.find(function(c, d)
      return d.parent ~= viewport and d.alpha == 0 and fake.hasHook(c, "ONRELEASE")
    end)
    fake.mouse.x = 690
    fake.mouse.y = 200
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
    local _, _, last = scrollParts(LAST_ROW)
    assert.are.equal(viewport.height - 32, last.y + last.height + content.y)
    fake.writes = 0
    fake.mouse.y = 100
    page.follow()
    assert.are.equal(0, fake.writes)
  end)

  it("takes no click on a swatch's clipped part, and hides a row scrolled out of view", function()
    local _, saved = open()
    -- Down 296 px, 4 px past the top of the Player colour row's first swatches.
    wheel(1, 37)
    fake.hook(fake.textHit("Game green"), "ONCLICK", 4, 2)
    assert.are.equal("runeui", saved.appearance().playerColour)
    wheel(1, 100)
    assert.is_nil(label("Font"))
    wheel(-1, 200)
    fake.pressText("Game green")
    assert.are.equal("gameGreen", saved.appearance().playerColour)
  end)

  it("blanks a number field whose box crosses the list's edge, since the client draws its text unclipped", function()
    open()
    local _, _, parent = scrollParts("Frame width")
    local field
    for _, c in ipairs(fake.created) do
      if c.parent == parent and fake.hasHook(c, "ONCONTENTCHANGED") then
        field = c
      end
    end
    -- Down 616 px, 5 px past the top of the Frame width field.
    wheel(1, 77)
    assert.are.same({ true, "" }, { fake.shown(field), field.content })
    wheel(-1, 2)
    assert.are.equal("250", field.content)
  end)

  it("scrolls by the wheel over a number field and the hex field", function()
    open()
    local _, content = scrollParts("Font")
    for _, field in ipairs({ fieldInRow("Text size"), hexField() }) do
      local before = content.y
      fake.hook(field, "ONSCROLLWHEEL", 1)
      assert.is_true(content.y < before)
    end
  end)

  it("chooses on a radio group and shows a choice saved elsewhere", function()
    local _, saved = open()
    fake.press("Noto Sans")
    assert.are.equal("noto", saved.appearance().font)
    local fonts = fake.find(function(_, d)
      return d.entries ~= nil and d.entries[1].label == "Museo Sans"
    end)
    saved.setAppearance("font", "cinzel")
    fake.press("Outline")
    assert.are.equal("Cinzel", fake.chosen(fonts))
  end)

  it("saves a typed number once it is in range, and on Enter saves it clamped and shows what it saved", function()
    local _, saved = open()
    local field = fake.find(function(c, d)
      return fake.hasHook(c, "ONCONTENTCHANGED") and d.content == "13"
    end)
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

  it("saves a preset colour and shows its hex", function()
    local _, saved = open()
    fake.pressText("Game green")
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
    local viewport, content, last = scrollParts(LAST_ROW)
    wheel(1, 200)
    assert.are.equal(viewport.height - 32, last.y + last.height + content.y)
  end)

  it("moves the hue mark when a hue is picked for a grey, whose colour the hue does not change", function()
    local _, saved = open()
    fake.press("Custom")
    local square = fake.find(function(c, d)
      return d.width == 180 and d.height == 110 and fake.hasHook(c, "ONCLICK")
    end)
    local strip = fake.find(function(c, d)
      return d.width == 18 and d.height == 110 and fake.hasHook(c, "ONCLICK")
    end)
    local mark = fake.find(function(_, d)
      return d.width == 22 and d.height == 4
    end)
    fake.hook(square, "ONCLICK", 0, 0)
    assert.are.equal(0xffffff, saved.appearance().playerColour)
    fake.hook(strip, "ONCLICK", 0, 0)
    assert.are.equal(strip.y + 108, mark.y)
    fake.hook(square, "ONCLICK", 180, 0)
    assert.are.equal(0xff0000, saved.appearance().playerColour)
  end)

  it("sets how the HUD shows out of combat, dimming the opacity until Fade and the target choice under Show", function()
    local _, saved, refreshed = open()
    wheel(1, 200)
    local function dimmed()
      return (checkInRow(LAST_ROW).alpha or 1) < 1
    end
    assert.are.same({ true, true }, { fieldInRow("Faded opacity %").alpha < 1, dimmed() })
    fake.press("Fade")
    assert.are.same({ "fade", 1 }, { saved.appearance().outOfCombat, refreshed.count })
    assert.are.same({ false, false }, { fieldInRow("Faded opacity %").alpha < 1, dimmed() })
    pressInRow("Faded opacity %", "+")
    assert.are.equal(35, saved.appearance().outOfCombatOpacity)
    fake.hook(fieldInRow("Faded opacity %"), "ONCONTENTCHANGED", ui.InputFieldActionResult.SUBMIT, "2")
    assert.are.same({ 10, "10" }, { saved.appearance().outOfCombatOpacity, fieldInRow("Faded opacity %").content })
    fake.press("Hide")
    fake.press(LAST_ROW)
    local a = saved.appearance()
    assert.are.same({ "hide", false }, { a.outOfCombat, a.showWithTarget })
    assert.are.same({ true, false }, { fieldInRow("Faded opacity %").alpha < 1, dimmed() })
  end)

  it("fades an action bar from its row, stepping its opacity by 5 and dimming it until the bar fades", function()
    local saved = openBars()
    wheel(1, 200)
    assert.is_true(fieldInRow("Main bar").alpha < 1)
    fake.tick(checkInRow("Main bar"))
    pressInRow("Main bar", "+")
    fake.tick(checkInRow("Action bar 3", 2))
    local a = saved.appearance()
    assert.are.same({ true, 30, false, 1 }, { a.fadeBar1, a.barOpacity1, a.hoverBar3, fieldInRow("Main bar").alpha })
    assert.is_true(checkInRow("Main bar").value)
    fake.hook(fieldInRow("Main bar"), "ONCONTENTCHANGED", ui.InputFieldActionResult.SUBMIT, "42")
    assert.are.same({ 40, "40" }, { saved.appearance().barOpacity1, fieldInRow("Main bar").content })
    fake.press("Hover shows all bars")
    assert.is_true(saved.appearance().hoverAllBars)
  end)

  it("turns every action bar's fading off from one switch, dimming each bar's own settings", function()
    local saved = openBars()
    wheel(1, 200)
    fake.tick(checkInRow("Main bar"))
    assert.is_false(fieldInRow("Main bar").alpha < 1)
    -- Up 40 px, so the switch's row shows whole.
    wheel(-1, 5)
    fake.press("Fade action bars")
    local a = saved.appearance()
    assert.are.same({ false, true }, { a.fadeBars, a.fadeBar1 })
    assert.is_true(fieldInRow("Main bar").alpha < 1)
    fake.press("Fade action bars")
    assert.are.same({ true, false }, { saved.appearance().fadeBars, fieldInRow("Main bar").alpha < 1 })
  end)

  it("saves a typed opacity only on a step of 5, keeping what is typed until then", function()
    local saved = openBars()
    wheel(1, 200)
    local field = fieldInRow("Main bar")
    field.content = "3"
    fake.hook(field, "ONCONTENTCHANGED", ui.InputFieldActionResult.CONTENT_CHANGE, "3")
    assert.are.same({ 25, "3" }, { saved.appearance().barOpacity1, field.content })
    field.content = "35"
    fake.hook(field, "ONCONTENTCHANGED", ui.InputFieldActionResult.CONTENT_CHANGE, "35")
    assert.are.equal(35, saved.appearance().barOpacity1)
  end)

  it("lets the cast bar take the adrenaline bar's width and the HUD's text size, fading each stepper", function()
    local saved = openBars()
    -- Scrolls 320 px, which shows the cast bar's rows from Width to Text size.
    wheel(1, 40)
    local width = fake.find(function(c, d)
      return fake.hasHook(c, "ONCONTENTCHANGED") and d.content == "278"
    end)
    assert.are.equal(1, width.alpha)
    fake.press("Same as adrenaline")
    assert.is_true(saved.appearance().castMatchWidth)
    assert.is_true(width.alpha < 1)
    local size = fake.find(function(c, d)
      return fake.hasHook(c, "ONCONTENTCHANGED") and d.content == "13"
    end)
    size.content = "16"
    assert.is_true(size.alpha < 1)
    fake.hook(size, "ONCONTENTCHANGED", ui.InputFieldActionResult.SUBMIT, "16")
    assert.are.same({ 16, 1 }, { saved.appearance().castTextSize, size.alpha })
    fake.press("Match HUD", 2)
    assert.are.same({ "hud", "13" }, { saved.appearance().castTextSize, size.content })
  end)

  it("redraws only the hovered option's frame, and nothing on a repeated hover", function()
    open()
    local before = {}
    for i, c in ipairs(fake.created) do
      before[i] = c.clears or 0
    end
    local hit = optionHit("Custom")
    fake.hook(hit, "ONMOUSEOVER")
    local cleared = {}
    for i, c in ipairs(fake.created) do
      if (c.clears or 0) > (before[i] or 0) then
        cleared[#cleared + 1] = c
      end
    end
    assert.are.equal(1, #cleared)
    fake.writes = 0
    fake.hook(hit, "ONMOUSEOVER")
    assert.are.equal(0, fake.writes)
  end)

  it("builds the page and its preview in at most 345 components, since the plugin layer's ids are shared", function()
    local _, _, _, built = open()
    assert.is_true(built <= 345, built)
  end)
end)
