local cooldowns = require("src/cooldowns")

local CB = "COMBATV2_COOLDOWN_MAGIC_CONCENTRATED_BLAST"
local DB = "COMBATV2_COOLDOWN_MAGIC_DRAGON_BREATH"
local BLAST = { name = "Concentrated Blast", icon = 13309 }

local function noAbility()
  return nil
end
local function blast()
  return BLAST
end

-- Fires an ability whose cooldown runs from tick start for length ticks.
local function fire(tracker, varStem, start, length)
  tracker.onVar(varStem .. "_START", start - 50, start)
  tracker.onVar(varStem .. "_END", start - 40, start + length)
end

local function justUsedChanged(tracker)
  tracker.onVar("COMBATV2_JUST_USED_ABILITY", 14730, 45450)
end

describe("cooldowns.tracker", function()
  it("gives the seconds left at each server tick and turns ready at the end", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    tracker.onTick(noAbility)
    local tile = tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1]
    assert.is_false(tile.ready)
    assert.are.equal(4.8, tile.remaining)
    for _ = 1, 8 do
      tracker.onTick(noAbility)
    end
    assert.is_true(tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1].ready)
  end)

  it("reports a change once after a cooldown or weapon style var changes, and not after other vars", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    assert.is_true(tracker.changed())
    assert.is_false(tracker.changed())
    tracker.onVar("COMBATV2_MAINHAND_STYLE", 1, 8)
    assert.is_true(tracker.changed())
    tracker.onVar("SA_ENERGY", 0, 100)
    assert.is_false(tracker.changed())
  end)

  it("follows the combat style of the latest started cooldown, skipping style-free ones", function()
    local tracker = cooldowns.tracker()
    assert.is_nil(tracker.style())
    fire(tracker, CB, 1000, 9)
    assert.are.equal("magic", tracker.style())
    fire(tracker, "COMBATV2_COOLDOWN_STRENGTH_DESTROY", 1001, 25)
    assert.are.equal("melee", tracker.style())
    fire(tracker, "COMBATV2_COOLDOWN_DEFENCE_RESONANCE", 1002, 50)
    assert.are.equal("melee", tracker.style())
  end)

  it("gives each tile its cooldown length in seconds once the ability has fired", function()
    local tracker = cooldowns.tracker()
    assert.is_nil(tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1].cooldown)
    fire(tracker, CB, 1000, 25)
    tracker.onTick(noAbility)
    assert.are.equal(15, tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1].cooldown)
  end)

  it("tracks weapon special cooldowns, whose vars carry their own prefix", function()
    local tracker = cooldowns.tracker()
    fire(tracker, "COMBATV2_ABILITY_WEAPON_COOLDOWN_INSTABILITY", 1000, 100)
    tracker.onTick(noAbility)
    local tile = tracker.tiles({ "WEAPON_INSTABILITY" }, {})[1]
    assert.are.same({ "Instability", 59.4, 60 }, { tile.name, tile.remaining, tile.cooldown })
    assert.are.same({ "WEAPON_INSTABILITY" }, tracker.known())
  end)

  it("gives a weapon special the shared special attack icon and keeps its own name", function()
    local tracker = cooldowns.tracker()
    fire(tracker, "COMBATV2_ABILITY_WEAPON_COOLDOWN_INSTABILITY", 1000, 100)
    justUsedChanged(tracker)
    local learned = tracker.onTick(function()
      return { key = "CONSTITUTION_SPECIAL_ATTACK", name = "Weapon Special Attack", icon = 26105 }
    end)
    assert.are.same({ key = "WEAPON_INSTABILITY", icon = 26105 }, learned)
    local tile = tracker.tiles({ "WEAPON_INSTABILITY" }, {})[1]
    assert.are.same({ "Instability", 26105 }, { tile.name, tile.icon })
  end)

  it("ignores unchanged values and the global cooldown", function()
    local tracker = cooldowns.tracker()
    tracker.onVar(CB .. "_START", 1000, 1000)
    tracker.onVar("COMBATV2_GLOBAL_COOLDOWN_START", 990, 1000)
    assert.are.same({}, tracker.known())
  end)

  it("takes name and icon from the just-used ability on the tick a single cooldown starts", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    justUsedChanged(tracker)
    tracker.onTick(blast)
    local tile = tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1]
    assert.are.equal("Concentrated Blast", tile.name)
    assert.are.equal(13309, tile.icon)
  end)

  it("leaves both unnamed when two cooldowns start on the same tick", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    fire(tracker, DB, 1000, 12)
    justUsedChanged(tracker)
    tracker.onTick(blast)
    local tiles = tracker.tiles({ "MAGIC_CONCENTRATED_BLAST", "MAGIC_DRAGON_BREATH" }, {})
    assert.is_nil(tiles[1].icon)
    assert.is_nil(tiles[2].icon)
  end)

  it("names the cooldown matching the struct when several start on one tick", function()
    local tracker = cooldowns.tracker()
    fire(tracker, "COMBATV2_COOLDOWN_NECROMANCY_CONJURE_VENGEFUL_GHOST", 1000, 50)
    fire(tracker, "COMBATV2_COOLDOWN_NECROMANCY_COMMAND_VENGEFUL_GHOST", 1000, 25)
    justUsedChanged(tracker)
    tracker.onTick(function()
      return { key = "NECROMANCY_CONJURE_VENGEFUL_GHOST", name = "Conjure Vengeful Ghost", icon = 30080 }
    end)
    local tiles = tracker.tiles({ "NECROMANCY_CONJURE_VENGEFUL_GHOST", "NECROMANCY_COMMAND_VENGEFUL_GHOST" }, {})
    assert.are.equal(30080, tiles[1].icon)
    assert.is_nil(tiles[2].icon)
  end)

  it("reports the ability it learned on a tick", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    justUsedChanged(tracker)
    assert.are.same(
      { key = "MAGIC_CONCENTRATED_BLAST", name = "Concentrated Blast", icon = 13309 },
      tracker.onTick(blast)
    )
    assert.is_nil(tracker.onTick(blast))
  end)

  it("shows saved names and icons before an ability fires this session", function()
    local tracker = cooldowns.tracker()
    tracker.seed({ MAGIC_CONCENTRATED_BLAST = { name = "Concentrated Blast", icon = 13309 } })
    local tile = tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1]
    assert.are.equal(13309, tile.icon)
    assert.is_true(tile.ready)
    assert.are.same({}, tracker.known())
    fire(tracker, CB, 1000, 9)
    assert.are.same({ "MAGIC_CONCENTRATED_BLAST" }, tracker.known())
  end)

  it("ignores a just-used ability that did not change on that tick", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    tracker.onTick(blast)
    assert.is_nil(tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, {})[1].icon)
  end)

  it("names an ability from its var with initials when no struct is known", function()
    local tracker = cooldowns.tracker()
    fire(tracker, DB, 1000, 12)
    local tile = tracker.tiles({ "MAGIC_DRAGON_BREATH" }, {})[1]
    assert.are.equal("Dragon Breath", tile.name)
    assert.are.equal("DB", tile.initials)
  end)

  it("shows the keybind of the bar slot whose icon matches", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    justUsedChanged(tracker)
    tracker.onTick(blast)
    local slots = { [13309] = { keybind = "Q", usable = true } }
    assert.are.equal("Q", tracker.tiles({ "MAGIC_CONCENTRATED_BLAST" }, slots)[1].keybind)
  end)

  it("marks a tile not usable while its bar slot shows the ability can't be cast", function()
    local tracker = cooldowns.tracker()
    tracker.seed({
      MAGIC_CONCENTRATED_BLAST = { name = "Concentrated Blast", icon = 13309 },
      MAGIC_DRAGON_BREATH = { name = "Dragon Breath", icon = 13310 },
    })
    local tiles = tracker.tiles({ "MAGIC_CONCENTRATED_BLAST", "MAGIC_DRAGON_BREATH" }, { [13309] = { usable = false } })
    assert.are.same({ false, true }, { tiles[1].usable, tiles[2].usable })
  end)

  it("builds tiles in the given order", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    fire(tracker, DB, 1001, 12)
    local tiles = tracker.tiles({ "MAGIC_DRAGON_BREATH", "MAGIC_CONCENTRATED_BLAST" }, {})
    assert.are.equal("MAGIC_DRAGON_BREATH", tiles[1].key)
    assert.are.equal("MAGIC_CONCENTRATED_BLAST", tiles[2].key)
  end)

  it("counts Dismember's MELEE_ cooldown as melee and defensives as no style", function()
    assert.are.same({ "melee", "melee" }, { cooldowns.styleOf("MELEE_DISMEMBER"), cooldowns.styleOf("ATTACK_FLURRY") })
    assert.is_nil(cooldowns.styleOf("DEFENCE_FREEDOM"))
  end)

  it("takes the name, icon and keybind of an upgraded form the action bar shows instead", function()
    local tracker = cooldowns.tracker()
    tracker.seed({
      MAGIC_SUNSHINE = {
        name = "Sunshine",
        icon = 20183,
        forms = {
          { name = "Sunshine", icon = 20183 },
          { name = "Greater Sunshine", icon = 20184 },
        },
      },
    })
    local tile = tracker.tiles({ "MAGIC_SUNSHINE" }, { [20184] = { keybind = "1", usable = true } })[1]
    assert.are.same({ "Greater Sunshine", 20184, "1" }, { tile.name, tile.icon, tile.keybind })
    tile = tracker.tiles({ "MAGIC_SUNSHINE" }, {})[1]
    assert.are.same({ "Sunshine", 20183 }, { tile.name, tile.icon })
  end)

  it("keeps a seeded name when a later seed gives only an icon", function()
    local tracker = cooldowns.tracker()
    tracker.seed({ MAGIC_SUNSHINE = { name = "Sunshine", icon = 20183 } })
    tracker.seed({ MAGIC_SUNSHINE = { icon = 20184 } })
    local tile = tracker.tiles({ "MAGIC_SUNSHINE" }, {})[1]
    assert.are.same({ "Sunshine", 20184 }, { tile.name, tile.icon })
  end)

  it("takes the style from the main-hand weapon, keeping it through an empty hand", function()
    local tracker = cooldowns.tracker()
    fire(tracker, CB, 1000, 9)
    tracker.onVar("COMBATV2_MAINHAND_STYLE", nil, 8)
    assert.are.equal("ranged", tracker.style())
    tracker.onVar("COMBATV2_MAINHAND_STYLE", 8, 7)
    assert.are.equal("ranged", tracker.style())
    tracker.onVar("COMBATV2_MAINHAND_STYLE", 7, 6)
    assert.are.equal("melee", tracker.style())
    tracker.onVar("COMBATV2_MAINHAND_STYLE", 6, 37)
    assert.are.equal("necromancy", tracker.style())
  end)

  it("falls back to the latest ability's style for an unknown weapon value", function()
    local tracker = cooldowns.tracker()
    tracker.onVar("COMBATV2_MAINHAND_STYLE", nil, 1)
    fire(tracker, "COMBATV2_COOLDOWN_STRENGTH_DESTROY", 1000, 9)
    assert.are.equal("magic", tracker.style())
    tracker.onVar("COMBATV2_MAINHAND_STYLE", 1, 99)
    assert.are.equal("melee", tracker.style())
  end)
end)
