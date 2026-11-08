local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local savedgroups = require("src/savedgroups")
local savedappearance = require("src/savedappearance")
local style = require("src/style")
local view = require("src/view")

local readyTiles = samples.readyTiles
local group = samples.group
local label = samples.label

describe("cooldowngroup", function()
  before_each(fake.reset)

  it("makes no client writes when a cooldown group redraws unchanged tiles", function()
    local tiles = readyTiles(9)
    tiles[6].queued = true
    tiles[2] = { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, keybind = "Q", remaining = 3.6 }
    tiles[3].count = "8"
    tiles[3].stacks = { key = "necrosis", count = 8, max = 12, gold = 6, notch = 6 }
    tiles[4].count = "1"
    tiles[4].charges = 1
    tiles[4].recharge = { remaining = 6, length = 10.2 }
    tiles[5].count = "2/3"
    for _, grow in ipairs(savedgroups.GROWS) do
      local g = group(36, 7, grow)
      g.update(tiles)
      fake.writes = 0
      assert.is_false(g.configure({ size = 36, perRow = 7, grow = grow }))
      g.update(tiles)
      assert.are.equal(0, fake.writes, grow)
    end
  end)

  it("fades a held cooldown group by each part's own alpha, and redraws unchanged tiles with no writes", function()
    local tiles = readyTiles(3)
    tiles[2] = { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, keybind = "Q", remaining = 3.6 }
    local g = group()
    view.holdable({ g })
    g.update(tiles)
    local alphas = {}
    for _, c in ipairs(fake.created) do
      alphas[c] = c.alpha or 1
    end
    view.fade(0.3)
    g.update(tiles)
    fake.writes = 0
    g.update(tiles)
    view.fade(0.3)
    assert.are.equal(0, fake.writes)
    local faded = 0
    for c, alpha in pairs(alphas) do
      if c.parent == g.layer then
        assert.is_near(alpha * 0.3, c.alpha, 1e-9)
        faded = faded + 1
      end
    end
    assert.is_true(faded > 10)
    view.fade(1)
    for c, alpha in pairs(alphas) do
      if c.parent == g.layer then
        assert.is_near(alpha, c.alpha, 1e-9)
      end
    end
  end)

  it("counts a cooling tile's whole seconds down between server ticks, writing only when they change", function()
    local g = group()
    g.update({ { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, remaining = 4.2 } }, 0)
    assert.is_not_nil(label("5"))
    g.step(0.2)
    assert.is_not_nil(label("4"))
    fake.writes = 0
    g.step(0.58)
    assert.are.equal(0, fake.writes)
  end)

  it("writes a tile's count once when it changes", function()
    local g = group()
    local tile =
      { key = "MAGIC_SURGE", name = "Surge", initials = "S", icon = 14233, ready = true, count = "2", charges = 2 }
    g.update({ tile })
    tile.count = "1"
    fake.writes = 0
    g.update({ tile })
    local writes = fake.writes
    assert.is_not_nil(label("1"))
    assert.is_true(writes > 0)
    fake.writes = 0
    g.update({ tile })
    assert.are.equal(0, fake.writes)
  end)

  it("writes a tile's count in the 13 pt body font on a small tile", function()
    local g = group(30)
    g.update({
      { key = "MAGIC_SURGE", name = "Surge", initials = "S", icon = 14233, ready = true, count = "1", charges = 1 },
    })
    local look = style.look(savedappearance.defaults(), nil)
    local body = look.outline and style.outlineFont(look.fonts.body) or look.fonts.body
    assert.are.equal(body, label("1").font)
  end)

  it("fills a spender's tile bar to its count in the row colour, growing it with whole casts gold", function()
    local g = group(36)
    local tile = { key = "NECROMANCY_FINGER_OF_DEATH", name = "Finger of Death", initials = "FOD", icon = 30077 }
    tile.ready = true
    tile.count = "5"
    tile.stacks = { key = "necrosis", count = 5, max = 12, gold = 0, notch = 6 }
    g.update({ tile })
    local function shownRect(rgb)
      return fake.find(function(_, d)
        return d.rgb == rgb and d.height ~= nil and d.height <= 8
      end)
    end
    local fill = shownRect(draw.COLOURS.necrosis)
    assert.are.same({ 14, 3 }, { fill.width, fill.height })
    assert.is_nil(shownRect(draw.WINDOW.accent))
    local notch = shownRect(draw.COLOURS.highlight)
    assert.are.same({ 2, 3 }, { notch.width, notch.height })
    tile.count = "6"
    tile.stacks = { key = "necrosis", count = 6, max = 12, gold = 6, notch = 6 }
    g.update({ tile })
    local gold = shownRect(draw.WINDOW.accent)
    assert.are.same({ 17, 5, 5, 5 }, { gold.width, gold.height, fill.height, notch.height })
    fake.writes = 0
    g.update({ tile })
    assert.are.equal(0, fake.writes)
  end)

  it("moves a charge's white recharge bar between server ticks, writing only when its width changes", function()
    local g = group(36)
    local tile = { key = "MAGIC_SURGE", name = "Surge", initials = "S", icon = 14233, ready = true, count = "1" }
    tile.charges = 1
    tile.recharge = { remaining = 6, length = 10.2 }
    g.update({ tile }, 0)
    local fill = fake.find(function(_, d)
      return d.rgb == draw.COLOURS.highlight and d.height == 3
    end)
    assert.is_true(fill.width < 15)
    g.step(0.45)
    assert.are.equal(15, fill.width)
    fake.writes = 0
    g.step(0.46)
    assert.are.equal(0, fake.writes)
    tile.charges = 2
    tile.count = "2"
    tile.recharge = nil
    g.update({ tile }, 0)
    assert.is_false(fake.shown(fill))
  end)

  it("borders the queued tile in gold with a light segment once round each tick, and drops it once fired", function()
    local g = group(38)
    local tiles = readyTiles(2)
    g.update(tiles, 0)
    local built = #fake.created
    tiles[2].queued = true
    g.update(tiles, 0)
    assert.are.equal(built + 7, #fake.created)
    local function shownOf(rgb)
      local list = {}
      for _, c in ipairs(fake.created) do
        if fake.shown(c) and c.rgb == rgb then
          list[#list + 1] = c
        end
      end
      return list
    end
    local band = shownOf(draw.WINDOW.accent)
    local x = band[1].x
    local firstEdge = fake.find(function(_, d)
      return d.width == 38 and d.rgb == draw.COLOURS.border
    end)
    assert.are.same({ 4, 40 }, { #band, x - firstEdge.x })
    -- At the tick the segment, 30% of the way round, covers the top and the first 7 px of the right side.
    local chase = shownOf(0xfff1c4)
    assert.are.same({ x, 0, 38, 2 }, { chase[1].x, chase[1].y, chase[1].width, chase[1].height })
    assert.are.same({ x + 36, 0, 2, 9 }, { chase[2].x, chase[2].y, chase[2].width, chase[2].height })
    -- A quarter of a tick later it covers the right side and the first 7 px of the bottom.
    g.step(0.15)
    chase = shownOf(0xfff1c4)
    assert.are.same({ x + 36, 0, 2, 38 }, { chase[1].x, chase[1].y, chase[1].width, chase[1].height })
    assert.are.same({ x + 29, 36, 9, 2 }, { chase[2].x, chase[2].y, chase[2].width, chase[2].height })
    fake.writes = 0
    g.step(0.151)
    assert.are.equal(0, fake.writes)
    tiles[2].queued = false
    g.update(tiles, 0)
    assert.are.same({ 0, 0 }, { #shownOf(draw.WINDOW.accent), #shownOf(0xfff1c4) })
    fake.writes = 0
    g.step(0.3)
    assert.are.equal(0, fake.writes)
    tiles[2].queued = true
    built = #fake.created
    g.update(tiles, 0)
    assert.are.same({ built, 4 }, { #fake.created, #shownOf(draw.WINDOW.accent) })
  end)

  it("makes no writes stepping a group with no cooling tile", function()
    local g = group()
    g.update(readyTiles(3))
    fake.writes = 0
    g.step(0.3)
    assert.are.equal(0, fake.writes)
  end)

  it("tints a tile's icon and keybind as the native bar does while its ability can't be cast", function()
    local g = group()
    local tile = {
      key = "MAGIC_WILD_MAGIC",
      name = "Wild Magic",
      initials = "WM",
      icon = 14385,
      keybind = "W",
      ready = true,
      usable = false,
    }
    g.update({ tile })
    local icon = fake.find(function(_, d)
      return d.sprite == 14385
    end)
    local keybind = label("W")
    assert.are.same({ 0x333333, 0xa5a5a5, 0.6 }, { icon.rgb, keybind.rgb, keybind.alpha })
    tile.usable = true
    g.update({ tile })
    assert.are.same({ 0xffffff, 1 }, { icon.rgb, keybind.alpha })
  end)

  it("adds an ability's description to its cooldown tooltip, ending with Ready", function()
    local tooltip = view.tooltip(fake.component())
    local g = view.cooldownGroup(fake.component(), tooltip, function(key)
      return key == "K1" and "Inflict searing pain on the target." or nil
    end)
    g.configure({ size = 36, perRow = 7, grow = "down" })
    g.update(readyTiles(1))
    fake.hook(
      fake.find(function(c)
        return fake.hasHook(c, "ONMOUSEOVER")
      end),
      "ONMOUSEOVER"
    )
    local info = label("Inflict searing pain on the target.")
    assert.is_true(label("Ready").y > info.y)
  end)

  it("bounds a cooldown group by its shown tiles, meeting at its axis when empty", function()
    local g = group(36, 7, "down")
    assert.is_true(g.update(readyTiles(9)))
    assert.are.same({ x = 0, y = 0, w = 264, h = 74 }, g.bounds)
    assert.is_false(g.update(readyTiles(9)))
    g.update({})
    assert.are.same({ x = 132, y = 0, w = 0, h = 36 }, g.bounds)
  end)

  it("keeps an up group's last tile on its bottom row and a left group's on its right column", function()
    local up = group(36, 7, "up")
    local left = group(30, 2, "left")
    up.update(readyTiles(3))
    left.update(readyTiles(3))
    assert.are.same({ x = 76, y = 76, w = 112, h = 36 }, up.bounds)
    assert.are.same({ x = 256, y = 0, w = 62, h = 62 }, left.bounds)
  end)

  it("resizes its tiles in place, building more only as the group grows", function()
    local g = group(36, 7, "down")
    g.update(readyTiles(3))
    local built = #fake.created
    assert.is_true(g.configure({ size = 44, perRow = 7, grow = "down" }))
    g.update(readyTiles(3))
    assert.are.equal(built, #fake.created)
    assert.is_not_nil(fake.find(function(_, d)
      return d.width == 44 and d.height == 44
    end))
    g.update(readyTiles(20))
    g.update(readyTiles(25))
    local full = #fake.created
    g.update(readyTiles(2))
    assert.are.equal(full, #fake.created)
  end)

  it("hides a group not in use and collapses its bounds", function()
    local g = group()
    g.update(readyTiles(3))
    g.setInUse(false)
    assert.is_true(g.update(readyTiles(3)))
    assert.are.same({ 0, 0 }, { g.bounds.w, g.bounds.h })
    assert.is_true(g.layer.hidden)
  end)

  it("updates a custom group that was never configured while it is not in use", function()
    local g = view.cooldownGroup(fake.component(), view.tooltip(fake.component()))
    g.setInUse(false)
    assert.has_no.errors(function()
      g.update({})
    end)
    assert.are.same({ 0, 0 }, { g.bounds.w, g.bounds.h })
  end)
end)
