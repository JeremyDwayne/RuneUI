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

  it("writes lifepoints in each frames.LIFEPOINTS format", function()
    local texts = {}
    for _, format in ipairs({ "short", "full", "amount", "percent" }) do
      texts[#texts + 1] = frames.player(reads, format).valueText
    end
    assert.are.same({ "13.1K | 78%", "13,158 / 16,845", "13.1K", "78%" }, texts)
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

  it("rounds the percent down without float error", function()
    assert.are.equal("29%", frames.resource({ adrenaline = 290, spenders = {} }, MARKERS).text)
  end)

  it("places markers at the configured threshold and ultimate costs", function()
    local model = frames.resource({ adrenaline = 0, spenders = {} }, { threshold = 60, ultimate = 100 })
    assert.is_near(0.6, model.markers[1].at, 1e-9)
    assert.is_near(1.0, model.markers[2].at, 1e-9)
  end)

  local SOULS = "COMBATV2_BUFF_NECROMANCY_RESIDUAL_SOUL_STACKS"
  local NECROSIS = "COMBATV2_BUFF_NECROMANCY_NECROSIS_STACKS"

  it("shows a row of blocks for each spender with stacks, both at once", function()
    local model = frames.resource({ adrenaline = 0, spenders = { [SOULS] = 2, [NECROSIS] = 7 } }, MARKERS)
    assert.are.same(
      { { key = "souls", count = 2, max = 3 }, { key = "necrosis", count = 7, max = 12 } },
      model.spenders
    )
    local empty = frames.resource({ adrenaline = 0, spenders = { [SOULS] = 0, [NECROSIS] = 0 } }, MARKERS)
    assert.are.same({}, empty.spenders)
  end)

  it("keeps empty spender rows while a Necromancy weapon is worn", function()
    local model = frames.resource({ adrenaline = 0, spenders = {}, necromancy = true }, MARKERS)
    assert.are.same(
      { { key = "souls", count = 0, max = 3 }, { key = "necrosis", count = 0, max = 12 } },
      model.spenders
    )
  end)

  it("caps souls at 5 with a Soulbound lantern equipped and 3 without", function()
    local with = frames.resource({ adrenaline = 0, spenders = { [SOULS] = 5 }, lantern = true }, MARKERS)
    assert.are.same({ key = "souls", count = 5, max = 5 }, with.spenders[1])
    local without = frames.resource({ adrenaline = 0, spenders = { [SOULS] = 5 } }, MARKERS)
    assert.are.same({ key = "souls", count = 3, max = 3 }, without.spenders[1])
  end)
end)

describe("frames.target", function()
  local reads = {
    target = 25128,
    name = "Aviansie",
    lifepointsLabel = "6,800",
    healthPercent = 58,
    debuffs = { 26104, 17255 },
  }

  it("shows name, exact lifepoints, percent, fill and debuff icons", function()
    local model = frames.target(reads)
    assert.are.equal("Aviansie", model.name)
    assert.are.equal("6,800 | 58%", model.valueText)
    assert.is_near(0.58, model.fill, 1e-9)
    assert.are.same({ 26104, 17255 }, model.debuffs)
  end)

  it("writes the exact lifepoints in full, as the target has no max, and the amount or percent alone", function()
    assert.are.equal("6,800 | 58%", frames.target(reads, "full").valueText)
    assert.are.equal(
      "12,242 | 58%",
      frames.target({ target = 1, lifepointsLabel = "12,242", healthPercent = 58 }, "full").valueText
    )
    assert.are.equal(
      "12.2K | 58%",
      frames.target({ target = 1, lifepointsLabel = "12,242", healthPercent = 58 }, "short").valueText
    )
    assert.are.equal("6,800", frames.target(reads, "amount").valueText)
    assert.are.equal("58%", frames.target(reads, "percent").valueText)
  end)

  it("falls back to the part it can read in any format", function()
    local unloaded = { target = 25128, healthPercent = 95, debuffs = {} }
    assert.are.equal("95%", frames.target(unloaded, "amount").valueText)
    assert.are.equal("6,800", frames.target({ target = 1, lifepointsLabel = "6,800" }, "percent").valueText)
  end)

  it("hides with no target or when the panel reads N/A", function()
    assert.is_true(frames.target({ target = -1, healthPercent = 0, debuffs = {} }).hidden)
    assert.is_true(frames.target({ target = 25128, lifepointsLabel = "N/A", debuffs = {} }).hidden)
  end)

  it("shows the percent alone when the native panel is unloaded", function()
    local model = frames.target({ target = 25128, healthPercent = 95, debuffs = {} })
    assert.are.equal("", model.name)
    assert.are.equal("95%", model.valueText)
  end)
end)
