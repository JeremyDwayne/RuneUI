local fake = require("spec/support/fake_ui")
local view = require("src/view")

describe("view", function()
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
end)
