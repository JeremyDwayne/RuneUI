local auras = require("src/auras")

local OVERLOAD, INCITE, SONIC, AFTERSHOCK, STUN, BLOODLUST = 30093, 14766, 27432, 26466, 14695, 23876

local function buffs(...)
  local list = {}
  for i = 1, select("#", ...), 2 do list[#list + 1] = { sprite = select(i, ...), label = select(i + 1, ...) } end
  return { buffs = list, debuffs = {} }
end

-- The row model for sprite in row, or nil.
local function shown(tracker, row, sprite, categories)
  for _, model in ipairs(tracker.rows(categories or {}, {})[row]) do
    if model.sprite == sprite then return model end
  end
end

describe("auras.parse", function()
  it("reads seconds, minutes to the top of the minute, hours and stacks, and no timer from other labels", function()
    assert.are.same({ seconds = 20, low = 19, text = "20", stacks = "5" }, auras.parse("20<br>(5)"))
    assert.are.same({ seconds = 20, low = 19, text = "20", stacks = "5" }, auras.parse("20(5)"))
    assert.are.same({ seconds = 419, low = 360, text = "6m" }, auras.parse("6m"))
    assert.are.same({ seconds = 7199, low = 3600, text = "1h" }, auras.parse("1h"))
    assert.are.same({}, auras.parse("47%"))
    assert.are.same({}, auras.parse("247/1 K"))
    assert.are.same({}, auras.parse(""))
    assert.are.same({}, auras.parse(nil))
  end)
end)

describe("auras.tracker", function()
  it("sorts a new buff by its first time left: combat up to a minute, upkeep above, hidden with no timer", function()
    local tracker = auras.tracker()
    local new = tracker.onTick(buffs(SONIC, "60", OVERLOAD, "6m", AFTERSHOCK, "47%"))
    assert.are.same({
      { sprite = SONIC, category = "combat" },
      { sprite = OVERLOAD, category = "upkeep" },
      { sprite = AFTERSHOCK, category = "hidden" },
    }, new)
    assert.are.same({}, tracker.onTick(buffs(SONIC, "59", OVERLOAD, "6m", AFTERSHOCK, "47%")))
    assert.is_not_nil(shown(tracker, "combatBuffs", SONIC))
    assert.is_not_nil(shown(tracker, "upkeepBuffs", OVERLOAD))
    assert.is_nil(shown(tracker, "combatBuffs", AFTERSHOCK) or shown(tracker, "upkeepBuffs", AFTERSHOCK))
  end)

  it("places a buff by its saved category over its first time left", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(SONIC, "20"))
    assert.is_not_nil(shown(tracker, "upkeepBuffs", SONIC, { [tostring(SONIC)] = "upkeep" }))
    assert.is_nil(shown(tracker, "combatBuffs", SONIC, { [tostring(SONIC)] = "hidden" }))
  end)

  it("shows the label's time and stacks, and drops a buff the bar no longer shows", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(INCITE, "20<br>(5)"))
    local model = shown(tracker, "combatBuffs", INCITE)
    assert.are.same({ "20", "5" }, { model.text, model.stacks })
    tracker.onTick(buffs())
    assert.is_nil(shown(tracker, "combatBuffs", INCITE))
  end)

  it("keeps the full length while time falls and raises it when a refresh raises the time left", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(INCITE, "20"))
    tracker.onTick(buffs(INCITE, "19"))
    tracker.onTick(buffs(INCITE, "12"))
    local falling = shown(tracker, "combatBuffs", INCITE)
    assert.are.same({ 20, 12 }, { falling.full, falling.left })

    tracker.onTick(buffs(INCITE, "30"))
    local refreshed = shown(tracker, "combatBuffs", INCITE)
    assert.are.same({ 30, 30 }, { refreshed.full, refreshed.left })
  end)

  it("highlights an icon in the last 10% of its full length, or its last 3 seconds when that is longer", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(SONIC, "50"))
    tracker.onTick(buffs(SONIC, "6"))
    assert.is_false(shown(tracker, "combatBuffs", SONIC).highlight)
    tracker.onTick(buffs(SONIC, "5"))
    assert.is_true(shown(tracker, "combatBuffs", SONIC).highlight)
    tracker.onTick(buffs(INCITE, "20"))
    tracker.onTick(buffs(INCITE, "4"))
    assert.is_false(shown(tracker, "combatBuffs", INCITE).highlight)
    tracker.onTick(buffs(INCITE, "3"))
    assert.is_true(shown(tracker, "combatBuffs", INCITE).highlight)
    tracker.onTick(buffs(AFTERSHOCK, "47%"))
    assert.is_false(shown(tracker, "combatBuffs", AFTERSHOCK, { [tostring(AFTERSHOCK)] = "combat" }).highlight)
  end)

  it("highlights a short time only once it has fallen", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(INCITE, "3"))
    assert.is_false(shown(tracker, "combatBuffs", INCITE).highlight)
    tracker.onTick(buffs(INCITE, "2"))
    assert.is_true(shown(tracker, "combatBuffs", INCITE).highlight)
  end)

  it("shows a seconds label that holds for 4 ticks as a count, with no timer or highlight", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(BLOODLUST, "5"))
    tracker.onTick(buffs(BLOODLUST, "4"))
    for _ = 1, 2 do tracker.onTick(buffs(BLOODLUST, "4")) end
    assert.is_not_nil(shown(tracker, "combatBuffs", BLOODLUST).left)
    tracker.onTick(buffs(BLOODLUST, "4"))
    local count = shown(tracker, "combatBuffs", BLOODLUST)
    assert.are.same({ "4", nil, nil, false }, { count.text, count.left, count.fill, count.highlight })
    tracker.onTick(buffs(BLOODLUST, "2"))
    assert.is_nil(shown(tracker, "combatBuffs", BLOODLUST).left)
  end)

  it("counts a minute label down by ticks inside its minute and resyncs when the label changes", function()
    local tracker = auras.tracker()
    tracker.onTick(buffs(OVERLOAD, "6m"))
    assert.are.equal(419, shown(tracker, "upkeepBuffs", OVERLOAD).left)
    for _ = 1, 10 do tracker.onTick(buffs(OVERLOAD, "6m")) end
    assert.are.equal(413, shown(tracker, "upkeepBuffs", OVERLOAD).left)
    for _ = 1, 200 do tracker.onTick(buffs(OVERLOAD, "6m")) end
    assert.are.equal(360, shown(tracker, "upkeepBuffs", OVERLOAD).left)
    assert.is_false(shown(tracker, "upkeepBuffs", OVERLOAD).highlight)
    tracker.onTick(buffs(OVERLOAD, "5m"))
    local model = shown(tracker, "upkeepBuffs", OVERLOAD)
    assert.are.same({ 359, 419, "5m" }, { model.left, model.full, model.text })
  end)

  it("shows every player debuff in bar order and every target debuff without a timer", function()
    local tracker = auras.tracker()
    tracker.onTick({ buffs = {}, debuffs = { { sprite = STUN, label = "4" }, { sprite = 26402, label = "" } } })
    local rows = tracker.rows({}, { 30098, 30212 })
    assert.are.same({ STUN, 26402 }, { rows.playerDebuffs[1].sprite, rows.playerDebuffs[2].sprite })
    assert.are.same({ "4", nil }, { rows.playerDebuffs[1].text, rows.playerDebuffs[2].text })
    assert.are.same({ { sprite = 30098 }, { sprite = 30212 } }, rows.targetDebuffs)
  end)

  it("holds at most 10 icons per row", function()
    local tracker = auras.tracker()
    local reads = { buffs = {}, debuffs = {} }
    for i = 1, 12 do reads.debuffs[i] = { sprite = 1000 + i, label = "9" } end
    tracker.onTick(reads)
    local targets = {}
    for i = 1, 12 do targets[i] = 2000 + i end
    local rows = tracker.rows({}, targets)
    assert.are.same({ 10, 10 }, { #rows.playerDebuffs, #rows.targetDebuffs })
  end)
end)
