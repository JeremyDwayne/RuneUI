local fakeStore = require("spec/support/fake_store")
local presets = require("src/presets")
local savedgroups = require("src/savedgroups")

-- A store whose saved cooldown groups are groups, { [name] = saved group }.
local function groupsStore(groups)
  return fakeStore({ cooldownGroups = { groups = groups or {} } })
end

-- Magic's major holds X and Y and its rotation A, B and C; the shared utility holds U.
local function edited()
  return savedgroups.load(groupsStore({
    major = { styles = { magic = { "X", "Y" } } },
    rotation = { styles = { magic = { "A", "B", "C" } } },
    utility = { keys = { "U" } },
  }))
end

describe("savedgroups", function()
  it("fills every style and Utility from the presets on the first load", function()
    local s = savedgroups.load(fakeStore())
    for style, lists in pairs(presets.STYLES) do
      assert.are.same(lists.major, s.keys("major", style), style)
      assert.are.same(lists.rotation, s.keys("rotation", style), style)
    end
    assert.are.same(presets.UTILITY, s.keys("utility", "melee"))
  end)

  it("fills from the presets only while nothing is saved, so a list emptied on purpose stays empty", function()
    local store = fakeStore()
    local s = savedgroups.load(store)
    for _, key in ipairs(presets.STYLES.ranged.rotation) do
      s.remove(key, "ranged")
    end
    assert.are.same({}, savedgroups.load(store).keys("rotation", "ranged"))
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

  it("clamps display settings, says whether one changed, and restores them from the store as integers", function()
    local store = fakeStore()
    local s = savedgroups.load(store)
    s.setGroup("major", "size", 80)
    s.setGroup("major", "perRow", 0)
    assert.is_false(s.setGroup("major", "grow", "sideways"))
    assert.is_true(s.setGroup("major", "grow", "left"))
    assert.is_false(s.setGroup("major", "grow", "left"))
    store.data.cooldownGroups.groups.major.size = 56.0
    local major = savedgroups.load(store).group("major")
    assert.are.same({ 56, 1, "left" }, { major.size, major.perRow, major.grow })
    assert.are.equal("integer", math.type(major.size))
  end)

  it("saves a whole size and row length as integers, as loading reads them", function()
    local s = savedgroups.load(fakeStore())
    s.setGroup("major", "size", 40.0)
    s.setGroup("major", "perRow", 3.0)
    local major = s.group("major")
    assert.are.same({ "integer", "integer" }, { math.type(major.size), math.type(major.perRow) })
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
