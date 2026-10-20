local auralists = require("src/auralists")

local BLOATED, STUN_IMMUNE, STUNNED, BONE_SHIELD, OVERLOAD = 30098, 26104, 26103, 30099, 30093

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
  it("lists buffs by row and each debuff kind by tracked or not, with defaults once, sorted by sprite", function()
    local groups = auralists.groups(
      { [tostring(OVERLOAD)] = "upkeep", [tostring(BONE_SHIELD)] = "hidden", ["14766"] = "combat" },
      { target = { [tostring(STUN_IMMUNE)] = "seen", [tostring(BLOATED)] = true }, player = { ["555"] = "seen" } })
    assert.are.same({ { 14766 }, { OVERLOAD }, { BONE_SHIELD } }, { groups.combat, groups.upkeep, groups.hidden })
    assert.are.same({ STUN_IMMUNE }, groups.target.untracked)
    local count = 0
    for i, sprite in ipairs(groups.target.tracked) do
      if sprite == BLOATED then count = count + 1 end
      if i > 1 then assert.is_true(groups.target.tracked[i - 1] < sprite) end
    end
    assert.are.equal(1, count)
    assert.are.same({ 555 }, groups.player.untracked)
  end)
end)
