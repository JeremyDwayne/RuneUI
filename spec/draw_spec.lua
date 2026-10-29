local fake = require("spec/support/fake_ui")
local draw = require("src/draw")

-- A component stand-in that counts property writes and SetPos calls.
local function fakeComponent()
  local writes = { props = 0, pos = 0 }
  local c = { writes = writes }
  function c.SetPos()
    writes.pos = writes.pos + 1
  end
  return setmetatable(c, {
    __newindex = function()
      writes.props = writes.props + 1
    end,
  })
end

describe("draw", function()
  it("skips a property write or move when the value is unchanged", function()
    local c = fakeComponent()
    draw.set(c, "hidden", true)
    draw.set(c, "hidden", true)
    draw.set(c, "hidden", false)
    draw.pos(c, 4, 8)
    draw.pos(c, 4, 8)
    draw.pos(c, 5, 8)
    draw.place(c, 5, 8, 0.5, 1)
    draw.place(c, 5, 8, 0.5, 1)
    draw.place(c, 5, 8, 0.5, 0)
    assert.are.same({ props = 2, pos = 4 }, c.writes)
  end)

  it("shows an aura icon as a sprite, or as an item for minus its id, skipping an unchanged icon", function()
    local calls = {}
    local c = setmetatable({
      SetAssociatedObject = function(_, objID)
        calls[#calls + 1] = "object=" .. objID
      end,
    }, {
      __newindex = function(_, k, v)
        calls[#calls + 1] = k .. "=" .. v
      end,
    })
    draw.icon(c, 30099)
    draw.icon(c, -49039)
    draw.icon(c, -49039)
    draw.icon(c, 30099)
    assert.are.same({ "sprite=30099", "object=49039", "object=-1", "sprite=30099" }, calls)
  end)

  it("retries a write the client refused", function()
    local attempts = 0
    local c = setmetatable({}, {
      __newindex = function()
        attempts = attempts + 1
        error("refused")
      end,
    })
    draw.set(c, "rgb", 1)
    draw.set(c, "rgb", 1)
    assert.are.equal(2, attempts)
  end)

  it("mirrors a changed label to its edge copies only while the edge is on", function()
    fake.reset()
    local parent = fake.component()
    local label = draw.edgedText(parent, draw.FONTS.body, ui.AlignMode.TOPLEFT, 10, 20, 50, 16)
    local function copies(predicate)
      local n = 0
      for _, c in ipairs(fake.created) do
        if c ~= label and c.parent == parent and fake.shown(c) and predicate(c) then
          n = n + 1
        end
      end
      return n
    end
    fake.writes = 0
    draw.set(label, "content", "1")
    assert.are.equal(1, fake.writes)
    assert.are.equal(
      0,
      copies(function()
        return true
      end)
    )

    draw.setEdge(label, 0x000000)
    assert.are.equal(
      4,
      copies(function(c)
        return c.content == "1" and c.rgb == 0x000000
      end)
    )
    assert.are.equal(
      1,
      copies(function(c)
        return c.x == 9 and c.y == 19
      end)
    )
    fake.writes = 0
    draw.set(label, "content", "2")
    draw.set(label, "content", "2")
    draw.setEdge(label, 0x000000)
    assert.are.equal(5, fake.writes)
    draw.pos(label, 30, 40)
    assert.are.equal(
      1,
      copies(function(c)
        return c.content == "2" and c.x == 31 and c.y == 41
      end)
    )

    draw.setEdge(label, nil)
    assert.are.equal(
      0,
      copies(function()
        return true
      end)
    )
    fake.writes = 0
    draw.set(label, "content", "3")
    assert.are.equal(1, fake.writes)
  end)

  it("repaints a gradient bar once when it changes size", function()
    fake.reset()
    local parent = fake.component()
    local bar = draw.bar(parent, 0x2f63a8, 0x111111, 1, 1, 100, 20)
    bar.setTexture("vertical")
    bar.setFill(0.5)
    fake.writes = 0
    bar.setBox(1, 1, 200, 30)
    local canvas = fake.find(function(_, d)
      return d.width == 200 and d.height == 30 and d.hooks
    end)
    assert.is_not_nil(canvas)
    local writes = fake.writes
    bar.setBox(1, 1, 200, 30)
    assert.are.equal(writes, fake.writes)
    local cover = fake.find(function(_, d)
      return d.x == 101 and d.width == 100 and d.height == 30
    end)
    assert.is_not_nil(cover)
  end)

  it("holds holdable layers hidden and gives each its own state back on release", function()
    local shown, empty, other = {}, {}, {}
    draw.set(empty, "hidden", true)
    draw.holdable(shown)
    draw.holdable(empty)
    draw.set(shown, "hidden", false)
    draw.hold(true)
    assert.is_true(shown.hidden)
    assert.is_true(empty.hidden)
    draw.set(other, "hidden", false)
    assert.is_false(other.hidden)
    -- An element showing a layer while it is held leaves it hidden until the release.
    draw.set(empty, "hidden", false)
    assert.is_true(empty.hidden)
    draw.hold(false)
    assert.is_false(shown.hidden)
    assert.is_false(empty.hidden)
  end)

  it("writes nothing while the hold is unchanged", function()
    local c = fakeComponent()
    draw.holdable(c)
    draw.set(c, "hidden", false)
    draw.hold(true)
    draw.hold(true)
    draw.set(c, "hidden", false)
    draw.hold(false)
    draw.hold(false)
    assert.are.same({ props = 3, pos = 0 }, c.writes)
  end)

  describe("fade", function()
    after_each(function()
      draw.fade(1)
    end)

    -- A holdable layer on a root, with a rect at alpha 0.5 and a label on a layer under it, and a rect on
    -- another layer of the root.
    local function layers()
      fake.reset()
      local root = fake.component()
      local layer = fake.component(root)
      draw.holdable(layer)
      local rect = draw.rect(layer, 0, 0, 0, 10, 10)
      draw.set(rect, "alpha", 0.5)
      local label = draw.text(draw.new(ui.Layer, layer), draw.FONTS.body, ui.AlignMode.TOPLEFT, 0, 0, 10, 10)
      local outside = draw.rect(fake.component(root), 0, 0, 0, 10, 10)
      return rect, label, outside
    end

    it("fades every component built on a holdable layer by its own alpha, and restores it at full", function()
      local rect, label, outside = layers()
      draw.fade(0.3)
      assert.is_near(0.15, rect.alpha, 1e-9)
      assert.is_near(0.3, label.alpha, 1e-9)
      assert.is_nil(outside.alpha)
      -- An element setting an alpha while faded gets it scaled.
      draw.set(rect, "alpha", 0.8)
      assert.is_near(0.24, rect.alpha, 1e-9)
      draw.set(outside, "alpha", 0.8)
      assert.are.equal(0.8, outside.alpha)
      draw.fade(1)
      assert.are.same({ 0.8, 1, 0.8 }, { rect.alpha, label.alpha, outside.alpha })
    end)

    it("fades a component built on a holdable layer while faded, as a tile's queued border is", function()
      local _, label = layers()
      draw.fade(0.3)
      local late = draw.rect(label, 0, 0, 0, 10, 10)
      local outside = draw.rect(fake.component(), 0, 0, 0, 10, 10)
      assert.is_near(0.3, late.alpha, 1e-9)
      assert.is_nil(outside.alpha)
      draw.fade(1)
      assert.are.equal(1, late.alpha)
    end)

    it("writes nothing while the fade is unchanged and an element sets the same alpha again", function()
      local rect = layers()
      draw.fade(0.3)
      fake.writes = 0
      draw.fade(0.3)
      draw.set(rect, "alpha", 0.5)
      assert.are.equal(0, fake.writes)
    end)

    it("fades a label's edge copies by the label's own alpha, as the edge turns on while faded", function()
      fake.reset()
      local layer = fake.component(fake.component())
      draw.holdable(layer)
      local label = draw.edgedText(layer, draw.FONTS.body, ui.AlignMode.TOPLEFT, 0, 0, 10, 10)
      draw.set(label, "alpha", 0.5)
      draw.fade(0.5)
      draw.setEdge(label, 0x000000)
      draw.set(label, "content", "1")
      local copies = {}
      for _, c in ipairs(fake.created) do
        if c ~= label and c.content == "1" then
          copies[#copies + 1] = c
        end
      end
      assert.are.equal(4, #copies)
      for _, copy in ipairs(copies) do
        assert.are.equal(0.25, copy.alpha)
      end
      draw.set(label, "alpha", 1)
      draw.fade(1)
      for _, copy in ipairs(copies) do
        assert.are.equal(1, copy.alpha)
      end
      assert.are.equal(1, label.alpha)
    end)
  end)

  it("builds a stand-in for a refused create, which takes writes, calls and children without the client", function()
    fake.reset()
    local logged = 0
    local realLog = _G.log
    _G.log = function()
      logged = logged + 1
    end
    local root = fake.component()
    fake.limit = 1
    draw.new(ui.Layer, root)
    assert.is_false(draw.refused())
    local layer = draw.new(ui.Layer, root)
    draw.set(layer, "hidden", true)
    layer:SetPos(4, 8)
    local child = draw.rect(layer, draw.COLOURS.border, 0, 0, 10, 10)
    draw.on(child, "ONCLICK", function() end)
    draw.new(ui.Rectangle, root)
    _G.log = realLog
    assert.is_true(draw.refused())
    assert.is_false(draw.refused())
    assert.are.equal(1, fake.live(root))
    assert.are.equal(1, logged)
  end)
end)
