local channel = require("src/channel")

local CHOKE = 14731
local function asphyxiate(structID)
  if structID == CHOKE then
    return { configName = "COMBATV2_ABILITY_MAGIC_CHOKE", name = "Asphyxiate", icon = 14660 }
  end
end

-- Starts Asphyxiate's channel on server ticks 227269 to 227275, 3 iterations 2 ticks apart, as the game sets it
-- right after the server tick of START.
local function startAsphyxiate(tracker)
  tracker.onVar("COMBATV2_CHANNEL_END_REASON", 1, -1)
  tracker.onVar("COMBATV2_CHANNEL_ABILITY_ITERATIONS", 2, 3)
  tracker.onVar("COMBATV2_CHANNEL_END", 227265, 227275)
  tracker.onVar("COMBATV2_CHANNEL_START", 227263, 227269)
  tracker.onVar("COMBATV2_CHANNEL_ABILITY_STRUCT", 45450, CHOKE)
end

describe("channel.tracker", function()
  it("shows nothing before a channel starts", function()
    local tracker = channel.tracker()
    tracker.onTick()
    tracker.read(asphyxiate)
    assert.is_nil(tracker.model())
  end)

  it("names the channel, lasts as long as the game's cast bar and times a hit on START and each iteration", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.read(asphyxiate)
    local expected = { start = 227269, name = "Asphyxiate", icon = 14660, duration = 4.2, ticksLeft = 7 }
    expected.hits = { 0, 1.2, 2.4, 3.6 }
    expected.style = "magic"
    assert.are.same(expected, tracker.model())
  end)

  it("names a first channel that repeats the struct and iterations held at load", function()
    local tracker = channel.tracker()
    local atLoad = { COMBATV2_CHANNEL_ABILITY_STRUCT = CHOKE, COMBATV2_CHANNEL_ABILITY_ITERATIONS = 3 }
    tracker.seed(function(name)
      return atLoad[name]
    end)
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", 1, -1)
    tracker.onVar("COMBATV2_CHANNEL_END", 227265, 227275)
    tracker.onVar("COMBATV2_CHANNEL_START", 227263, 227269)
    tracker.read(asphyxiate)
    local model = tracker.model()
    assert.are.same({ "Asphyxiate", "magic", 4 }, { model.name, model.style, #model.hits })
  end)

  it("counts the ticks left down on each server tick after START, as the game's label steps", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.onTick()
    assert.are.equal(6, tracker.model().ticksLeft)
  end)

  it("reports a change once after channel vars change, and not after other vars", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    assert.is_true(tracker.changed())
    assert.is_false(tracker.changed())
    tracker.onVar("SA_ENERGY", 0, 100)
    assert.is_false(tracker.changed())
  end)

  it("shows nothing until the channel's END arrives with its START", function()
    local tracker = channel.tracker()
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", 1, -1)
    tracker.onVar("COMBATV2_CHANNEL_END", 0, 227265)
    tracker.onVar("COMBATV2_CHANNEL_START", 227263, 227269)
    assert.is_nil(tracker.model())
  end)

  it("reads the ability's struct once per channel", function()
    local tracker = channel.tracker()
    local reads = 0
    local function counting(structID)
      reads = reads + 1
      return asphyxiate(structID)
    end
    startAsphyxiate(tracker)
    tracker.read(counting)
    tracker.read(counting)
    assert.are.equal(1, reads)
  end)

  it("reads the ability's struct again when it found nothing", function()
    local tracker = channel.tracker()
    local reads = 0
    local function failingOnce(structID)
      reads = reads + 1
      if reads > 1 then
        return asphyxiate(structID)
      end
    end
    startAsphyxiate(tracker)
    tracker.read(failingOnce)
    assert.is_nil(tracker.model().name)
    tracker.read(failingOnce)
    assert.are.equal("Asphyxiate", tracker.model().name)
  end)

  it("keeps the name, icon and style when the channel's struct changes on its last hit", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.read(asphyxiate)
    for _ = 1, 6 do
      tracker.onTick()
    end
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", -1, 1)
    tracker.onVar("COMBATV2_CHANNEL_ABILITY_STRUCT", CHOKE, 14732)
    tracker.read(asphyxiate)
    local model = tracker.model()
    assert.are.same({ "Asphyxiate", 14660, "magic" }, { model.name, model.icon, model.style })
  end)

  it("keeps a finished channel until its last tick passes, as the game's cast bar shows 0.6s on", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    for _ = 1, 6 do
      tracker.onTick()
    end
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", -1, 1)
    assert.are.equal(1, tracker.model().ticksLeft)
    tracker.onTick()
    assert.is_nil(tracker.model())
  end)

  it("reports a cancelled channel on the tick it was cancelled, and nothing after", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.onTick()
    tracker.onVar("COMBATV2_CHANNEL_END", 227275, 227270)
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", -1, 2)
    assert.are.same({ start = 227269, cancelled = true }, tracker.model())
    tracker.onTick()
    assert.is_nil(tracker.model())
  end)
end)
