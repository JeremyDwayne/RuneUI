local icons = require("src/icons")

-- A struct table like the client's, keyed by id; lookup returns what the adapter reads from each.
local STRUCTS = {
  [1] = { configName = "COMBATV2_BOSS_BUFF_SLISKE_DELIRIUM", icon = 30097, name = "Delirium - Poison grows." },
  [2] = { configName = "COMBATV2_BUFF_MAGIC_ASPHYXIATE_CRITICAL_DAMAGE", icon = 17606, name = "Channelled Might" },
  [3] = { configName = "COMBATV2_STUN_IMMUNE_DUMMY_ABILITY", icon = 26104, name = "Stun Immune" },
  [5] = { configName = "COMBATV2_ABILITY_NECROMANCY_BLOAT", icon = 30098, name = "Bloat" },
  [6] = { configName = "COMBATV2_POISONED_DUMMY_ABILITY", icon = 30097, name = "Poisoned" },
  [8] = { configName = "COMBATV2_DEBUFF_NECROMANCY_BLOATED", icon = 30098, name = "Bloated", info = "Swollen." },
  [9] = { configName = "COMBATV2_DEBUFF_DRENCHED", icon = 30500, name = "Drenched - Each stack slows you." },
}
local looked = 0
local function lookup(id)
  looked = looked + 1
  return STRUCTS[id]
end

local SPRITES = {
  [30098] = "BUFF_ICON_NECROMANCY_BLOATED",
  [26104] = "COMBAT_ICON_BUFF_11",
  [14766] = "BUFF_ICON_INCITE_FEAR",
  [30097] = "DEBUFF_ICON_POISONED",
  [17606] = "BUFF_ICON_MAGIC_ASPHYXIATE",
}
local function spriteName(sprite)
  return SPRITES[sprite]
end
local function noName()
  return nil
end
local described = 0
local function structInfo(structID)
  described = described + 1
  return STRUCTS[structID] and STRUCTS[structID].info
end
-- The client lookups icons.index takes, with no sprite names when bare.
local function client(bare)
  return { spriteName = bare and noName or spriteName, itemName = noName, describe = structInfo }
end

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

describe("icons.split", function()
  it("reads a non-breaking space tag as a space, so the name matches a typed search", function()
    assert.are.equal("Basic Attack", icons.split("Basic<nbsp>Attack"))
  end)

  it("splits a name of the form Name - text into the name and the text", function()
    assert.are.same({ "Drenched", "Each stack slows you." }, { icons.split("Drenched - Each stack slows you.") })
    assert.are.same({ "Delirium", "Poison grows - fast." }, { icons.split("Delirium - Poison grows - fast.") })
    assert.are.same(
      { "Flames of Zamorak", "Melts shields." },
      { icons.split("Flames of Zamorak<br><br>Melts shields.") }
    )
    assert.are.same({ "Warp Time", "Takes a snapshot of you." }, { icons.split("Warp Time: Takes a snapshot of you.") })
    assert.are.same({ "Imbue: Shadows" }, { icons.split("Imbue: Shadows") })
    assert.are.same({ "Blue stream", "Gaining adrenaline." }, { icons.split("Blue stream - gaining adrenaline.") })
    assert.are.same({ "Stun Immune" }, { icons.split("Stun Immune") })
    assert.are.same({ "Anti-poison" }, { icons.split("Anti-poison") })
  end)
end)

