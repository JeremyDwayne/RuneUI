local settings = require("src/settings")

-- An in-memory stand-in for src/adapter's PersistentDB store that counts writes.
local function fakeStore(data)
  local store = { data = data or {}, writes = 0 }
  function store.get(key) return store.data[key] end
  function store.set(key, value)
    store.writes = store.writes + 1
    store.data[key] = value
  end
  return store
end

local function edited()
  local s = settings.load(fakeStore())
  s.adopt({ rotation = { "A", "B", "C" }, cooldowns = { "X", "Y" } })
  return s
end

describe("settings", function()
  it("round-trips positions, groups, markers and known abilities through the store", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.setPosition("player", { x = 10, y = -20, anchorX = 0.5, anchorY = 1 })
    s.adopt({ rotation = { "MAGIC_DRAGON_BREATH" }, cooldowns = {} })
    s.setMarker("threshold", 60)
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)

    local reloaded = settings.load(store)
    assert.are.same({ x = 10, y = -20, anchorX = 0.5, anchorY = 1 }, reloaded.positions().player)
    assert.are.same({ rotation = { "MAGIC_DRAGON_BREATH" }, cooldowns = {} }, reloaded.groups())
    assert.are.equal(60, reloaded.markers().threshold)
    assert.are.same({ name = "Dragon Breath", icon = 14730 }, reloaded.known().MAGIC_DRAGON_BREATH)
  end)

  it("has no groups until some are adopted, so the caller can fill them automatically", function()
    local s = settings.load(fakeStore())
    assert.is_nil(s.groups())
    s.adopt({ rotation = { "A" }, cooldowns = {} })
    s.adopt({ rotation = { "B" }, cooldowns = {} })
    assert.are.same({ "A" }, s.groups().rotation)
  end)

  it("resets positions to the defaults and keeps groups", function()
    local s = edited()
    s.setPosition("player", { x = 1, y = 2, anchorX = 0, anchorY = 0 })
    s.resetPositions()
    assert.are.same(settings.DEFAULT_POSITIONS.player, s.positions().player)
    assert.are.same({ "A", "B", "C" }, s.groups().rotation)
  end)

  it("adds to the end of a group, taking the ability out of the other group", function()
    local s = edited()
    s.add("rotation", "X")
    assert.are.same({ "A", "B", "C", "X" }, s.groups().rotation)
    assert.are.same({ "Y" }, s.groups().cooldowns)
  end)

  it("removes an ability from whichever group holds it", function()
    local s = edited()
    s.remove("B")
    assert.are.same({ "A", "C" }, s.groups().rotation)
  end)

  it("moves an ability to an index within its group or into the other group", function()
    local s = edited()
    s.move("C", "rotation", 1)
    assert.are.same({ "C", "A", "B" }, s.groups().rotation)
    s.move("A", "cooldowns", 2)
    assert.are.same({ "C", "B" }, s.groups().rotation)
    assert.are.same({ "X", "A", "Y" }, s.groups().cooldowns)
  end)

  it("swaps two abilities, across groups too", function()
    local s = edited()
    s.swap("A", "Y")
    assert.are.same({ "Y", "B", "C" }, s.groups().rotation)
    assert.are.same({ "X", "A" }, s.groups().cooldowns)
  end)

  it("keeps debuff names by icon across loads, dropping malformed entries", function()
    local store = fakeStore({ debuffs = { ["1"] = "broken" } })
    settings.load(store).learnDebuff(30098, "Bloated", "Swollen from the inside.")
    assert.are.same({ ["30098"] = { name = "Bloated", info = "Swollen from the inside." } },
      settings.load(store).debuffs())
  end)

  it("saves a learned ability only when its name or icon changed", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)
    local writes = store.writes
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)
    assert.are.equal(writes, store.writes)
  end)

  it("clamps marker percents to 0 through 100", function()
    local s = settings.load(fakeStore())
    s.setMarker("ultimate", 150)
    s.setMarker("threshold", -5)
    assert.are.same({ threshold = 0, ultimate = 100 }, s.markers())
  end)

  it("keeps bars flat until a known texture is chosen, and saves the choice", function()
    local store = fakeStore()
    assert.are.equal("flat", settings.load(store).texture())
    settings.load(store).setTexture("vertical")
    assert.are.equal("vertical", settings.load(store).texture())
    assert.are.equal("flat", settings.load(fakeStore({ appearance = { texture = "plaid" } })).texture())
  end)

  it("shows the default target panel until hiding is chosen, keeping the texture beside it", function()
    local store = fakeStore()
    assert.is_false(settings.load(store).hideTargetPanel())
    local s = settings.load(store)
    s.setTexture("horizontal")
    s.setHideTargetPanel(true)
    local reloaded = settings.load(store)
    assert.is_true(reloaded.hideTargetPanel())
    assert.are.equal("horizontal", reloaded.texture())
  end)

  it("restores whole numbers that PersistentDB returns as floats as integers", function()
    local s = settings.load(fakeStore({
      layout = { player = { x = -427.0, y = -429.0, anchorX = 0.5, anchorY = 1.0 } },
      known = { A = { name = "Alpha", icon = 34171.0 } },
    }))
    assert.are.equal("integer", math.type(s.positions().player.x))
    assert.are.equal("integer", math.type(s.known().A.icon))
    assert.are.equal(0.5, s.positions().player.anchorX)
  end)

  it("ignores unknown keys and malformed values in saved data", function()
    local s = settings.load(fakeStore({
      layout = { player = { x = "far", y = 0 }, target = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 }, bogus = {} },
      groups = { rotation = { "A", 7 }, cooldowns = "nope", extra = { "Z" } },
      markers = { threshold = "high", ultimate = 90 },
      known = { A = { name = "Alpha", icon = 1 }, B = "broken" },
    }))
    assert.are.same(settings.DEFAULT_POSITIONS.player, s.positions().player)
    assert.are.equal(5, s.positions().target.x)
    assert.is_nil(s.positions().bogus)
    assert.are.same({ rotation = { "A" }, cooldowns = {} }, s.groups())
    assert.are.same({ threshold = 50, ultimate = 90 }, s.markers())
    assert.are.same({ A = { name = "Alpha", icon = 1 } }, s.known())
  end)
end)
