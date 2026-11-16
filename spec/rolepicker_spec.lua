local fake = require("spec/support/fake_ui")
local fakeStore = require("spec/support/fake_store")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local party = require("src/party")
local rolepicker = require("src/rolepicker")
local settings = require("src/settings")

local label = samples.label

local BOSSES = {
  { name = "Vorago", tags = { "BT", "TL5", "Bomb", "Vit", "PT" } },
  { name = "Raids", tags = { "NT", "CPR" } },
}

-- A picker on a 1000 by 800 root. Returns it, the root, the settings and a table counting HUD redraws.
local function create()
  local root = fake.component()
  root.width, root.height = 1000, 800
  local saved = settings.load(fakeStore())
  local state = { refreshes = 0 }
  local picker = rolepicker.create(root, {
    saved = saved,
    bosses = BOSSES,
    refresh = function()
      state.refreshes = state.refreshes + 1
    end,
  })
  return picker, root, saved, state
end

-- The open picker's tag field.
local function field()
  return fake.find(function(_, d)
    return d.hooks.ONCONTENTCHANGED ~= nil
  end)
end

describe("rolepicker.layout", function()
  it("puts the tag field first, then Base tank and None, then each boss's tags four to a row under its name", function()
    local layout = rolepicker.layout(BOSSES)
    assert.are.same({ 196, 192 }, { layout.w, layout.h })
    assert.are.same({ x = 8, y = 32, w = 180, h = 24 }, layout.field)
    assert.are.same({ x = 8, y = 60, w = 42, h = 20, label = "BT", tag = "BT" }, layout.tiles[1])
    assert.are.same({ x = 54, y = 60, w = 42, h = 20, label = "None", tag = false }, layout.tiles[2])
    assert.are.same(
      { { text = "Vorago", x = 8, y = 84, w = 180, h = 16 }, { text = "Raids", x = 8, y = 148, w = 180, h = 16 } },
      layout.heads
    )
    assert.are.same({ 146, 100, "Vit" }, { layout.tiles[6].x, layout.tiles[6].y, layout.tiles[6].tag })
    assert.are.same({ 8, 124, "PT" }, { layout.tiles[7].x, layout.tiles[7].y, layout.tiles[7].tag })
    assert.are.same({ 54, 164, "CPR" }, { layout.tiles[9].x, layout.tiles[9].y, layout.tiles[9].tag })
  end)
end)

describe("bossroles", function()
  it("holds only tags short enough for a picker tile", function()
    for _, boss in ipairs(require("src/bossroles")) do
      for _, tag in ipairs(boss.tags) do
        assert.is_true(#tag >= 1 and #tag <= 4, boss.name .. " " .. tag)
        assert.is_nil(tag:find("%s"))
      end
    end
  end)
end)

describe("rolepicker", function()
  before_each(fake.reset)

  it("opens at the place given, kept on the screen, names the member and marks their tag", function()
    local picker, _, saved = create()
    saved.setRole("Oakhelm", "TL5")
    picker.open("Oakhelm", 990, 100)
    assert.is_true(picker.isOpen())
    assert.is_truthy(label("Oakhelm"))
    assert.are.equal(1000 - 196, label("Oakhelm").parent.x)
    assert.are.equal(draw.WINDOW.accentText, label("TL5").rgb)
    assert.are.equal(draw.WINDOW.text, label("Bomb").rgb)
  end)

  it("saves a pressed tag as the member's, redraws the HUD and hides, holding nothing after the next tick", function()
    local picker, root, saved, state = create()
    picker.open("Oakhelm", 100, 100)
    fake.press("Bomb")
    assert.are.equal("Bomb", party.tag(saved.roles(), "Oakhelm"))
    assert.are.equal(1, state.refreshes)
    assert.is_false(picker.isOpen())
    -- The press runs inside the tile's own hook, so the picker is only hidden until a tick.
    assert.is_nil(label("Oakhelm"))
    assert.is_true(fake.live(root) > 0)
    picker.tick()
    assert.are.equal(0, fake.live(root))
    picker.open("Oakhelm", 100, 100)
    fake.press("None")
    assert.is_nil(party.tag(saved.roles(), "Oakhelm"))
  end)

  it("saves a tag as it is typed, marking a tile it matches, and closes on Enter", function()
    local picker, _, saved, state = create()
    picker.open("Oakhelm", 100, 100)
    local results = ui.InputFieldActionResult
    fake.hook(field(), "ONCONTENTCHANGED", results.CONTENT_CHANGE, "CPR")
    assert.are.equal("CPR", party.tag(saved.roles(), "Oakhelm"))
    assert.are.equal(1, state.refreshes)
    assert.are.equal(draw.WINDOW.accentText, label("CPR").rgb)
    assert.is_true(picker.isOpen())
    -- Losing focus with nothing typed leaves the tag alone.
    fake.hook(field(), "ONCONTENTCHANGED", results.SUBMIT_ON_FOCUS_LOSS, "")
    assert.are.equal("CPR", party.tag(saved.roles(), "Oakhelm"))
    fake.hook(field(), "ONCONTENTCHANGED", results.SUBMIT, "CPR")
    assert.is_false(picker.isOpen())
  end)

  it("closes on a click elsewhere on the screen, leaving the tag alone", function()
    local picker, root, saved = create()
    saved.setRole("Oakhelm", "NT")
    picker.open("Oakhelm", 100, 100)
    local catcher = fake.find(function(c, d)
      return d.hooks.ONCLICK ~= nil and c.width == 1000 and c.height == 800
    end)
    fake.hook(catcher, "ONCLICK")
    assert.is_false(picker.isOpen())
    picker.tick()
    assert.are.equal(0, fake.live(root))
    assert.are.equal("NT", party.tag(saved.roles(), "Oakhelm"))
  end)
end)
