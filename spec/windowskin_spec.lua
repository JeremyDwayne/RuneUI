_G.log = function() end

-- Interface 1477 as the client builds it for three windows from src/windowframes: the backpack, open, with
-- sprites under its background :104, border :108 and tab strip :110 plus a label under the border, the minimap,
-- closed until open() shows it, and the main action bar's window, open. Every write and component lookup counts.
-- lock() replaces every frame sprite with a new one in the game's look, as locking the interface does.
local FRAMES = {
  { window = 103, statics = { 104, 108, 110 } },
  { window = 94, statics = { 95, 100 } },
  { window = 69, statics = { 70, 71 } },
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
      list[#list + 1] =
        proxy({ categoryID = 0, dynamicID = i, spriteID = i == 1 and -1 or 18000 + i, rgb = 0xffffff, alpha = 1 })
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
    stub.windows[frame.window] = { visibleGlobal = frame.window ~= 94 }
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
  -- Every child's field, rgb unless given, under staticID, in order.
  function stub.rgbs(staticID, field)
    local out = {}
    for _, child in ipairs(stub.statics[staticID].children) do
      out[#out + 1] = child[field or "rgb"]
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

  it("fades a window's background sprites to its opacity, leaving its border and held frames at full", function()
    local stub, windowskin = loadWindows()
    windowskin.apply(SKIN, { INVENTORY_WINDOW = 40, ACTION_WINDOW = 40 })
    assert.are.same({ 0.4, 0.4, 0.4 }, stub.rgbs(104, "alpha"))
    assert.are.same({ 1, 1, 1 }, stub.rgbs(108, "alpha"))
    assert.are.same({ 1, 1, 1 }, stub.rgbs(70, "alpha"))
  end)

  it("fades the background sprites a lock replaced, with both colours at Game", function()
    local stub, windowskin = loadWindows()
    local game = { windowFrameColour = "game", windowBackgroundColour = "game" }
    windowskin.apply(game, { INVENTORY_WINDOW = 40 })
    stub.lock()
    windowskin.onFrame()
    assert.are.same({ 0.4, 0.4, 0.4 }, stub.rgbs(104, "alpha"))
    assert.are.same({ WHITE, WHITE, WHITE }, stub.rgbs(104))
  end)

  it("puts each background sprite's own alpha back once its window is at 100 again", function()
    local stub, windowskin = loadWindows()
    stub.statics[104].children[1].alpha = 0.8
    windowskin.apply(SKIN, { INVENTORY_WINDOW = 40 })
    windowskin.apply(SKIN, {})
    assert.are.same({ 0.8, 1, 1 }, stub.rgbs(104, "alpha"))
    stub.writes = 0
    windowskin.apply(SKIN, {})
    assert.are.equal(0, stub.writes)
  end)

  it("fades each background sprite from its own alpha, leaving a hidden one hidden", function()
    local stub, windowskin = loadWindows()
    stub.statics[104].children[1].alpha = 0.5
    stub.statics[104].children[3].alpha = 0
    windowskin.apply(SKIN, { INVENTORY_WINDOW = 80 })
    assert.are.same({ 0.4, 0.8, 0 }, stub.rgbs(104, "alpha"))
    stub.writes = 0
    windowskin.onFrame()
    windowskin.apply(SKIN, { INVENTORY_WINDOW = 80 })
    assert.are.equal(0, stub.writes)
  end)

  it("tints a frame on a later tick when the client had built no sprite under it", function()
    local stub, windowskin = loadWindows()
    local built = stub.statics[104].children
    stub.statics[104].children = {}
    windowskin.apply(SKIN)
    stub.statics[104].children = built
    windowskin.apply(SKIN)
    assert.are.same({ DARK, DARK, DARK }, stub.rgbs(104))
  end)

  it("lists the open windows and those with a saved opacity, leaving out held frames", function()
    local _, windowskin = loadWindows()
    local names = {}
    for i, frame in ipairs(windowskin.listed({ CHAT_WINDOW = 40 })) do
      names[i] = frame.name
    end
    assert.are.same({ "INVENTORY_WINDOW", "CHAT_WINDOW" }, names)
  end)
end)
