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
    target = view.targetFrame(root),
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

  it("tints a tile's icon and keybind as the native bar does while its ability can't be cast", function()
    local group = view.cooldownGroup(fake.component(), view.TILE_STYLES.rotation, view.tooltip(fake.component()))
    local tile = { key = "MAGIC_WILD_MAGIC", name = "Wild Magic", initials = "WM", icon = 14385, keybind = "W",
      ready = true, usable = false }
    group.update({ tile }, nil)
    local icon = fake.find(function(_, d) return d.sprite == 14385 end)
    local keybind = fake.find(function(_, d) return d.content == "W" end)
    assert.are.same({ 0x333333, 0xa5a5a5, 0.6 }, { icon.rgb, keybind.rgb, keybind.alpha })
    tile.usable = true
    group.update({ tile }, nil)
    assert.are.same({ 0xffffff, 1 }, { icon.rgb, keybind.alpha })
  end)

  it("makes no client writes when the tooltip is shown again at the same icon", function()
    local tooltip = view.tooltip(fake.component())
    local content = { title = "Sunshine", left = "Cooldown 60s", line = "Ready" }
    tooltip.show(content, 100, 300, 42)
    fake.writes = 0
    tooltip.show(content, 100, 300, 42)
    assert.are.equal(0, fake.writes)
  end)

  it("hides a debuff's tooltip when the target debuffs row empties under it", function()
    local tooltip = view.tooltip(fake.component())
    local looked = {}
    local row = view.auraRow(fake.component(), view.AURA_STYLES.targetDebuffs, tooltip, function(sprite)
      looked[#looked + 1] = sprite
      return { name = "Bloated" }
    end)
    row.update({ { sprite = 30098 } }, false)
    fake.hook(fake.find(function(c) return fake.hasHook(c, "ONMOUSEOVER") end), "ONMOUSEOVER")
    assert.is_not_nil(fake.find(function(_, d) return d.content == "Bloated" end))

    row.update({}, false)
    assert.is_nil(fake.find(function(_, d) return d.content == "Bloated" or d.content == "Unknown debuff" end))
    assert.are.same({ 30098 }, looked)
  end)

  -- A combat buffs row, and the src/auras model of a 20 s buff with left seconds left.
  local function auraRow()
    return view.auraRow(fake.component(), view.AURA_STYLES.combatBuffs, view.tooltip(fake.component()),
      function() end)
  end
  local function incite(left)
    return { { sprite = 14766, text = tostring(left), stacks = "5", left = left, full = 20, fill = left / 20,
      highlight = left <= 2 } }
  end

  it("makes no client writes when an aura row redraws unchanged icons, with or without bars", function()
    for _, bars in ipairs({ false, true }) do
      local row = auraRow()
      row.update(incite(12), bars)
      fake.writes = 0
      row.update(incite(12), bars)
      assert.are.equal(0, fake.writes)
    end
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

  it("draws the player and target frames the same height, with or without a prayer bar", function()
    local elements = hud()
    -- A frame's box is the tallest full-width component on its layer: its black border.
    local function boxHeight(frame)
      local tallest = 0
      fake.find(function(_, d)
        if d.parent == frame.layer and d.width == frame.width then tallest = math.max(tallest, d.height or 0) end
      end)
      return tallest
    end
    elements.player.update({ hidden = false, name = "Jeremy", valueText = "", fill = 1 })
    elements.target.update({ hidden = false, name = "Aviansie", valueText = "", fill = 1, debuffs = {} })
    assert.are.equal(boxHeight(elements.player), boxHeight(elements.target))
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
