local icons = require("src/icons")

local NAMES = {
  [30098] = { name = "Bloated", struct = 8 },
  [26104] = { name = "Stun Immune", struct = 3 },
}
local SPRITES = { [14766] = "BUFF_ICON_INCITE_FEAR", [26104] = "COMBAT_ICON_BUFF_11" }
local INFOS = { [8] = "Swollen." }
local ITEMS = { [49039] = "Elder overload salve (6)" }

-- The client lookups icons.index takes, counting description reads.
local described = 0
local client = {
  spriteName = function(sprite)
    return SPRITES[sprite]
  end,
  itemName = function(objID)
    return ITEMS[objID]
  end,
  describe = function(structID)
    described = described + 1
    return INFOS[structID]
  end,
}

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
  before_each(function()
    described = 0
  end)

  it("names a catalogued icon and reads its description from its struct once", function()
    local index = icons.index(NAMES, client)
    assert.are.same({ name = "Bloated", info = "Swollen." }, index.info(30098))
    assert.are.same({ name = "Stun Immune" }, index.info(26104))
    index.info(30098)
    assert.are.equal(2, described)
  end)

  it("labels an icon the catalog lacks from its sprite name, or names nothing", function()
    local index = icons.index(NAMES, client)
    assert.are.same({ name = "Incite Fear" }, index.info(14766))
    assert.are.same({}, index.info(99999))
    assert.are.equal(0, described)
  end)

  it("names an item icon from its item without its dose", function()
    local index = icons.index(NAMES, client)
    assert.are.same({ name = "Elder overload salve" }, index.info(-49039))
    assert.are.same({}, index.info(-1))
  end)
end)
