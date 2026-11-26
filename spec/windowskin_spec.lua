_G.log = function() end

-- Interface 1477 as the client builds it for two windows from src/windowframes: the backpack, open, with sprites
-- under its background :104, border :108 and tab strip :110 plus a label under the border, and the minimap,
-- closed until open() shows it. Every rgb write and component lookup counts. lock() replaces every frame sprite
-- with a new untinted one, as locking the interface does.
local FRAMES = {
  { window = 103, statics = { 104, 108, 110 } },
  { window = 94, statics = { 95, 100 } },
}

local function loadWindows()
  local stub = { writes = 0, lookups = 0, statics = {}, windows = {} }
  local function proxy(data)
    return setmetatable({}, {
      __index = data,
      __newindex = function(_, key, value)
        stub.writes = stub.writes + 1
        data[key] = value
      end,
    })
  end
  local function children(staticID)
    local list = {}
    for i = 0, 2 do
      list[#list + 1] = proxy({ categoryID = 0, dynamicID = i, spriteID = i == 1 and -1 or 18000 + i, rgb = 0xffffff })
    end
    if staticID == 108 then
      list[#list + 1] = proxy({ categoryID = 0, dynamicID = 3, rgb = 0xffffff })
    end
    return list
  end
  function stub.lock()
    for _, frame in ipairs(FRAMES) do
      for _, staticID in ipairs(frame.statics) do
        stub.statics[staticID].children = children(staticID)
      end
    end
  end
  for _, frame in ipairs(FRAMES) do
    stub.windows[frame.window] = { visibleGlobal = frame.window == 103 }
    for _, staticID in ipairs(frame.statics) do
      local data = { children = children(staticID) }
      function data.IterateDynamicComponents(_, fn)
        for _, child in ipairs(data.children) do
          fn(child)
        end
      end
      stub.statics[staticID] = data
    end
  end
  function stub.open()
    stub.windows[94].visibleGlobal = true
  end
  -- Every sprite's rgb under staticID, in order.
  function stub.rgbs(staticID)
    local out = {}
    for _, child in ipairs(stub.statics[staticID].children) do
      out[#out + 1] = child.rgb
    end
    return out
  end
  _G.ui = {
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID, _, dynamicID)
        stub.lookups = stub.lookups + 1
        if interfaceID ~= 1477 then
          return nil
        end
        if stub.windows[staticID] then
          return stub.windows[staticID]
        end
        local data = stub.statics[staticID]
        if data and dynamicID ~= nil then
          return data.children[dynamicID + 1]
        end
        return data
      end,
    },
  }
  package.loaded["src/windowskin"] = nil
  return stub, require("src/windowskin")
end

local BLUE, DARK, WHITE = 0x3a8dde, 0x404040, 0xffffff
local SKIN = { windowFrameColour = "blue", windowBackgroundColour = "dark" }

describe("windowskin", function()
  it("tints every sprite under an open window's frame, leaving labels and closed windows alone", function()
    local stub, windowskin = loadWindows()
    windowskin.apply(SKIN)
    assert.are.same({ DARK, DARK, DARK }, stub.rgbs(104))
    assert.are.same({ BLUE, BLUE, BLUE, WHITE }, stub.rgbs(108))
    assert.are.same({ BLUE, BLUE, BLUE }, stub.rgbs(110))
    assert.are.same({ WHITE, WHITE, WHITE }, stub.rgbs(100))
  end)

  it("takes a custom colour and leaves the game's colours for Game", function()
    local stub, windowskin = loadWindows()
    windowskin.apply({ windowFrameColour = 0x123456, windowBackgroundColour = "game" })
    assert.are.same({ 0x123456, 0x123456, 0x123456, WHITE }, stub.rgbs(108))
    assert.are.same({ WHITE, WHITE, WHITE }, stub.rgbs(104))
  end)

  it("retints the sprites a lock replaced on the next rendered frame, then reads one sprite a frame", function()
    local stub, windowskin = loadWindows()
    windowskin.apply(SKIN)
    stub.lock()
    windowskin.onFrame()
    assert.are.same({ DARK, DARK, DARK }, stub.rgbs(104))
    assert.are.same({ BLUE, BLUE, BLUE, WHITE }, stub.rgbs(108))
    stub.writes, stub.lookups = 0, 0
    windowskin.onFrame()
    assert.are.same({ 0, 1 }, { stub.writes, stub.lookups })
  end)

  it("tints a window that opens on the next server tick", function()
    local stub, windowskin = loadWindows()
    windowskin.apply(SKIN)
    stub.open()
    windowskin.apply(SKIN)
    assert.are.same({ BLUE, BLUE, BLUE }, stub.rgbs(100))
    assert.are.same({ DARK, DARK, DARK }, stub.rgbs(95))
  end)

  it("makes no writes on a steady tick or frame", function()
    local stub, windowskin = loadWindows()
    windowskin.apply(SKIN)
    stub.writes = 0
    windowskin.apply(SKIN)
    windowskin.onFrame()
    assert.are.equal(0, stub.writes)
  end)

  it("reads nothing with both colours at Game", function()
    local stub, windowskin = loadWindows()
    windowskin.apply({ windowFrameColour = "game", windowBackgroundColour = "game" })
    windowskin.onFrame()
    assert.are.same({ 0, 0 }, { stub.writes, stub.lookups })
  end)

  it("writes the game's look back to every tinted frame on restore, closed ones too", function()
    local stub, windowskin = loadWindows()
    stub.open()
    windowskin.apply(SKIN)
    stub.windows[94].visibleGlobal = false
    windowskin.restore()
    for _, staticID in ipairs({ 104, 110, 95, 100 }) do
      assert.are.same({ WHITE, WHITE, WHITE }, stub.rgbs(staticID))
    end
    stub.lookups = 0
    windowskin.onFrame()
    assert.are.equal(0, stub.lookups)
  end)
end)
