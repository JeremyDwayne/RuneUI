_G.log = function() end
_G.id = { Font = {} }

-- Client components as stand-ins that count property writes and Set, Add, Clear and MoveToFront calls.
local writes = 0
local function component()
  local data = {}
  local function call(method)
    return function(_, x, y)
      if method:match("^Set") or method:match("^Add") or method == "Clear" or method == "MoveToFront" then
        writes = writes + 1
      end
      if method == "SetPos" then data.x, data.y = x, y end
    end
  end
  return setmetatable({}, {
    __index = function(_, key)
      if data[key] ~= nil then return data[key] end
      return call(key)
    end,
    __newindex = function(_, key, value)
      writes = writes + 1
      data[key] = value
    end,
  })
end
local constructor = { new = component }
_G.ui = {
  Layer = constructor, Rectangle = constructor, Text = constructor, Sprite = constructor, Canvas = constructor,
  Hook = setmetatable({}, { __index = function(_, name) return name end }),
  AlignMode = { TOPLEFT = 0, CENTRE = 1, BOTTOMRIGHT = 2 },
}

local view = require("src/view")

describe("view", function()
  it("makes no client writes when a cooldown group redraws unchanged tiles", function()
    local group = view.cooldownGroup(component(), view.TILE_STYLES.rotation, view.tooltip(component()))
    local tiles = {
      { key = "MAGIC_SUNSHINE", name = "Sunshine", initials = "SUN", ready = true },
      { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, keybind = "Q", seconds = 4 },
    }
    group.update(tiles, 0x2f7fd6)
    writes = 0
    group.update(tiles, 0x2f7fd6)
    assert.are.equal(0, writes)
  end)

  it("makes no client writes when the tooltip is shown again at the same icon", function()
    local tooltip = view.tooltip(component())
    local content = { title = "Sunshine", left = "Cooldown 60s", line = "Ready" }
    tooltip.show(content, 100, 300, 42)
    writes = 0
    tooltip.show(content, 100, 300, 42)
    assert.are.equal(0, writes)
  end)
end)
