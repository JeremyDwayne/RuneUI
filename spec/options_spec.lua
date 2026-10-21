local fake = require("spec/support/fake_ui")
local cooldowns = require("src/cooldowns")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

local function fakeStore()
  local data = {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end }
end

-- The options window over a player frame, a cooldowns row holding Sunshine, and a rotation row holding Soul
-- Sap and then Wild Magic, so magic is the current style. Opened from the ribbon.
local function openWindow()
  local root = fake.component()
  local tracker = cooldowns.tracker()
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_SUNSHINE_START", 0, 1000)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_SUNSHINE_END", 0, 1100)
  tracker.onVar("COMBATV2_COOLDOWN_NECROMANCY_SOUL_SAP_START", 0, 1000)
  tracker.onVar("COMBATV2_COOLDOWN_NECROMANCY_SOUL_SAP_END", 0, 1005)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_WILD_MAGIC_START", 0, 1001)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_WILD_MAGIC_END", 0, 1010)
  local elements = {
    player = view.playerFrame(root),
    cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns, view.tooltip(root)),
  }
  local saved = settings.load(fakeStore())
  options.create(root, {
    saved = saved, tracker = tracker, elements = elements, view = view, refresh = function() end,
  })
  fake.fire("ContentLayerReady", { component = fake.component() })
  fake.press("Open RuneUI options")
  return saved
end

local function logicTick()
  fake.fire("Logic", { logicTick = 1 })
end

local function editorTile()
  return fake.find(function(c) return fake.hasHook(c, "ONRELEASE") end)
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
    assert.are.equal(0, tile.alpha)

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
    local cx, cy = x + 45, y + 15
    assert.is_true(tile.x <= cx - 60 and tile.x + tile.width >= cx + 60)
    assert.is_true(tile.y <= cy - 60 and tile.y + tile.height >= cy + 60)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.same({ x, y }, { tile.x, tile.y })
  end)

  it("moves a tile to the row it is dropped on", function()
    local saved = openWindow()
    local tile = editorTile()
    local rotation = fake.find(function(_, d) return d.content == "Rotation" end)
    fake.mouse.x, fake.mouse.y = 500, 300
    fake.hook(tile, "ONCLICK", 5, 5)
    fake.mouse.y = 300 + rotation.y + 32 - (tile.y + 5)
    logicTick()
    fake.hook(tile, "ONRELEASE")
    local groups = saved.groups()
    assert.are.same({ {}, "MAGIC_SUNSHINE" }, { groups.cooldowns, groups.rotation[1] })
  end)

  it("opens the picker on the current combat style's tab and switches style by tab", function()
    openWindow()
    fake.press("+")
    local function listed(name) return fake.find(function(_, d) return d.content == name end) ~= nil end
    assert.are.same({ true, false }, { listed("Wild Magic"), listed("Soul Sap") })
    fake.press("Necromancy")
    assert.are.same({ false, true }, { listed("Wild Magic"), listed("Soul Sap") })
    fake.press("All")
    assert.are.same({ true, true }, { listed("Wild Magic"), listed("Soul Sap") })
  end)

  it("lists abilities matching the picker search from every style, leaving the All tab chosen", function()
    openWindow()
    fake.press("+")
    local search = fake.find(function(c) return fake.hasHook(c, "ONCONTENTCHANGED") end)
    local function listed(name) return fake.find(function(_, d) return d.content == name end) ~= nil end
    fake.hook(search, "ONCONTENTCHANGED", 0, "soul")
    assert.are.same({ false, true }, { listed("Wild Magic"), listed("Soul Sap") })
    fake.hook(search, "ONCONTENTCHANGED", 0, "")
    assert.are.same({ true, true }, { listed("Wild Magic"), listed("Soul Sap") })
  end)

  it("says when no ability matches the picker search", function()
    openWindow()
    fake.press("+")
    local search = fake.find(function(c) return fake.hasHook(c, "ONCONTENTCHANGED") end)
    fake.hook(search, "ONCONTENTCHANGED", 0, "zzz")
    assert.is_not_nil(fake.find(function(_, d) return d.content == "No ability matches" end))
  end)

  it("closes the picker when the reset dialog opens", function()
    openWindow()
    fake.press("+")
    fake.press("Reset positions")
    assert.is_nil(fake.find(function(_, d) return d.content == "Wild Magic" end))
  end)

  it("ignores a search event that arrives after the picker closed", function()
    openWindow()
    fake.press("+")
    local search = fake.find(function(c) return fake.hasHook(c, "ONCONTENTCHANGED") end)
    fake.hook(search, "ONCONTENTCHANGED", 0, "soul")
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.has_no.errors(function() fake.hook(search, "ONCONTENTCHANGED", 4, "soul") end)
  end)

  it("makes no client writes while a tile drag is held still", function()
    openWindow()
    fake.mouse.x, fake.mouse.y = 500, 300
    fake.hook(editorTile(), "ONCLICK", 5, 5)
    fake.mouse.x = 540
    logicTick()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)
  end)
end)
