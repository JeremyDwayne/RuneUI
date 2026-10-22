local barfade = require("src/barfade")

-- A part's state as { hidden, scale }.
local function state(part, level, hideStats)
  return { barfade.state(part, level, hideStats) }
end

describe("barfade.level", function()
  it("fades only a bar with Fade on, and shows it at full while hovered if Show on hover is on", function()
    local appearance = { barOpacity = 25, fadeBar1 = true, hoverBar1 = true, fadeBar2 = true, hoverBar2 = false }
    assert.are.same({ 25, 100, 25, 100 }, {
      barfade.level(appearance, 1, false),
      barfade.level(appearance, 1, true),
      barfade.level(appearance, 2, true),
      barfade.level(appearance, 3, false),
    })
  end)
end)

describe("barfade.state", function()
  it("hides the frame, flash, queue, highlight and keybind at 0, and makes the rest transparent", function()
    for _, part in ipairs({ "frame", "flash", "queue", "highlight", "keybind" }) do
      assert.are.same({ true, 1 }, state(part, 0, false))
    end
    assert.are.same({ { false, 0 }, { false, 0 } }, { state("other", 0, false), state("stats", 0, false) })
  end)

  it("hides only the flash, queue and highlight between 5 and 95, and scales the rest by the level", function()
    assert.are.same({ true, 1 }, state("flash", 25, false))
    assert.are.same({ true, 1 }, state("highlight", 95, false))
    assert.are.same({ false, 0.25 }, state("keybind", 25, false))
    assert.are.same({ false, 0.05 }, state("frame", 5, false))
  end)

  it("restores every part at 100", function()
    for _, part in ipairs({ "frame", "flash", "queue", "highlight", "keybind", "stats", "other" }) do
      assert.are.same({ false, 1 }, state(part, 100, false))
    end
  end)

  it("hides the stats strip at any level once Player stats is Hide", function()
    assert.are.same({ { true, 1 }, { true, 1 }, { true, 1 } }, {
      state("stats", 0, true),
      state("stats", 25, true),
      state("stats", 100, true),
    })
  end)
end)
