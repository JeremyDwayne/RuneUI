local icons = require("src/icons")

-- A struct table like the client's, keyed by id; lookup returns what the adapter reads from each.
local STRUCTS = {
  [1] = { configName = "COMBATV2_BOSS_BUFF_SLISKE_DELIRIUM", icon = 30097, name = "Delirium - Poison grows." },
  [2] = { configName = "COMBATV2_BUFF_MAGIC_ASPHYXIATE_CRITICAL_DAMAGE", icon = 17606, name = "Channelled Might" },
  [3] = { configName = "COMBATV2_STUN_IMMUNE_DUMMY_ABILITY", icon = 26104, name = "Stun Immune" },
  [5] = { configName = "COMBATV2_ABILITY_NECROMANCY_BLOAT", icon = 30098, name = "Bloat" },
  [6] = { configName = "COMBATV2_POISONED_DUMMY_ABILITY", icon = 30097, name = "Poisoned" },
  [8] = { configName = "COMBATV2_DEBUFF_NECROMANCY_BLOATED", icon = 30098, name = "Bloated", info = "Swollen." },
}
local looked = 0
local function lookup(id)
  looked = looked + 1
  return STRUCTS[id]
end

local SPRITES = {
  [30098] = "BUFF_ICON_NECROMANCY_BLOATED", [26104] = "COMBAT_ICON_BUFF_11", [14766] = "BUFF_ICON_INCITE_FEAR",
  [30097] = "DEBUFF_ICON_POISONED", [17606] = "BUFF_ICON_MAGIC_ASPHYXIATE",
}
local function spriteName(sprite) return SPRITES[sprite] end
local function noName() return nil end

describe("icons.spriteLabel", function()
  it("drops the icon prefix and a leading combat style, and title cases the rest", function()
    assert.are.equal("Haunted", icons.spriteLabel("DEBUFF_ICON_NECROMANCY_HAUNTED"))
    assert.are.equal("Corruption Shot", icons.spriteLabel("COMBAT_ABILITY_ICON_RANGED_CORRUPTION_SHOT"))
    assert.are.equal("Adrenaline Reduced", icons.spriteLabel("DEBUFF_ICON_COMBAT_ADRENALINE_REDUCED"))
    assert.are.equal("Buff 11", icons.spriteLabel("COMBAT_ICON_BUFF_11"))
    assert.are.equal("Smoke Cloud", icons.spriteLabel("SPELL_ANCIENT_MAGICKS_ICON_SMOKE_CLOUD"))
    assert.is_nil(icons.spriteLabel("BUFF_ICON_MAGIC"))
  end)
end)

describe("icons.index", function()
  it("names wanted icons, preferring a debuff struct over an earlier match, and saves what it found", function()
    local index = icons.index({}, noName, noName, 10)
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
    local index = icons.index({ ["30098"] = { name = "Bloated" } }, spriteName, noName, 10)
    looked = 0
    assert.are.equal("Bloated", index.info(30098).name)
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)

  it("names an item icon from its item without its dose, scanning nothing", function()
    local function itemName(objID) return objID == 49039 and "Elder overload salve (6)" or nil end
    local index = icons.index({}, spriteName, itemName, 10)
    looked = 0
    assert.are.same({ name = "Elder overload salve" }, index.info(-49039))
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)

  it("shows an icon's sprite label until the scan names it", function()
    local index = icons.index({}, spriteName, noName, 10)
    assert.are.same({ name = "Buff 11" }, index.info(26104))
    for _ = 1, 4 do index.step(lookup, 3) end
    assert.are.same({ name = "Stun Immune" }, index.info(26104))
  end)

  it("reports an icon no struct matches, and never scans for it again once saved", function()
    local index = icons.index({}, spriteName, noName, 10)
    index.info(14766)
    local found = {}
    for _ = 1, 4 do
      for _, f in ipairs(index.step(lookup, 3)) do found[#found + 1] = f end
    end
    assert.are.same({ { sprite = 14766 } }, found)

    index = icons.index({ ["14766"] = { unmatched = true } }, spriteName, noName, 10)
    looked = 0
    assert.are.same({ name = "Incite Fear" }, index.info(14766))
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)

  it("stops reporting a lookup for an unmatched icon with no sprite label", function()
    local index = icons.index({}, noName, noName, 10)
    assert.is_nil(index.info(14766))
    for _ = 1, 4 do index.step(lookup, 3) end
    assert.are.same({}, index.info(14766))
  end)

  it("prefers a struct named for the sprite, and otherwise keeps the lowest id", function()
    local index = icons.index({}, spriteName, noName, 10)
    index.info(30097)
    index.info(17606)
    for _ = 1, 4 do index.step(lookup, 3) end
    assert.are.same({ "Poisoned", "Channelled Might" }, { index.info(30097).name, index.info(17606).name })
  end)
end)
