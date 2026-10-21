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
    tracker.read(asphyxiate)
    assert.is_nil(tracker.model())
  end)

  it("names the channel and gives its length as soon as its vars arrive", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.read(asphyxiate)
    assert.are.same({ start = 227269, name = "Asphyxiate", icon = 14660, duration = 4.2 }, tracker.model())
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
      if reads > 1 then return asphyxiate(structID) end
    end
    startAsphyxiate(tracker)
    tracker.read(failingOnce)
    assert.is_nil(tracker.model().name)
    tracker.read(failingOnce)
    assert.are.equal("Asphyxiate", tracker.model().name)
  end)

  it("ends when the game marks the channel finished", function()
    local tracker = channel.tracker()
    startAsphyxiate(tracker)
    tracker.read(asphyxiate)
    tracker.onVar("COMBATV2_CHANNEL_END_REASON", -1, 1)
    assert.is_nil(tracker.model())
  end)
end)