describe("icons.index", function()
  it("names wanted icons, preferring a debuff struct over an earlier match, and saves what it found", function()
    local index = icons.index({}, client(true), 10)
    assert.is_nil(index.info(30098))
    assert.is_nil(index.info(26104))
    local learned = {}
    for _ = 1, 4 do
      for _, found in ipairs(index.step(lookup, 3)) do
        learned[found.sprite] = found
      end
    end
    assert.are.same({ name = "Bloated", info = "Swollen." }, index.info(30098))
    assert.are.same({ name = "Stun Immune" }, index.info(26104))
    assert.are.same({ sprite = 30098, name = "Bloated", struct = 8 }, learned[30098])
    assert.are.equal("Stun Immune", learned[26104].name)
  end)

  it("reads a saved icon's description from its struct once, on first ask", function()
    local saved = { ["30098"] = { name = "Bloated", struct = 8 } }
    local index = icons.index(saved, client(), 10)
    described = 0
    assert.are.same({ name = "Bloated", info = "Swollen." }, index.info(30098))
    index.info(30098)
    assert.are.same({ 1, { name = "Bloated", struct = 8 } }, { described, saved["30098"] })
  end)

  it("shows a saved Name - text name, and a scan match, by the name alone", function()
    local index = icons.index({ ["30098"] = { name = "Drenched - Each stack slows you." } }, client(), 10)
    assert.are.equal("Drenched", index.info(30098).name)
    index.info(30500)
    local found = {}
    for _ = 1, 4 do
      for _, f in ipairs(index.step(lookup, 3)) do
        found[#found + 1] = f
      end
    end
    assert.are.same({ { sprite = 30500, name = "Drenched", struct = 9 } }, found)
  end)

  it("names an icon it learns at once with no scan, and leaves a named icon alone", function()
    local index = icons.index({ ["30098"] = { name = "Bloated", struct = 8 } }, client(), 10)
    assert.is_true(index.learn(26104, "Stun Immune", 3))
    assert.is_false(index.learn(30098, "Swollen", 5))
    looked = 0
    index.step(lookup, 5)
    assert.are.same({ 0, "Stun Immune", "Bloated" }, { looked, index.info(26104).name, index.info(30098).name })
  end)

  it("starts from saved names and scans nothing until an unknown icon is wanted", function()
    local index = icons.index({ ["30098"] = { name = "Bloated" } }, client(), 10)
    looked = 0
    assert.are.equal("Bloated", index.info(30098).name)
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)

  it("names an item icon from its item without its dose, scanning nothing", function()
    local function itemName(objID)
      return objID == 49039 and "Elder overload salve (6)" or nil
    end
    local index = icons.index({}, { spriteName = spriteName, itemName = itemName, describe = structInfo }, 10)
    looked = 0
    assert.are.same({ name = "Elder overload salve" }, index.info(-49039))
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)

  it("shows an icon's sprite label until the scan names it", function()
    local index = icons.index({}, client(), 10)
    assert.are.same({ name = "Buff 11" }, index.info(26104))
    for _ = 1, 4 do
      index.step(lookup, 3)
    end
    assert.are.same({ name = "Stun Immune" }, index.info(26104))
  end)

  it("reports an icon no struct matches, and never scans for it again once saved", function()
    local index = icons.index({}, client(), 10)
    index.info(14766)
    local found = {}
    for _ = 1, 4 do
      for _, f in ipairs(index.step(lookup, 3)) do
        found[#found + 1] = f
      end
    end
    assert.are.same({ { sprite = 14766 } }, found)

    index = icons.index({ ["14766"] = { unmatched = true } }, client(), 10)
    looked = 0
    assert.are.same({ name = "Incite Fear" }, index.info(14766))
    index.step(lookup, 5)
    assert.are.equal(0, looked)
  end)

  it("stops reporting a lookup for an unmatched icon with no sprite label", function()
    local index = icons.index({}, client(true), 10)
    assert.is_nil(index.info(14766))
    for _ = 1, 4 do
      index.step(lookup, 3)
    end
    assert.are.same({}, index.info(14766))
  end)

  it("prefers a struct named for the sprite, and otherwise keeps the lowest id", function()
    local index = icons.index({}, client(), 10)
    index.info(30097)
    index.info(17606)
    for _ = 1, 4 do
      index.step(lookup, 3)
    end
    assert.are.same({ "Poisoned", "Channelled Might" }, { index.info(30097).name, index.info(17606).name })
  end)
end)
