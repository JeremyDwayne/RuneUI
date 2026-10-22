local targeteffects = require("src/targeteffects")

local VULNERABILITY, ENFEEBLE, BLOATED, DEATH_MARK, SMOKE_CLOUD = 14395, 14371, 30098, 30100, 14771

describe("targeteffects.tracker", function()
  it("shows no debuffs before any var arrives", function()
    assert.are.same({ sprites = {}, complete = true, timers = {} }, targeteffects.tracker().debuffs())
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
    tracker.onVar("LIFEPOINTS", 9900, 9800)
    assert.are.equal(first, tracker.debuffs())
  end)

  it("counts a debuff's measured length down from the tick its bit set", function()
    local tracker = targeteffects.tracker()
    tracker.onTick()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20)
    assert.are.same({ [BLOATED] = { left = 33, full = 33 } }, tracker.debuffs().timers)
    tracker.onTick()
    tracker.onTick()
    assert.are.same({ [BLOATED] = { left = 31, full = 33 } }, tracker.debuffs().timers)
  end)

  it("drops a timer once its time runs out with the bit still set", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20)
    for _ = 1, 33 do
      tracker.onTick()
    end
    local debuffs = tracker.debuffs()
    assert.are.same({ BLOATED }, debuffs.sprites)
    assert.are.same({}, debuffs.timers)
  end)

  it("times no debuff already set when the target changes", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0, 0x20)
    tracker.onVar("NPCTARGET", 25128, 25127)
    assert.are.same({}, tracker.debuffs().timers)
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0x20, 0x20 | 0x40)
    assert.are.same({ [30212] = { left = 50, full = 50 } }, tracker.debuffs().timers)
  end)

  it("restarts a set debuff's time when its spell is cast again, and times no unset one", function()
    local tracker = targeteffects.tracker()
    tracker.onVar("COMBATV2_TARGET_EFFECTS", 0, 0x40000000)
    for _ = 1, 40 do
      tracker.onTick()
    end
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", 14000, 14787)
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", 14787, 14784)
    assert.are.same({ [ENFEEBLE] = { left = 102, full = 102 } }, tracker.debuffs().timers)
  end)

  it("times no debuff without a measured length, nor one set before load", function()
    local tracker = targeteffects.tracker()
    tracker.seed(function(name)
      if name == "COMBATV2_TARGET_EFFECTS_11" then
        return 0x20
      end
    end)
    tracker.onVar("COMBATV2_TARGET_EFFECTS_11", 0x20, 0x20 | 0x80)
    assert.are.same({}, tracker.debuffs().timers)
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
