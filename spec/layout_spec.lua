local layout = require("src/layout")
local savedlayout = require("src/savedlayout")

-- Shown bounds inside each element's layer with full first rows: 6 major, 6 rotation and 8 utility and custom
-- tiles, Defensives at 30 px, no spender rows, and 10 aura tiles.
local function fullBounds()
  local function row(size, count)
    return layout.grid(count, size, 2, count, "down", 20).bounds
  end
  return {
    player = { x = 0, y = 0, w = 250, h = 55 },
    target = { x = 0, y = 0, w = 250, h = 55 },
    resource = { x = 0, y = 20, w = 278, h = 20 },
    castbar = { x = 0, y = 0, w = 278, h = 22 },
    major = row(35, 6),
    rotation = row(45, 6),
    utility = row(30, 8),
    custom1 = row(30, 8),
    custom2 = row(36, 8),
    custom3 = row(36, 8),
    custom4 = row(36, 8),
    targetDebuffs = { x = 3, y = 3, w = 278, h = 26 },
    playerDebuffs = { x = 3, y = 3, w = 278, h = 26 },
    upkeepBuffs = { x = 3, y = 3, w = 278, h = 26 },
    combatBuffs = { x = 3, y = 3, w = 378, h = 36 },
  }
end

local function at(x, y)
  return { x = x, y = y, anchorX = 0.5, anchorY = 1 }
end

