local fake = require("spec/support/fake_ui")
local cooldowns = require("src/cooldowns")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

local function fakeStore()
  local data = {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end }
end

-- Edit mode over every HUD element with default settings, entered from the options window. Returns the
-- elements by name.
local function enterEditMode()
  local root = fake.component()
  local tooltip = view.tooltip(root)
  local elements = {
    player = view.playerFrame(root),
    target = view.targetFrame(root, tooltip, function() end),
    resource = view.resourceBar(root),
    rotation = view.cooldownGroup(root, view.TILE_STYLES.rotation, tooltip),
    cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns, tooltip),
  }
  options.create(root, {
    saved = settings.load(fakeStore()), tracker = cooldowns.tracker(), elements = elements, view = view,
    refresh = function() end,
  })
  fake.fire("ContentLayerReady", { component = fake.component() })
  fake.press("Open RuneUI options")
  fake.press("Edit mode off")
  return elements
end

local function logicTick()
  fake.fire("Logic", { logicTick = 1 })
end

-- The overlay hit area over element.
local function overlayOf(element)
  return fake.find(function(c, d)
    return fake.hasHook(c, "ONRELEASE") and d.width == element.width and d.height == element.height
  end)
end

-- Presses element's overlay with the cursor at 300, 300.
local function grab(element)
  local tint = overlayOf(element)
  fake.mouse.x, fake.mouse.y = 300, 300
  fake.hook(tint, "ONCLICK")
  return tint
end

describe("edit mode", function()
  before_each(fake.reset)

  it("resets positions only once the dialog is confirmed", function()
    local elements = enterEditMode()
    local layer = elements.player.layer
    local x = layer.x
    local tint = grab(elements.player)
    fake.mouse.x = 350
    logicTick()
    fake.hook(tint, "ONRELEASE")

    fake.press("Reset positions")
    fake.press("Cancel")
    assert.are.equal(x + 50, layer.x)
    fake.press("Reset positions")
    fake.press("Reset positions", 3)
    assert.are.equal(x, layer.x)
    assert.is_nil(fake.find(function(_, d) return d.content == "Cancel" end))
  end)

  it("puts a moved element back on Esc", function()
    local elements = enterEditMode()
    local layer = elements.player.layer
    local x, y = layer.x, layer.y
    grab(elements.player)
    fake.mouse.x = 350
    logicTick()
    assert.are.equal(x + 50, layer.x)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.same({ x, y }, { layer.x, layer.y })
    fake.writes = 0
    fake.mouse.x = 400
    logicTick()
    assert.are.equal(0, fake.writes)
  end)

  it("moves an element by the cursor's UI distance when the mouse reports physical pixels", function()
    local elements = enterEditMode()
    local layer = elements.player.layer
    local x = layer.x
    local tint = overlayOf(elements.player)
    tint.xyGlobal = { x = 150, y = 150 }
    fake.mouse.x, fake.mouse.y = 300, 300
    fake.hook(tint, "ONCLICK")
    fake.mouse.x = 400
    logicTick()
    assert.are.equal(x + 50, layer.x)
  end)

  it("makes no client writes while a move is held still", function()
    local elements = enterEditMode()
    grab(elements.player)
    fake.mouse.x = 350
    logicTick()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)
  end)
end)
