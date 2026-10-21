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
end)
