local targeteffects = require("src/targeteffects")

local VULNERABILITY, BLOATED, DEATH_MARK, SMOKE_CLOUD = 14395, 30098, 30100, 14771

describe("targeteffects.tracker", function()
  it("shows no debuffs before any var arrives", function()
    assert.are.same({ sprites = {}, complete = true }, targeteffects.tracker().debuffs())
  end)

  it("lists known bits from several vars in the order the game's target panel shows them", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20 | 0x80)
    tracker.onVar("COMBATV2_TARGET_EFFECTS_8", 0, 0x80)
    tracker.onVar("COMBATV2_TARGET_EFFECTS", 0, 0x20000000)
    local debuffs = tracker.debuffs()
    assert.are.same({ VULNERABILITY, SMOKE_CLOUD, BLOATED, DEATH_MARK }, debuffs.sprites)
    assert.is_true(debuffs.complete)
  end)

  it("drops a debuff once its bit clears", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20 | 0x80)
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0x20 | 0x80, 0x80)
    assert.are.same({ DEATH_MARK }, tracker.debuffs().sprites)
  end)

  it("reports an unknown set bit as incomplete and keeps the known debuffs", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20 | 0x1000)
    local debuffs = tracker.debuffs()
    assert.are.same({ BLOATED }, debuffs.sprites)
    assert.is_false(debuffs.complete)
  end)

  it("reads the top bit when the game sends it as a negative number", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_5", 0, -2146959360)
    local debuffs = tracker.debuffs()
    assert.are.same({ 26104, 17255 }, debuffs.sprites)
    assert.is_true(debuffs.complete)
  end)

  it("ignores other vars and returns the same result until a target effect var changes", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20)
    local first = tracker.debuffs()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0x20, 0x20)
    tracker.onVar("NPCTARGET", -1, 25128)
    assert.are.equal(first, tracker.debuffs())
  end)

  it("seeds each target effect var from its value at load", function()
    local tracker = targeteffects.tracker()
    tracker.seed(function(name)
      if name == "COMBATV2_TARGET_EFFECTS" then
        return 0x20000000
      end
    end)
    assert.are.same({ VULNERABILITY }, tracker.debuffs().sprites)
  end)
end)
