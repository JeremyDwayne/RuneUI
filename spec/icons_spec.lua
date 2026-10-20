local icons = require("src/icons")

-- A struct table like the client's, keyed by id; lookup returns what the adapter reads from each.
local STRUCTS = {
  [3] = { configName = "COMBATV2_STUN_IMMUNE_DUMMY_ABILITY", icon = 26104, name = "Stun Immune" },
  [5] = { configName = "COMBATV2_ABILITY_NECROMANCY_BLOAT", icon = 30098, name = "Bloat" },
  [8] = { configName = "COMBATV2_DEBUFF_NECROMANCY_BLOATED", icon = 30098, name = "Bloated", info = "Swollen." },
}
local looked = 0
local function lookup(id)
  looked = looked + 1
  return STRUCTS[id]
end

describe("icons.index", function()
  it("names wanted icons, preferring a debuff struct over an earlier match, and saves what it found", function()
    local index = icons.index({}, 10)
    assert.is_nil(index.info(30098))
    assert.is_nil(index.info(26104))
    local learned = {}
    for _ = 1, 4 do
      for _, found in ipairs(index.step(lookup, 3)) do learned[found.sprite] = found end
    end
    assert.are.same({ name = "Bloated", info = "Swollen." }, index.info(30098))
    assert.are.same({ name = "Stun Immune" }, index.info(26104))
    assert.are.equal("Bloated", learned[30098].name)
    assert.are.equal("Stun Immune", learned[26104].name)
  end)

  it("starts from saved names and scans nothing until an unknown icon is wanted", function()
    local index = icons.index({ ["30098"] = { name = "Bloated" } }, 10)
    looked = 0
    assert.are.equal("Bloated", index.info(30098).name)
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)
end)
