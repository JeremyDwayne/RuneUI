local fake = require("spec/support/fake_ui")
local view = require("src/view")

describe("view", function()
  before_each(fake.reset)

  it("makes no client writes when a cooldown group redraws unchanged tiles", function()
    local group = view.cooldownGroup(fake.component(), view.TILE_STYLES.rotation, view.tooltip(fake.component()))
    local tiles = {
      { key = "MAGIC_SUNSHINE", name = "Sunshine", initials = "SUN", ready = true },
      { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, keybind = "Q", seconds = 4 },
    }
    group.update(tiles, 0x2f7fd6)
    fake.writes = 0
    group.update(tiles, 0x2f7fd6)
    assert.are.equal(0, fake.writes)
  end)

  it("makes no client writes when the tooltip is shown again at the same icon", function()
    local tooltip = view.tooltip(fake.component())
    local content = { title = "Sunshine", left = "Cooldown 60s", line = "Ready" }
    tooltip.show(content, 100, 300, 42)
    fake.writes = 0
    tooltip.show(content, 100, 300, 42)
    assert.are.equal(0, fake.writes)
  end)

  it("hides a debuff's tooltip when the target frame hides under it", function()
    local tooltip = view.tooltip(fake.component())
    local looked = {}
    local frame = view.targetFrame(fake.component(), tooltip, function(sprite)
      looked[#looked + 1] = sprite
      return { name = "Bloated" }
    end)
    frame.update({ hidden = false, name = "Aviansie", valueText = "", fill = 1, debuffs = { 30098 } })
    fake.hook(fake.find(function(c) return fake.hasHook(c, "ONMOUSEOVER") end), "ONMOUSEOVER")
    assert.is_not_nil(fake.find(function(_, d) return d.content == "Bloated" end))

    frame.update({ hidden = true })
    assert.is_nil(fake.find(function(_, d) return d.content == "Bloated" or d.content == "Unknown debuff" end))
    assert.are.same({ 30098 }, looked)
  end)
end)
