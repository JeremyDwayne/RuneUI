_G.id = { Font = {} }
_G.log = function() end
local draw = require("src/draw")

-- A component stand-in that counts property writes and SetPos calls.
local function fakeComponent()
  local writes = { props = 0, pos = 0 }
  local c = { writes = writes }
  function c.SetPos() writes.pos = writes.pos + 1 end
  return setmetatable(c, { __newindex = function() writes.props = writes.props + 1 end })
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

  it("retries a write the client refused", function()
    local attempts = 0
    local c = setmetatable({}, { __newindex = function()
      attempts = attempts + 1
      error("refused")
    end })
    draw.set(c, "rgb", 1)
    draw.set(c, "rgb", 1)
    assert.are.equal(2, attempts)
  end)
end)
