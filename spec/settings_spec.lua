local fakeStore = require("spec/support/fake_store")
local savedlayout = require("src/savedlayout")
local settings = require("src/settings")

-- Saved data from this layout version, so positions and anchors in it are kept.
local CURRENT = { layout = savedlayout.LAYOUT_VERSION }
-- Saved groups that every style and Utility have been seeded into from src/presets.
local SEEDED = { utility = true, defensives = true, necromancy = true, magic = true, ranged = true, melee = true }

-- A store whose seeded groups hold groups, { [name] = saved group }.
local function seededStore(groups)
  return fakeStore({ cooldownGroups = { seeded = SEEDED, groups = groups or {} } })
end

describe("settings", function()
  it("round-trips positions, groups, markers and known abilities through the store", function()
    local store = seededStore()
    local s = settings.load(store)
    s.setPosition("player", { x = 10, y = -20, anchorX = 0.5, anchorY = 1 })
    s.add("rotation", "magic", "MAGIC_DRAGON_BREATH")
    s.setMarker("threshold", 60)
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)

    local reloaded = settings.load(store)
    assert.are.same({ x = 10, y = -20, anchorX = 0.5, anchorY = 1 }, reloaded.positions().player)
    assert.are.same({ "MAGIC_DRAGON_BREATH" }, reloaded.keys("rotation", "magic"))
    assert.are.same({}, reloaded.keys("rotation", "ranged"))
    assert.are.equal(60, reloaded.markers().threshold)
    assert.are.same({ name = "Dragon Breath", icon = 14730 }, reloaded.known().MAGIC_DRAGON_BREATH)
  end)

  it("restores whole numbers that PersistentDB returns as floats as integers", function()
    local s = settings.load(fakeStore({
      version = CURRENT,
      layout = { player = { x = -427.0, y = -429.0, anchorX = 0.5, anchorY = 1.0 } },
      known = { A = { name = "Alpha", icon = 34171.0 } },
      markers = { threshold = 55.0, ultimate = 100.0 },
    }))
    assert.are.equal("integer", math.type(s.positions().player.x))
    assert.are.equal("integer", math.type(s.known().A.icon))
    assert.are.equal("integer", math.type(s.markers().threshold))
    assert.are.equal(0.5, s.positions().player.anchorX)
  end)

  it("ignores unknown keys and malformed values in saved data", function()
    local s = settings.load(fakeStore({
      version = CURRENT,
      layout = { player = { x = "far", y = 0 }, target = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 }, bogus = {} },
      cooldownGroups = {
        seeded = SEEDED,
        groups = {
          rotation = { styles = { magic = { "A", 7 }, ranged = "nope" }, size = "big", grow = "sideways" },
          major = "broken",
          custom2 = 5,
          extra = { keys = { "Z" } },
        },
      },
      markers = { threshold = "high", ultimate = 90 },
      known = { A = { name = "Alpha", icon = 1 }, B = "broken" },
      editMode = 5,
    }))
    assert.are.same(savedlayout.DEFAULT_POSITIONS.player, s.positions().player)
    assert.are.equal(5, s.positions().target.x)
    assert.is_nil(s.positions().bogus)
    assert.are.same({ "A" }, s.keys("rotation", "magic"))
    assert.are.same({}, s.keys("rotation", "ranged"))
    assert.are.same({ 45, "down" }, { s.group("rotation").size, s.group("rotation").grow })
    assert.are.same({ "major", "rotation", "utility" }, s.groupNames())
    assert.are.same({ threshold = 50, ultimate = 90 }, s.markers())
    assert.are.same({ A = { name = "Alpha", icon = 1 } }, s.known())
    assert.is_true(s.snap())
  end)
end)
