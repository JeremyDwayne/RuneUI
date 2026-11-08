local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local view = require("src/view")

local label = samples.label

-- The tooltip's panel layer: the shown component on root 240 wide.
local function tooltipLayer(root)
  return fake.find(function(_, d)
    return d.parent == root and d.width == 240
  end)
end

describe("tooltip", function()
  before_each(fake.reset)

  it("splits a tooltip's description into paragraphs at <br>, sized to their lines", function()
    local root = fake.component()
    local tooltip = view.tooltip(root)
    local first = "The power of Zamorak's flames causes a delayed eruption of chaos fire."
    tooltip.show(
      { title = "Flames of Zamorak", left = "Debuff on you", info = first .. "<br>Melts shields." },
      0,
      300,
      42
    )
    local a = label(first)
    local b = label("Melts shields.")
    assert.is_true(b.y >= a.y + 2 * 14)
    local twoParagraphs = tooltipLayer(root).height
    tooltip.show({ title = "Flames of Zamorak", left = "Debuff on you", info = "Melts shields." }, 0, 300, 42)
    assert.is_nil(label(first))
    assert.are.equal(twoParagraphs - 2 * 14 - 4, tooltipLayer(root).height)
  end)

  it("shows only the name and the status row for an effect with no description", function()
    local root = fake.component()
    local tooltip = view.tooltip(root)
    tooltip.show({ title = "Stunned", left = "Debuff on you", right = "4s", info = "Stuck." }, 0, 300, 42)
    tooltip.show({ title = "Stunned", left = "Debuff on you", right = "4s" }, 0, 300, 42)
    assert.is_nil(label("Stuck."))
    assert.are.equal(40, tooltipLayer(root).height)
  end)

  it("leaves out the status row when it has neither end", function()
    local root = fake.component()
    local tooltip = view.tooltip(root)
    tooltip.show({ title = "Command Skeleton Warrior", info = "Rage.", foot = "Ready" }, 0, 300, 42)
    assert.are.equal(24 + 4, label("Rage.").y)
    tooltip.show(
      { title = "Command Skeleton Warrior", left = "Cooldown 30s", info = "Rage.", foot = "Ready" },
      0,
      300,
      42
    )
    assert.are.equal(24 + 14 + 4, label("Rage.").y)
  end)

  it("makes no client writes when the tooltip is shown again at the same icon", function()
    local tooltip = view.tooltip(fake.component())
    local content = { title = "Sunshine", left = "Cooldown 60s", info = "Boosts damage.<br>Lasts 30s.", foot = "Ready" }
    tooltip.show(content, 100, 300, 42)
    fake.writes = 0
    tooltip.show(content, 100, 300, 42)
    assert.are.equal(0, fake.writes)
  end)

  it("moves the tooltip to the front once shown, never while hidden", function()
    local tooltip = view.tooltip(fake.component())
    tooltip.show({ title = "Sunshine" }, 100, 300, 42)
    assert.is_nil(fake.find(function(_, d)
      return d.undrawn
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.fronted and d.width == 240
    end))
  end)

  it("draws a cooldown's Ready line after an aura's tooltip showed first", function()
    local tooltip = view.tooltip(fake.component())
    tooltip.show({ title = "Sunshine", left = "Buff", right = "20s" }, 100, 300, 42)
    tooltip.show({ title = "Finger of Death", right = "Key 4", foot = "Ready" }, 100, 300, 42)
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Ready" and not d.undrawn
    end))
  end)

  it("keeps the tooltip inside the screen's side edges", function()
    local root = fake.component()
    root:SetSize(1000, 800)
    local tooltip = view.tooltip(root)
    local function layerX()
      return tooltipLayer(root).x
    end
    tooltip.show({ title = "Sunshine" }, 950, 300, 42)
    assert.are.equal(760, layerX())
    tooltip.show({ title = "Sunshine" }, -20, 300, 42)
    assert.are.equal(0, layerX())
  end)
end)
