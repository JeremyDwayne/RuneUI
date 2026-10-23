local autohide = require("src/autohide")

-- An appearance with the Out of combat settings at mode, 30 percent, showing with a target unless withTarget
-- is false.
local function appearance(mode, withTarget)
  return { outOfCombat = mode, outOfCombatOpacity = 30, showWithTarget = withTarget ~= false }
end

describe("autohide", function()
  it("keeps the HUD at full in combat, and before the combat var is read", function()
    for _, mode in ipairs({ "show", "fade", "hide" }) do
      assert.are.same({ false, 1 }, { autohide.state(appearance(mode), 1, false, false) }, mode)
      assert.are.same({ false, 1 }, { autohide.state(appearance(mode), nil, false, false) }, mode)
    end
  end)

  it("fades the HUD to the saved opacity or hides it out of combat", function()
    assert.are.same({ false, 1 }, { autohide.state(appearance("show"), 0, false, false) })
    assert.are.same({ false, 0.3 }, { autohide.state(appearance("fade"), 0, false, false) })
    assert.are.same({ true, 1 }, { autohide.state(appearance("hide"), 0, false, false) })
  end)

  it("shows the HUD at full out of combat while the player has a target, unless that is off", function()
    assert.are.same({ false, 1 }, { autohide.state(appearance("hide"), 0, true, false) })
    assert.are.same({ false, 1 }, { autohide.state(appearance("fade"), 0, true, false) })
    assert.are.same({ true, 1 }, { autohide.state(appearance("hide", false), 0, true, false) })
    assert.are.same({ false, 0.3 }, { autohide.state(appearance("fade", false), 0, true, false) })
  end)

  it("shows the HUD at full while the options window or edit mode is open", function()
    assert.are.same({ false, 1 }, { autohide.state(appearance("hide", false), 0, false, true) })
    assert.are.same({ false, 1 }, { autohide.state(appearance("fade", false), 0, false, true) })
  end)

  it("reads the combat var only while the setting is not Show", function()
    assert.is_false(autohide.reads(appearance("show")))
    assert.is_true(autohide.reads(appearance("fade")))
    assert.is_true(autohide.reads(appearance("hide")))
  end)
end)
