local fake = require("spec/support/fake_ui")
local settings = require("src/settings")
local view = require("src/view")

-- n ready tiles for a cooldown group.
local function readyTiles(n)
  local out = {}
  for i = 1, n do out[i] = { key = "K" .. i, name = "Tile " .. i, initials = "T" .. i, ready = true } end
  return out
end

-- Every HUD element on one root.
local function hud()
  local root = fake.component()
  local tooltip = view.tooltip(root)
  return {
    player = view.playerFrame(root),
    target = view.targetFrame(root, tooltip, function() end),
    resource = view.resourceBar(root),
    rotation = view.cooldownGroup(root, view.TILE_STYLES.rotation, tooltip),
    cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns, tooltip),
  }
end

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

  it("moves the tooltip to the front once shown, never while hidden", function()
    local tooltip = view.tooltip(fake.component())
    tooltip.show({ title = "Sunshine" }, 100, 300, 42)
    assert.is_nil(fake.find(function(_, d) return d.undrawn end))
    assert.is_not_nil(fake.find(function(_, d) return d.fronted and d.width == 200 end))
  end)

  it("keeps the tooltip inside the screen's side edges", function()
    local root = fake.component()
    root:SetSize(1000, 800)
    local tooltip = view.tooltip(root)
    local function layerX()
      return fake.find(function(_, d) return d.parent == root and d.width == 200 end).x
    end
    tooltip.show({ title = "Sunshine" }, 950, 300, 42)
    assert.are.equal(800, layerX())
    tooltip.show({ title = "Sunshine" }, -20, 300, 42)
    assert.are.equal(0, layerX())
  end)

  it("bounds a cooldown row by its shown tiles, meeting at its center when empty", function()
    local group = view.cooldownGroup(fake.component(), view.TILE_STYLES.rotation, view.tooltip(fake.component()))
    assert.is_true(group.update(readyTiles(7)))
    assert.are.same({ x = 66, y = 0, w = 306, h = 47 }, group.bounds)
    assert.is_false(group.update(readyTiles(7)))
    group.update({})
    assert.are.same({ x = 219, y = 0, w = 0, h = 47 }, group.bounds)
  end)

  it("moves anchored frames on the tick the rotation row gains a tile, and makes no writes when steady", function()
    local elements = hud()
    local saved = settings.load({ get = function() end, set = function() end })
    local function tick(count)
      local moved = elements.rotation.update(readyTiles(count))
      if moved then view.arrange(elements, saved.positions(), saved.anchors()) end
    end
    view.arrange(elements, saved.positions(), saved.anchors())
    tick(7)
    local x = elements.player.layer.x
    tick(8)
    assert.are.equal(x - 22, elements.player.layer.x)
    fake.writes = 0
    tick(8)
    assert.are.equal(0, fake.writes)
  end)
end)
