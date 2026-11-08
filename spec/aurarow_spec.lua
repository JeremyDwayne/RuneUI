local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local savedappearance = require("src/savedappearance")
local style = require("src/style")
local view = require("src/view")

local auraRow = samples.auraRow
local incite = samples.incite

describe("aurarow", function()
  before_each(fake.reset)

  it("hides a debuff's tooltip when the target debuffs row empties under it", function()
    local tooltip = view.tooltip(fake.component())
    local looked = {}
    local row = view.auraRow(fake.component(), view.AURA_STYLES.targetDebuffs, tooltip, function(sprite)
      looked[#looked + 1] = sprite
      return { name = "Bloated" }
    end)
    row.update({ { sprite = 30098 } }, false)
    fake.hook(
      fake.find(function(c)
        return fake.hasHook(c, "ONMOUSEOVER")
      end),
      "ONMOUSEOVER"
    )
    assert.is_not_nil(samples.label("Bloated"))
    assert.is_not_nil(samples.label("Debuff on target"))

    row.update({}, false)
    assert.is_nil(fake.find(function(_, d)
      return d.content == "Bloated" or d.content == "Unknown debuff"
    end))
    assert.are.same({ 30098 }, looked)
  end)

  it("builds an aura row's tiles as auras appear and keeps them hidden once gone", function()
    local row = auraRow()
    local empty = #fake.created
    row.update({}, false)
    assert.are.equal(empty, #fake.created)
    row.update({ incite(12)[1], incite(12)[1] }, false)
    local two = #fake.created
    assert.is_true(two > empty)
    row.update({}, false)
    row.update({ incite(12)[1] }, false)
    assert.are.equal(two, #fake.created)
  end)

  it("makes no client writes when an aura row redraws unchanged icons, with or without bars", function()
    for _, bars in ipairs({ false, true }) do
      local row = auraRow()
      row.update(incite(12), bars)
      fake.writes = 0
      row.update(incite(12), bars)
      assert.are.equal(0, fake.writes)
    end
  end)

  it("draws a missing Keep up tile dim with a dashed outline and no time, steady after", function()
    local row = auraRow()
    local missing = { { sprite = 30093, missing = true, highlight = false } }
    row.update(missing, false)
    local icon = fake.find(function(_, d)
      return d.sprite == 30093
    end)
    assert.are.equal(0.35, icon.alpha)
    assert.is_not_nil(fake.find(function(_, d)
      return d.width == 42 and d.height == 42
    end))
    assert.is_nil(fake.find(function(_, d)
      return d.parent == row.layer and (d.content or "") ~= ""
    end))
    fake.writes = 0
    row.update(missing, false)
    assert.are.equal(0, fake.writes)
  end)

  it("bounds an aura row by its shown icons and at least one, reporting when they change", function()
    local row = auraRow()
    assert.are.same({ x = 174, y = 3, w = 36, h = 36 }, row.bounds)
    assert.is_false(row.update(incite(12), false))
    local two = incite(12)
    two[2] = { sprite = 30093, text = "6m" }
    assert.is_true(row.update(two, false))
    assert.are.same({ x = 155, y = 3, w = 74, h = 36 }, row.bounds)
    assert.is_true(row.update({}, true))
    assert.are.same({ x = 174, y = 3, w = 36, h = 41 }, row.bounds)
  end)

  it("sizes an aura row's tiles and text from its look, reporting the bounds that moved", function()
    local row = auraRow()
    row.update(incite(12), false)
    local appearance = savedappearance.defaults()
    appearance.combatBuffsIcon = 48
    appearance.combatBuffsText = 16
    local look = style.look(appearance, nil)
    assert.is_true(row.setLook(look))
    assert.are.same({ x = 228, y = 3, w = 48, h = 48 }, row.bounds)
    assert.is_not_nil(fake.find(function(_, d)
      return d.sprite == 14766 and d.width == 46 and d.height == 46
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "12" and d.width == 48 and d.height == 18 and d.font == id.Font.MUSEO_SANS_17PT_BOLD
    end))
    fake.writes = 0
    assert.is_false(row.setLook(look))
    row.update(incite(12), false)
    assert.are.equal(0, fake.writes)
  end)

  it("draws aura icons over the game's dark slot, edging debuffs in the look's colour", function()
    local row = view.auraRow(
      fake.component(),
      view.AURA_STYLES.targetDebuffs,
      view.tooltip(fake.component()),
      function() end
    )
    local appearance = savedappearance.defaults()
    appearance.debuffEdge = "white"
    row.setLook(style.look(appearance, nil))
    row.update({ { sprite = 30098 } }, false)
    assert.is_not_nil(fake.find(function(_, d)
      return d.parent == row.layer and d.rgb == draw.COLOURS.slot and d.width == 24 and d.height == 24
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.parent == row.layer and d.rgb == 0xffffff and d.width == 26 and d.height == 26
    end))
  end)
end)
