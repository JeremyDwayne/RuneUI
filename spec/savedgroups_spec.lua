local fakeStore = require("spec/support/fake_store")
local presets = require("src/presets")
local savedgroups = require("src/savedgroups")

-- The position of key in list, or nil.
local function indexOfKey(list, key)
  for i, k in ipairs(list) do
    if k == key then
      return i
    end
  end
end

-- Saved groups that every style and Utility have been seeded into from src/presets.
local SEEDED = { utility = true, defensives = true, necromancy = true, magic = true, ranged = true, melee = true }

-- A store whose seeded groups hold groups, { [name] = saved group }.
local function seededStore(groups)
  return fakeStore({ cooldownGroups = { seeded = SEEDED, groups = groups or {} } })
end

-- Magic's major holds X and Y and its rotation A, B and C; the shared utility holds U.
local function edited()
  return savedgroups.load(seededStore({
    major = { styles = { magic = { "X", "Y" } } },
    rotation = { styles = { magic = { "A", "B", "C" } } },
    utility = { keys = { "U" } },
  }))
end

describe("savedgroups", function()
  it("loads a second charge's or recast stage's saved key as its ability's, keeping one of each", function()
    local s = savedgroups.load(seededStore({
      utility = { keys = { "MAGIC_SURGE_CHARGE2", "MAGIC_SURGE", "RANGED_ESCAPE_CHARGE2" } },
    }))
    assert.are.same({ "MAGIC_SURGE", "RANGED_ESCAPE" }, s.keys("utility", "magic"))
  end)

  it("loads a name saved under a second charge as its ability's and drops one saved under a recast stage", function()
    local s = savedgroups.load(fakeStore({
      known = {
        MAGIC_SURGE_CHARGE2 = { name = "Surge", icon = 14233 },
        MELEE_DISMEMBER_RECAST_2 = { name = "Slaughter", icon = 21362 },
      },
    }))
    assert.are.same({ MAGIC_SURGE = { name = "Surge", icon = 14233 } }, s.known())
  end)

  it("fills every style and Utility from the presets on the first load", function()
    local s = savedgroups.load(fakeStore())
    for style, lists in pairs(presets.STYLES) do
      assert.are.same(lists.major, s.keys("major", style), style)
      assert.are.same(lists.rotation, s.keys("rotation", style), style)
    end
    assert.are.same(presets.UTILITY, s.keys("utility", "melee"))
  end)

  it("fills only styles with nothing in them, once, so a style emptied on purpose stays empty", function()
    local store = fakeStore({ cooldownGroups = { groups = { rotation = { styles = { magic = { "A" } } } } } })
    local s = savedgroups.load(store)
    assert.are.same({ { "A" }, {} }, { s.keys("rotation", "magic"), s.keys("major", "magic") })
    assert.are.same(presets.STYLES.ranged.rotation, s.keys("rotation", "ranged"))
    for _, key in ipairs(presets.STYLES.ranged.rotation) do
      s.remove(key, "ranged")
    end
    assert.are.same({}, savedgroups.load(store).keys("rotation", "ranged"))
  end)

  it("leaves a preset ability out of a style where another list already shows it", function()
    local s = savedgroups.load(fakeStore({
      cooldownGroups = {
        seeded = { utility = true },
        groups = {
          utility = { keys = { "MAGIC_SUNSHINE" } },
        },
      },
    }))
    local major = { table.unpack(presets.STYLES.magic.major, 2) }
    assert.are.equal("MAGIC_SUNSHINE", presets.STYLES.magic.major[1])
    assert.are.same(major, s.keys("major", "magic"))
    assert.are.same({ "MAGIC_SUNSHINE" }, s.keys("utility", "magic"))
  end)

  it("shows a per-style group as empty until a style is known", function()
    assert.are.same({}, savedgroups.load(fakeStore()).keys("major", nil))
  end)

  it("adds to the end of a style's list, taking the ability out of every list shown with that style", function()
    local s = edited()
    s.add("rotation", "magic", "X")
    s.add("rotation", "magic", "U")
    assert.are.same({ "A", "B", "C", "X", "U" }, s.keys("rotation", "magic"))
    assert.are.same({ "Y" }, s.keys("major", "magic"))
    assert.are.same({}, s.keys("utility", "ranged"))
    assert.are.same({}, s.keys("rotation", "ranged"))
  end)

  it("refuses an ability once a list holds 20", function()
    local s = edited()
    for i = 1, 17 do
      assert.is_true(s.add("rotation", "magic", "K" .. i))
    end
    assert.is_false(s.add("rotation", "magic", "X"))
    assert.are.same({ "X", "Y" }, s.keys("major", "magic"))
  end)

  it("removes an ability from whichever list holds it for that style", function()
    local s = edited()
    s.remove("B", "magic")
    assert.are.same({ "A", "C" }, s.keys("rotation", "magic"))
  end)

  it("moves and swaps abilities within a group's list", function()
    local s = edited()
    s.move("C", "rotation", "magic", 1)
    assert.are.same({ "C", "A", "B" }, s.keys("rotation", "magic"))
    s.swap("C", "B", "rotation", "magic")
    assert.are.same({ "B", "A", "C" }, s.keys("rotation", "magic"))
  end)

  it("keeps both lists when a group switches between shared and per style", function()
    local s = edited()
    s.setGroup("rotation", "shared", true)
    assert.are.same({}, s.keys("rotation", "magic"))
    s.add("rotation", "magic", "S")
    s.setGroup("rotation", "shared", false)
    assert.are.same({ "A", "B", "C" }, s.keys("rotation", "magic"))
    s.setGroup("rotation", "shared", true)
    assert.are.same({ "S" }, s.keys("rotation", "ranged"))
  end)

  it("clamps display settings and restores them from the store as integers", function()
    local store = fakeStore()
    local s = savedgroups.load(store)
    s.setGroup("major", "size", 80)
    s.setGroup("major", "perRow", 0)
    s.setGroup("major", "grow", "sideways")
    s.setGroup("major", "grow", "left")
    store.data.cooldownGroups.groups.major.size = 56.0
    local major = savedgroups.load(store).group("major")
    assert.are.same({ 56, 1, "left" }, { major.size, major.perRow, major.grow })
    assert.are.equal("integer", math.type(major.size))
  end)

  it("leaves out of Defensives a defensive another style's list already holds", function()
    local seeded = { utility = true, necromancy = true, magic = true, ranged = true, melee = true }
    local s = savedgroups.load(fakeStore({
      cooldownGroups = {
        seeded = seeded,
        groups = {
          rotation = { styles = { magic = { "DEFENCE_FREEDOM" } } },
        },
      },
    }))
    assert.is_nil(indexOfKey(s.group("custom1").keys, "DEFENCE_FREEDOM"))
    assert.are.equal(#presets.DEFENSIVES - 1, #s.group("custom1").keys)
  end)

  it("starts with Defensives as the first custom group, adds up to three more, and deletes only custom ones", function()
    local store = fakeStore()
    local s = savedgroups.load(store)
    assert.are.same({ "Defensives", presets.DEFENSIVES }, { s.group("custom1").title, s.group("custom1").keys })
    assert.are.same({ "custom2", "custom3", "custom4" }, { s.addGroup(), s.addGroup(), s.addGroup() })
    assert.is_nil(s.addGroup())
    s.setGroup("custom2", "title", "Defensives and more than twenty")
    s.deleteGroup("custom1")
    s.deleteGroup("major")
    local reloaded = savedgroups.load(store)
    assert.are.same({ "major", "rotation", "utility", "custom2", "custom3", "custom4" }, reloaded.groupNames())
    assert.are.equal("Defensives and more", reloaded.group("custom2").title)
    assert.is_true(reloaded.group("custom2").shared)
    assert.are.equal("custom1", reloaded.addGroup())
  end)

  it("saves a learned ability only when its name or icon changed", function()
    local store = fakeStore()
    local s = savedgroups.load(store)
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)
    local writes = store.writes
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)
    assert.are.equal(writes, store.writes)
  end)
end)
