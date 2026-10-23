local targeteffects = require("src/targeteffects")

local VULNERABILITY, ENFEEBLE, BLOATED, DEATH_MARK, SMOKE_CLOUD = 14395, 14371, 30098, 30100, 14771

-- Struct ids the specs use for abilities, and the names their structs read.
local BIND, SNARE, CAST_ENFEEBLE = 1, 2, 3
local NAMES = { [BIND] = "Bind", [SNARE] = "Snare", [CAST_ENFEEBLE] = "Enfeeble" }
local BOUND = 14392

local function nameOf(struct)
  return NAMES[struct] and { name = NAMES[struct] }
end

-- One server tick: the tracker ticks, then sees the sprites the target frame shows.
local function step(tracker, sprites)
  tracker.onTick(nameOf)
  tracker.observe(sprites)
end

-- A tracker past its first tick, so the debuffs it sees next are newly applied.
local function timed()
  local tracker = targeteffects.tracker()
  step(tracker, {})
  return tracker
end

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
    tracker.onVar("LIFEPOINTS", 9900, 9800)
    assert.are.equal(first, tracker.debuffs())
  end)

  it("counts a debuff's length down from the tick it shows on the target", function()
    local tracker = timed()
    step(tracker, { BLOATED })
    assert.are.same({ [BLOATED] = { left = 33, full = 33 } }, tracker.timers())
    step(tracker, { BLOATED })
    step(tracker, { BLOATED })
    assert.are.same({ [BLOATED] = { left = 31, full = 33 } }, tracker.timers())
  end)

  it("drops a timer once its time runs out with the icon still shown", function()
    local tracker = timed()
    for _ = 1, 34 do
      step(tracker, { BLOATED })
    end
    assert.are.same({}, tracker.timers())
  end)

  it("times no debuff shown at load or on a new target", function()
    local tracker = targeteffects.tracker()
    step(tracker, { VULNERABILITY })
    assert.are.same({}, tracker.timers())
    tracker.onVar("NPCTARGET", 25128, 25127)
    step(tracker, { VULNERABILITY, BLOATED })
    assert.are.same({}, tracker.timers())
    step(tracker, { VULNERABILITY, BLOATED, SMOKE_CLOUD })
    assert.are.same({ [SMOKE_CLOUD] = { left = 200, full = 200 } }, tracker.timers())
  end)

  it("times the debuff that opens a fight on a new target", function()
    local tracker = timed()
    tracker.onVar("NPCTARGET", -1, 25128)
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", 0, CAST_ENFEEBLE)
    step(tracker, { ENFEEBLE })
    assert.are.same({ [ENFEEBLE] = { left = 100, full = 100 } }, tracker.timers())
  end)

  it("gives a debuff the length of the ability that applied it, named up to 2 ticks late", function()
    local tracker = timed()
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", 0, SNARE)
    step(tracker, { BOUND })
    assert.are.same({ [BOUND] = { left = 30, full = 30 } }, tracker.timers())
    tracker = timed()
    step(tracker, { BOUND })
    assert.are.same({}, tracker.timers())
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", 0, BIND)
    step(tracker, { BOUND })
    assert.are.same({ [BOUND] = { left = 19, full = 20 } }, tracker.timers())
  end)

  it("restarts a debuff when its ability is used again, unless that ability keeps it", function()
    local tracker = timed()
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", 0, SNARE)
    step(tracker, { ENFEEBLE, BOUND })
    for _ = 1, 10 do
      step(tracker, { ENFEEBLE, BOUND })
    end
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", SNARE, CAST_ENFEEBLE)
    step(tracker, { ENFEEBLE, BOUND })
    tracker.onVar("COMBATV2_JUST_USED_ABILITY", CAST_ENFEEBLE, SNARE)
    step(tracker, { ENFEEBLE, BOUND })
    assert.are.same({
      [ENFEEBLE] = { left = 99, full = 100 },
      [BOUND] = { left = 18, full = 30 },
    }, tracker.timers())
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
