local layout = require("src/layout")
local settings = require("src/settings")

-- Shown bounds inside each element's layer with a full row of 10 rotation and 10 cooldown tiles.
local function fullBounds()
  return {
    player = { x = 0, y = 0, w = 250, h = 55 },
    target = { x = 0, y = 0, w = 250, h = 78 },
    resource = { x = 0, y = 0, w = 278, h = 47 },
    rotation = { x = 0, y = 0, w = 438, h = 47 },
    cooldowns = { x = 0, y = 0, w = 378, h = 41 },
  }
end

local function at(x, y)
  return { x = x, y = y, anchorX = 0.5, anchorY = 1 }
end

describe("layout", function()
  it("reproduces the default positions from the default anchors with a full rotation row", function()
    local positions = layout.resolve(settings.DEFAULT_POSITIONS, settings.DEFAULT_ANCHORS, fullBounds())
    assert.are.same(settings.DEFAULT_POSITIONS, positions)
  end)

  it("moves the frames in to keep their gaps from 7 shown rotation tiles", function()
    local bounds = fullBounds()
    bounds.rotation = { x = 66, y = 0, w = 306, h = 47 }
    local positions = layout.resolve(settings.DEFAULT_POSITIONS, settings.DEFAULT_ANCHORS, bounds)
    assert.are.equal(-219 + 66 - 8 - 250, positions.player.x)
    assert.are.equal(-219 + 66 + 306 + 8, positions.target.x)
    assert.are.equal(-409, positions.player.y)
  end)

  it("places a child flush on each side and alignment of its target", function()
    local target = { x = 100, y = -200, w = 100, h = 50 }
    local cases = {
      { "left", "top", 80, -200 }, { "left", "center", 80, -180 }, { "left", "bottom", 80, -160 },
      { "right", "top", 200, -200 }, { "right", "center", 200, -180 }, { "right", "bottom", 200, -160 },
      { "top", "left", 100, -210 }, { "top", "center", 140, -210 }, { "top", "right", 180, -210 },
      { "bottom", "left", 100, -150 }, { "bottom", "center", 140, -150 }, { "bottom", "right", 180, -150 },
    }
    for _, case in ipairs(cases) do
      local side, align, x, y = table.unpack(case)
      local anchor = { target = "rotation", side = side, align = align, gap = 0, offset = 0 }
      local positions = layout.resolve({ rotation = at(100, -200), player = at(0, 0) }, { player = anchor },
        { rotation = { x = 0, y = 0, w = 100, h = 50 }, player = { x = 0, y = 0, w = 20, h = 10 } })
      assert.are.same({ side, align, x, y }, { side, align, positions.player.x, positions.player.y })
      assert.are.same(target, layout.rect(positions.rotation, { x = 0, y = 0, w = 100, h = 50 }))
    end
  end)

  it("keeps a growing child's near edge fixed", function()
    local anchors = { player = { target = "rotation", side = "left", align = "bottom", gap = 8, offset = 0 } }
    local positions = { rotation = at(0, -100), player = at(0, 0) }
    local bounds = { rotation = { x = 0, y = 0, w = 100, h = 40 }, player = { x = 0, y = 0, w = 50, h = 20 } }
    local narrow = layout.resolve(positions, anchors, bounds)
    bounds.player = { x = 0, y = 0, w = 80, h = 20 }
    local wide = layout.resolve(positions, anchors, bounds)
    assert.are.equal(narrow.player.x + 50, wide.player.x + 80)
  end)

  it("resolves a chain through two levels", function()
    local positions = layout.resolve({ rotation = at(-100, -400), resource = at(0, 0), cooldowns = at(0, 0) }, {
      resource = { target = "rotation", side = "top", align = "center", gap = 10, offset = 0 },
      cooldowns = { target = "resource", side = "top", align = "left", gap = 2, offset = 5 },
    }, {
      rotation = { x = 0, y = 0, w = 200, h = 40 },
      resource = { x = 0, y = 0, w = 100, h = 20 },
      cooldowns = { x = 10, y = 0, w = 60, h = 30 },
    })
    assert.are.same(at(-50, -430), positions.resource)
    assert.are.same(at(-55, -462), positions.cooldowns)
  end)

  it("captures a dragged child's gap and offset so resolve puts it back", function()
    local bounds = { rotation = { x = 4, y = 0, w = 100, h = 40 }, player = { x = 0, y = 2, w = 50, h = 21 } }
    local target = layout.rect(at(0, -100), bounds.rotation)
    for side, aligns in pairs(layout.ALIGNS) do
      for _, align in ipairs(aligns) do
        local dropped = at(-73, -131)
        local anchor = layout.capture(layout.rect(dropped, bounds.player), target, side, align)
        anchor.target = "rotation"
        local positions = layout.resolve({ rotation = at(0, -100), player = at(0, 0) }, { player = anchor }, bounds)
        assert.are.same({ side, align, dropped }, { side, align, positions.player })
      end
    end
  end)

  it("lists every descendant in a chain and refuses anchoring into it", function()
    local anchors = settings.DEFAULT_ANCHORS
    local chain = layout.chain(anchors, "rotation")
    table.sort(chain)
    assert.are.same({ "cooldowns", "player", "resource", "target" }, chain)
    assert.are.same({ "cooldowns" }, layout.chain(anchors, "resource"))
    assert.is_false(layout.canAnchor(anchors, "rotation", "rotation"))
    assert.is_false(layout.canAnchor(anchors, "rotation", "cooldowns"))
    assert.is_true(layout.canAnchor(anchors, "cooldowns", "player"))
  end)
end)