describe("layout", function()
  it("reproduces the default positions from the default anchors with a full rotation row", function()
    local positions = layout.resolve(savedlayout.DEFAULT_POSITIONS, savedlayout.DEFAULT_ANCHORS, fullBounds())
    assert.are.same(savedlayout.DEFAULT_POSITIONS, positions)
  end)

  it("moves the frames in to stay beside 4 shown rotation tiles", function()
    local bounds = fullBounds()
    bounds.rotation = layout.grid(4, 45, 2, 6, "down", 20).bounds
    local positions = layout.resolve(savedlayout.DEFAULT_POSITIONS, savedlayout.DEFAULT_ANCHORS, bounds)
    assert.are.equal(-140 + 47 - 250, positions.player.x)
    assert.are.equal(-140 + 47 + 186, positions.target.x)
    assert.are.equal(-362, positions.player.y)
  end)

  it("pushes everything below a major group that wraps to a second row", function()
    local bounds = fullBounds()
    bounds.major = layout.grid(8, 35, 2, 6, "down", 20).bounds
    local positions = layout.resolve(savedlayout.DEFAULT_POSITIONS, savedlayout.DEFAULT_ANCHORS, bounds)
    local defaults = savedlayout.DEFAULT_POSITIONS
    assert.are.same(
      { defaults.rotation.y + 37, defaults.target.y + 37, defaults.utility.y + 37 },
      { positions.rotation.y, positions.target.y, positions.utility.y }
    )
  end)

  it("pushes utility down by spender rows below the adrenaline bar", function()
    local bounds = fullBounds()
    bounds.resource = { x = 0, y = 20, w = 278, h = 40 }
    local positions = layout.resolve(savedlayout.DEFAULT_POSITIONS, savedlayout.DEFAULT_ANCHORS, bounds)
    assert.are.same(
      { savedlayout.DEFAULT_POSITIONS.castbar.y + 20, savedlayout.DEFAULT_POSITIONS.utility.y + 20 },
      { positions.castbar.y, positions.utility.y }
    )
  end)

  it("places a child flush on each side and alignment of its target", function()
    local target = { x = 100, y = -200, w = 100, h = 50 }
    local cases = {
      { "left", "top", 80, -200 },
      { "left", "center", 80, -180 },
      { "left", "bottom", 80, -160 },
      { "right", "top", 200, -200 },
      { "right", "center", 200, -180 },
      { "right", "bottom", 200, -160 },
      { "top", "left", 100, -210 },
      { "top", "center", 140, -210 },
      { "top", "right", 180, -210 },
      { "bottom", "left", 100, -150 },
      { "bottom", "center", 140, -150 },
      { "bottom", "right", 180, -150 },
    }
    for _, case in ipairs(cases) do
      local side, align, x, y = table.unpack(case)
      local anchor = { target = "rotation", side = side, align = align, gap = 0, offset = 0 }
      local positions = layout.resolve(
        { rotation = at(100, -200), player = at(0, 0) },
        { player = anchor },
        { rotation = { x = 0, y = 0, w = 100, h = 50 }, player = { x = 0, y = 0, w = 20, h = 10 } }
      )
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
    local anchors = savedlayout.DEFAULT_ANCHORS
    local chain = layout.chain(anchors, "resource")
    table.sort(chain)
    assert.are.same({ "castbar", "custom1", "custom2", "custom3", "custom4", "utility" }, chain)
    local rotationChain = layout.chain(anchors, "rotation")
    table.sort(rotationChain)
    assert.are.same({
      "castbar",
      "custom1",
      "custom2",
      "custom3",
      "custom4",
      "player",
      "playerDebuffs",
      "resource",
      "target",
      "targetDebuffs",
      "upkeepBuffs",
      "utility",
    }, rotationChain)
    assert.is_false(layout.canAnchor(anchors, "major", "major"))
    assert.is_false(layout.canAnchor(anchors, "major", "utility"))
    assert.is_true(layout.canAnchor(anchors, "utility", "player"))
  end)

  it("snaps an edge or center within range onto another element's lines, with a guide on the snapped axis", function()
    local other = { x = 0, y = 0, w = 100, h = 100 }
    local cases = {
      { 3, 500, 0, 500, 0, nil },
      { 33, 500, 35, 500, 50, nil },
      { 72, 500, 70, 500, 100, nil },
      { 104, 500, 100, 500, 100, nil },
      { 500, -4, 500, 0, nil, 0 },
      { 500, 37, 500, 40, nil, 50 },
      { 500, 83, 500, 80, nil, 100 },
    }
    for _, case in ipairs(cases) do
      local x, y, toX, toY, guideX, guideY = table.unpack(case, 1, 6)
      local snapped = layout.snap({ x = x, y = y, w = 30, h = 20 }, { other }, 6)
      assert.are.same({ x = toX, y = toY, guideX = guideX, guideY = guideY }, snapped)
    end
  end)

  it("prefers element lines over closer grid lines, and snaps edges to the grid otherwise", function()
    local snapped = layout.snap({ x = 100, y = 203, w = 30, h = 20 }, { { x = 95, y = 0, w = 100, h = 100 } }, 6, 16)
    assert.are.same({ x = 95, y = 204, guideX = 95, guideY = 224 }, snapped)
  end)

  it("leaves a rect beyond range where it is", function()
    local snapped = layout.snap({ x = 107, y = 500, w = 30, h = 20 }, { { x = 0, y = 0, w = 100, h = 100 } }, 6)
    assert.are.same({ x = 107, y = 500 }, snapped)
  end)

  it("offers every element outside the dragged one's chain as a snap target", function()
    local rects = fullBounds()
    local skipped = { player = true, playerDebuffs = true, upkeepBuffs = true }
    local targets = layout.snapTargets(rects, savedlayout.DEFAULT_ANCHORS, "player")
    local count = 0
    for name in pairs(rects) do
      if not skipped[name] then
        count = count + 1
      end
    end
    assert.are.equal(count, #targets)
    assert.are.same({}, layout.snapTargets(rects, savedlayout.DEFAULT_ANCHORS, "major"))
  end)

  it("wraps a down group into centred rows below its first", function()
    local g = layout.grid(9, 36, 2, 7, "down", 14)
    assert.are.same({ 264, 74 }, { g.w, g.h })
    assert.are.same({ x = 0, y = 0 }, g.tiles[1])
    assert.are.same({ x = 228, y = 0 }, g.tiles[7])
    assert.are.same({ { x = 95, y = 38 }, { x = 133, y = 38 } }, { g.tiles[8], g.tiles[9] })
    assert.are.same({ x = 0, y = 0, w = 264, h = 74 }, g.bounds)
  end)

  it("keeps an up group's bottom edge and centres a short row on the axis", function()
    local g = layout.grid(3, 36, 2, 7, "up", 14)
    assert.are.same({ x = 76, y = 38 }, g.tiles[1])
    assert.are.same({ x = 76, y = 38, w = 112, h = 36 }, g.bounds)
  end)

  it("lays a left group in columns that stack leftward from its right edge", function()
    local g = layout.grid(5, 30, 2, 2, "left", 6)
    assert.are.same({ 94, 62 }, { g.w, g.h })
    assert.are.same({ { x = 64, y = 0 }, { x = 64, y = 32 } }, { g.tiles[1], g.tiles[2] })
    assert.are.same({ x = 0, y = 16 }, g.tiles[5])
    assert.are.same({ x = 0, y = 0, w = 94, h = 62 }, g.bounds)
  end)

  it("bounds an empty group one row deep with its sides meeting at the axis", function()
    assert.are.same({ x = 132, y = 0, w = 0, h = 36 }, layout.grid(0, 36, 2, 7, "down", 14).bounds)
  end)
end)
