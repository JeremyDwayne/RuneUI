local fakeStore = require("spec/support/fake_store")
local savedauras = require("src/savedauras")

describe("savedauras", function()
  it("keeps the first category learned for each buff icon across loads, dropping malformed entries", function()
    local store = fakeStore({ auras = { ["1"] = "sideways", ["2"] = 5 } })
    local s = savedauras.load(store)
    s.learnAura(30093, "upkeep")
    s.learnAura(30093, "combat")
    s.learnAura(26466, "hidden")
    assert.are.same({ ["30093"] = "upkeep", ["26466"] = "hidden" }, savedauras.load(store).auras())
  end)

  it("moves a buff between rows and marks Keep up across loads, dropping malformed entries", function()
    local store = fakeStore({ keepUp = { ["1"] = "yes" } })
    local s = savedauras.load(store)
    s.learnAura(30099, "combat")
    s.setAuraCategory(30099, "hidden")
    s.setKeepUp(30093, true)
    s.setKeepUp(14695, true)
    s.setKeepUp(14695, false)
    local reloaded = savedauras.load(store)
    assert.are.same({ { ["30099"] = "hidden" }, { ["30093"] = true } }, { reloaded.auras(), reloaded.keepUp() })
  end)

  it("lists each debuff seen once and keeps tracked choices per kind, dropping malformed entries", function()
    local store = fakeStore({ trackedTarget = { ["1"] = 5 } })
    local s = savedauras.load(store)
    s.seeDebuff("target", 26104)
    local writes = store.writes
    s.seeDebuff("target", 26104)
    assert.are.equal(writes, store.writes)
    s.setTracked("target", 30098, false)
    s.seeDebuff("target", 30098)
    s.setTracked("player", 26103, true)
    local reloaded = savedauras.load(store)
    assert.are.same({ ["26104"] = "seen", ["30098"] = false }, reloaded.tracked("target"))
    assert.are.same({ ["26103"] = true }, reloaded.tracked("player"))
  end)

  it("drops icon keys that are not whole numbers from every icon map, keeping item icons", function()
    local s = savedauras.load(fakeStore({
      auras = { abc = "upkeep", ["-49039"] = "upkeep" },
      keepUp = { ["1.5"] = true, ["-49039"] = true },
      trackedTarget = { abc = true, ["30098"] = "seen" },
    }))
    assert.are.same({
      { ["-49039"] = "upkeep" },
      { ["-49039"] = true },
      { ["30098"] = "seen" },
    }, { s.auras(), s.keepUp(), s.tracked("target") })
  end)

  it("keeps each kind's icon order across loads, dropping entries that are not whole numbers", function()
    local store = fakeStore({ orderTarget = { 30098.0, "x", 1.5, 14395 } })
    local s = savedauras.load(store)
    s.setOrder("buffs", { 27432, -49039 })
    local orders = savedauras.load(store).orders()
    assert.are.same({ { 27432, -49039 }, { 30098, 14395 }, {} }, { orders.buffs, orders.target, orders.player })
  end)

  it("counts each change to aura rows, tracking or order, and not a repeat of a known icon", function()
    local s = savedauras.load(fakeStore())
    local start = s.auraVersion()
    s.learnAura(30099, "combat")
    s.learnAura(30099, "upkeep")
    s.seeDebuff("target", 26104)
    s.seeDebuff("target", 26104)
    s.setAuraCategory(30099, "hidden")
    s.setTracked("target", 26104, true)
    s.setOrder("buffs", { 30099 })
    assert.are.equal(start + 5, s.auraVersion())
  end)
end)
