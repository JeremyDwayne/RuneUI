local auralists = require("src/auralists")

local BLOATED, STUN_IMMUNE, STUNNED, BONE_SHIELD, ANTIFIRE = 30098, 26104, 26103, 30099, 30093
local VULNERABILITY, DEATH_MARK, HAUNTED = 14395, 30100, 30212

describe("auralists.tracked", function()
  it("tracks a default debuff with no saved choice and leaves others untracked", function()
    assert.is_true(auralists.tracked("target", {}, BLOATED))
    assert.is_false(auralists.tracked("target", {}, STUN_IMMUNE))
    assert.is_true(auralists.tracked("player", {}, STUNNED))
    assert.is_false(auralists.tracked("player", {}, BLOATED))
  end)

  it("takes a saved choice over the default either way", function()
    local choices = { [tostring(BLOATED)] = false, [tostring(STUN_IMMUNE)] = true }
    assert.is_false(auralists.tracked("target", choices, BLOATED))
    assert.is_true(auralists.tracked("target", choices, STUN_IMMUNE))
  end)
end)

describe("auralists.groups", function()
  it("lists buffs by row and each debuff kind by tracked or not, with defaults once", function()
    local groups = auralists.groups(
      { [tostring(ANTIFIRE)] = "upkeep", [tostring(BONE_SHIELD)] = "hidden", ["14766"] = "combat" },
      { target = { [tostring(STUN_IMMUNE)] = "seen", [tostring(BLOATED)] = true }, player = { ["555"] = "seen" } }, {})
    assert.are.same({ { 14766 }, { ANTIFIRE }, { BONE_SHIELD } }, { groups.combat, groups.upkeep, groups.hidden })
    assert.are.same({ STUN_IMMUNE }, groups.target.untracked)
    assert.are.equal(#auralists.TARGET_DEFAULTS, #groups.target.tracked)
    assert.are.same({ 555 }, groups.player.untracked)
  end)

  it("orders each kind by its saved order, then default importance, then sprite id", function()
    local categories = { ["27432"] = "combat", ["14766"] = "combat", ["20184"] = "combat" }
    local choices = { target = { [tostring(STUN_IMMUNE)] = true, ["555"] = true }, player = {} }
    local groups = auralists.groups(categories, choices, { buffs = { 27432 }, target = { HAUNTED, BLOATED } })
    assert.are.same({ 27432, 14766, 20184 }, groups.combat)
    local tracked = groups.target.tracked
    assert.are.same({ HAUNTED, BLOATED, VULNERABILITY, DEATH_MARK }, { tracked[1], tracked[2], tracked[3], tracked[4] })
    assert.are.same({ 555, STUN_IMMUNE }, { tracked[#tracked - 1], tracked[#tracked] })
    assert.are.equal(27432, groups.order.buffs[1])
  end)
end)

describe("auralists.drop", function()
  local A, B, C, D = 1, 2, 3, 4

  it("inserts an icon between two others in its own group", function()
    local moved = auralists.drop({ A, B, C, D }, { A, B, C }, A, { kind = "insert", index = 3 })
    assert.are.same({ order = { B, A, C, D } }, moved)
  end)

  it("inserts an icon into another group before the icon at the index, or after its last", function()
    local first = auralists.drop({ A, B, C, D }, { B, C }, D, { kind = "insert", index = 1 })
    local last = auralists.drop({ A, D, B, C }, { B, C }, D, { kind = "insert", index = 3 })
    assert.are.same({ { order = { A, D, B, C } }, { order = { A, B, C, D } } }, { first, last })
  end)

  it("swaps an icon with the one it is dropped on, and ignores a drop on itself", function()
    assert.are.same({ order = { C, B, A, D }, other = C },
      auralists.drop({ A, B, C, D }, { C, D }, A, { kind = "swap", index = 1 }))
    assert.is_nil(auralists.drop({ A, B }, { A, B }, A, { kind = "swap", index = 1 }))
  end)

  it("keeps the order when inserting into an empty group", function()
    assert.are.same({ order = { A, B } }, auralists.drop({ A, B }, {}, B, { kind = "insert", index = 1 }))
  end)
end)
