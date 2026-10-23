local fakeStore = require("spec/support/fake_store")
local savedlayout = require("src/savedlayout")

-- Saved data from this layout version, so positions and anchors in it are kept.
local CURRENT = { layout = savedlayout.LAYOUT_VERSION }

describe("savedlayout", function()
  it("resets positions to the defaults", function()
    local s = savedlayout.load(fakeStore())
    s.setPosition("player", { x = 1, y = 2, anchorX = 0, anchorY = 0 })
    s.resetPositions()
    assert.are.same(savedlayout.DEFAULT_POSITIONS.player, s.positions().player)
  end)

  it("drops positions and anchors saved for an older default layout once", function()
    local store = fakeStore({
      layout = { player = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 } },
      anchors = { player = { target = "target", side = "left", align = "top", gap = 0, offset = 0 } },
    })
    local s = savedlayout.load(store)
    assert.are.same(savedlayout.DEFAULT_ANCHORS, s.anchors())
    s.setPosition("target", { x = 7, y = 8, anchorX = 0.5, anchorY = 1 })
    assert.are.equal(7, savedlayout.load(store).positions().target.x)
  end)

  it("round-trips anchors through the store, restoring floats as integers", function()
    local store = fakeStore()
    local s = savedlayout.load(store)
    s.setAnchor("player", { target = "target", side = "top", align = "left", gap = 4, offset = -3 })
    local saved = store.data.anchors.player
    saved.gap = 4.0
    saved.offset = -3.0
    local anchor = savedlayout.load(store).anchors().player
    assert.are.same({ target = "target", side = "top", align = "left", gap = 4, offset = -3 }, anchor)
    assert.are.equal("integer", math.type(anchor.gap))
  end)

  it("anchors an element added since anchors were saved by its default, until it is placed", function()
    local store = fakeStore({
      anchors = { player = { target = "rotation", side = "left", align = "bottom", gap = 0, offset = 0 } },
      layout = { target = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 } },
      version = CURRENT,
    })
    local anchors = savedlayout.load(store).anchors()
    assert.are.same(savedlayout.DEFAULT_ANCHORS.playerDebuffs, anchors.playerDebuffs)
    assert.is_nil(anchors.target)
  end)

  it("removes an anchor, keeping it removed across loads", function()
    local store = fakeStore()
    local s = savedlayout.load(store)
    s.setPosition("player", { x = 1, y = 2, anchorX = 0.5, anchorY = 1 })
    s.removeAnchor("player")
    assert.is_nil(savedlayout.load(store).anchors().player)
    assert.is_not_nil(savedlayout.load(store).anchors().target)
  end)

  it("drops saved anchors with unknown elements, sides or alignments, and cycles", function()
    local s = savedlayout.load(fakeStore({
      version = CURRENT,
      anchors = {
        player = { target = "rotation", side = "left", align = "left", gap = 0, offset = 0 },
        rotation = { target = "player", side = "under", align = "top", gap = 0, offset = 0 },
        target = { target = "target", side = "left", align = "top", gap = 0, offset = 0 },
        resource = { target = "nowhere", side = "top", align = "center", gap = 0, offset = 0 },
        major = { target = "resource", side = "top", align = "center", gap = 2.0, offset = 0 },
        bogus = { target = "player", side = "left", align = "top", gap = 0, offset = 0 },
      },
    }))
    local anchors = s.anchors()
    assert.are.same({ target = "resource", side = "top", align = "center", gap = 2, offset = 0 }, anchors.major)
    assert.is_nil(anchors.player or anchors.rotation or anchors.target or anchors.resource or anchors.bogus)
  end)

  it("resets anchors to the defaults along with positions", function()
    local s = savedlayout.load(fakeStore())
    assert.are.same(savedlayout.DEFAULT_ANCHORS, s.anchors())
    s.removeAnchor("player")
    s.setAnchor("target", { target = "player", side = "left", align = "top", gap = 0, offset = 0 })
    s.resetPositions()
    assert.are.same(savedlayout.DEFAULT_ANCHORS, s.anchors())
  end)

  it("raises the default HUD to keep the major group 31.5% of the window height above its bottom", function()
    for height, majorY in pairs({ [1041] = -328, [1440] = -454 }) do
      local positions = savedlayout.load(fakeStore(), height).positions()
      local shift = majorY - savedlayout.DEFAULT_POSITIONS.major.y
      assert.are.equal(majorY, positions.major.y)
      assert.are.equal(savedlayout.DEFAULT_POSITIONS.player.y + shift, positions.player.y)
      assert.are.equal(savedlayout.DEFAULT_POSITIONS.major.x, positions.major.x)
    end
  end)

  it("snaps by default and saves turning it off", function()
    local store = fakeStore()
    assert.is_true(savedlayout.load(store).snap())
    savedlayout.load(store).setSnap(false)
    assert.is_false(savedlayout.load(store).snap())
  end)
end)
