local frames = require("src/frames")

local MARKERS = { threshold = 50, ultimate = 100 }

describe("frames.formatAmount", function()
  it("uses commas below ten thousand and K or M above", function()
    assert.are.equal("6,800", frames.formatAmount(6800))
    assert.are.equal("13.1K", frames.formatAmount(13158))
    assert.are.equal("100K", frames.formatAmount(100000))
    assert.are.equal("1.2M", frames.formatAmount(1234567))
  end)
end)

describe("frames.player", function()
  local reads = {
    available = true,
    name = "JeremyDwayne",
    lifepoints = 13158,
    lifepointsLabel = "13,158/16,845",
    prayerValue = 6530436,
    prayerLabel = "960/990",
  }

  it("shows lifepoints, percent and fill when the max label is readable", function()
    local model = frames.player(reads)
    assert.are.equal("JeremyDwayne", model.name)
    assert.are.equal("13.1K | 78%", model.valueText)
    assert.is_near(13158 / 16845, model.fill, 1e-9)
  end)

  it("shows only current lifepoints when the max label is missing", function()
    local model = frames.player({ available = true, name = "J", lifepoints = 6800 })
    assert.are.equal("6,800", model.valueText)
    assert.is_nil(model.fill)
  end)

  it("decodes prayer points from the packed var and fills against the label max", function()
    local model = frames.player(reads)
    assert.are.equal("960", model.prayerText)
    assert.is_near(960 / 990, model.prayerFill, 1e-9)
  end)

  it("hides when no character is logged in", function()
    assert.is_true(frames.player({ available = false }).hidden)
  end)
end)

describe("frames.resource", function()
  it("shows adrenaline percent and fill from tenths of a percent", function()
    local model = frames.resource({ adrenaline = 800, spenders = {} }, MARKERS)
    assert.are.equal("80%", model.text)
    assert.is_near(0.8, model.fill, 1e-9)
  end)

  it("places markers at the configured threshold and ultimate costs", function()
    local model = frames.resource({ adrenaline = 0, spenders = {} }, { threshold = 60, ultimate = 100 })
    assert.is_near(0.6, model.markers[1].at, 1e-9)
    assert.are.equal("Threshold", model.markers[1].label)
    assert.is_near(1.0, model.markers[2].at, 1e-9)
  end)

  it("shows spender blocks only while the resource has stacks", function()
    local souls = "COMBATV2_BUFF_NECROMANCY_RESIDUAL_SOUL_STACKS"
    local shown = frames.resource({ adrenaline = 0, spenders = { [souls] = 3 } }, MARKERS)
    assert.are.same({ label = "Souls", count = 3, max = 5 }, shown.spender)
    local empty = frames.resource({ adrenaline = 0, spenders = { [souls] = 0 } }, MARKERS)
    assert.is_nil(empty.spender)
  end)
end)
