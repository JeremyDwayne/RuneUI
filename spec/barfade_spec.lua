local barfade = require("src/barfade")

-- A part's state as { hidden, scale }.
local function state(part, level)
  return { barfade.state(part, level) }
end

describe("barfade.level", function()
  it("fades a bar with Fade on to its own opacity, and at full while hovered with Show on hover on", function()
    local appearance = {
      barOpacity1 = 25,
      fadeBar1 = true,
      hoverBar1 = true,
      barOpacity2 = 60,
      fadeBar2 = true,
      hoverBar2 = false,
      barOpacity3 = 40,
    }
    assert.are.same({ 25, 100, 60, 100 }, {
      barfade.level(appearance, 1, false),
      barfade.level(appearance, 1, true),
      barfade.level(appearance, 2, true),
      barfade.level(appearance, 3, false),
    })
  end)
end)

describe("barfade.state", function()
  it("hides the frame, flash, queue, highlight and keybind at 0, and draws the rest at 1%", function()
    for _, part in ipairs({ "frame", "flash", "queue", "highlight", "keybind" }) do
      assert.are.same({ true, 1 }, state(part, 0))
    end
    assert.are.same({ false, 0.01 }, state("other", 0))
  end)

  it("hides only the frame, flash, queue and highlight between 5 and 95, and scales the rest by the level", function()
    assert.are.same({ true, 1 }, state("flash", 25))
    assert.are.same({ true, 1 }, state("highlight", 95))
    assert.are.same({ true, 1 }, state("frame", 5))
    assert.are.same({ false, 0.25 }, state("keybind", 25))
    assert.are.same({ false, 0.05 }, state("other", 5))
  end)

  it("restores every part at 100", function()
    for _, part in ipairs({ "frame", "flash", "queue", "highlight", "keybind", "other" }) do
      assert.are.same({ false, 1 }, state(part, 100))
    end
  end)
end)
