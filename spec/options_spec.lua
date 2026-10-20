local fake = require("spec/support/fake_ui")
local cooldowns = require("src/cooldowns")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

local function fakeStore()
  local data = {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end }
end

-- The options window over a player frame and a cooldowns row holding one known ability, opened from the
-- ribbon. Returns the HUD elements.
local function openWindow()
  local root = fake.component()
  local tracker = cooldowns.tracker()
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_SUNSHINE_START", 0, 1000)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_SUNSHINE_END", 0, 1100)
  local elements = {
    player = view.playerFrame(root),
    cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns, view.tooltip(root)),
  }
  options.create(root, {
    saved = settings.load(fakeStore()), tracker = tracker, elements = elements, view = view, refresh = function() end,
  })
  fake.fire("ContentLayerReady", { component = fake.component() })
  fake.press("Open RuneUI options")
  return elements
end

local function logicTick()
  fake.fire("Logic", { logicTick = 1 })
end

local function editorTile()
  return fake.find(function(c) return fake.hasHook(c, "ONRELEASE") end)
end

-- Starts moving the player frame in edit mode with the cursor at 300, 300.
local function grabPlayer(elements)
  fake.press("Edit mode off")
  local frame = elements.player
  local tint = fake.find(function(c, d)
    return fake.hasHook(c, "ONRELEASE") and d.width == frame.width and d.height == frame.height
  end)
  fake.mouse.x, fake.mouse.y = 300, 300
  fake.hook(tint, "ONCLICK")
end

describe("options", function()
  before_each(fake.reset)

  it("cancels a tile drag on Esc, restoring the tile and leaving the logic tick idle", function()
    openWindow()
    local tile = editorTile()
    fake.mouse.x, fake.mouse.y = 500, 300
    fake.hook(tile, "ONCLICK", 5, 5)
    fake.mouse.x = 540
    logicTick()
    assert.are.equal(0.3, tile.alpha)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.equal(1, tile.alpha)
    fake.writes = 0
    fake.mouse.x = 600
    logicTick()
    assert.are.equal(0, fake.writes)
  end)

  it("keeps the pressed tile under the cursor during a drag so the client does not release it", function()
    openWindow()
    local tile = editorTile()
    local x, y = tile.x, tile.y
    fake.mouse.x, fake.mouse.y = 500, 300
    fake.hook(tile, "ONCLICK", 5, 5)
    fake.mouse.x, fake.mouse.y = 540, 310
    logicTick()
    assert.are.same({ x + 40, y + 10 }, { tile.x, tile.y })

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.same({ x, y }, { tile.x, tile.y })
  end)

  it("puts a moved element back on Esc in edit mode", function()
    local elements = openWindow()
    local layer = elements.player.layer
    local x, y = layer.x, layer.y
    grabPlayer(elements)
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
    local elements = openWindow()
    local layer = elements.player.layer
    local x = layer.x
    fake.press("Edit mode off")
    local tint = fake.find(function(c, d)
      return fake.hasHook(c, "ONRELEASE") and d.width == elements.player.width
    end)
    tint.xyGlobal = { x = 150, y = 150 }
    fake.mouse.x, fake.mouse.y = 300, 300
    fake.hook(tint, "ONCLICK")
    fake.mouse.x = 400
    logicTick()
    assert.are.equal(x + 50, layer.x)
  end)

  it("makes no client writes while a drag or a move is held still", function()
    local elements = openWindow()
    fake.mouse.x, fake.mouse.y = 500, 300
    fake.hook(editorTile(), "ONCLICK", 5, 5)
    fake.mouse.x = 540
    logicTick()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    fake.press("Open RuneUI options")
    grabPlayer(elements)
    fake.mouse.x = 350
    logicTick()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)
  end)
end)
