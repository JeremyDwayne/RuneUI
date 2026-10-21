local channel = require("src/channel")

local CHOKE = 14731
local function asphyxiate(structID)
  if structID == CHOKE then return { name = "Asphyxiate", icon = 14660 } end
end

-- Starts Asphyxiate's channel on server ticks 227269 to 227275, as the game sets it.
local function startAsphyxiate(tracker)
  tracker.onVar("COMBATV2_CHANNEL_END_REASON", 1, -1)
  tracker.onVar("COMBATV2_CHANNEL_END", 227265, 227275)
  tracker.onVar("COMBATV2_CHANNEL_START", 227263, 227269)
  tracker.onVar("COMBATV2_CHANNEL_ABILITY_STRUCT", 45450, CHOKE)
end

describe("channel.tracker", function()
  it("shows nothing before a channel starts", function()
    local tracker = channel.tracker()
    tracker.onTick(asphyxiate)
    assert.is_nil(tracker.model())
  end)

  it("names the channel and counts its time down 0.6 s a tick from the game's first label", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.onTick(asphyxiate)
    local first = tracker.model()
    assert.are.same({ "Asphyxiate", 14660, 4.2 }, { first.name, first.icon, first.seconds })
    assert.are.equal(4.2, first.duration)
    tracker.onTick(asphyxiate)
    assert.are.equal(3.6, tracker.model().seconds)
  end)

  it("reads the ability's struct once per channel", function()
    local tracker = channel.tracker()
    local reads = 0
    local function counting(structID)
      reads = reads + 1
      return asphyxiate(structID)
    end
    startAsphyxiate(tracker)
    tracker.onTick(counting)
    tracker.onTick(counting)
    assert.are.equal(1, reads)
  end)

  it("reads the ability's struct again on the next tick when it found nothing", function()
    local tracker = channel.tracker()
    local reads = 0
    local function failingOnce(structID)
      reads = reads + 1
      if reads > 1 then return asphyxiate(structID) end
    end
    startAsphyxiate(tracker)
    tracker.onTick(failingOnce)
    assert.is_nil(tracker.model().name)
    tracker.onTick(failingOnce)
    assert.are.equal("Asphyxiate", tracker.model().name)
  end)

  it("ends when the game marks the channel finished", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.onTick(asphyxiate)
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", -1, 1)
    assert.is_nil(tracker.model())
  end)

  it("ends once its last tick passes, even with no finish from the game", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    for _ = 1, 7 do tracker.onTick(asphyxiate) end
    assert.are.equal(0.6, tracker.model().seconds)
    tracker.onTick(asphyxiate)
    assert.is_nil(tracker.model())
  end)
end)
