local fake = require("spec/support/fake_ui")
local controls = require("src/controls")

describe("controls", function()
  it("steps a stepper's shown number by step inside its bounds and saves each", function()
    fake.reset()
    local savedValues = {}
    local stepper = controls.stepper(fake.component(), 0, 0, 10, 50, 10, function(n)
      savedValues[#savedValues + 1] = n
    end)
    stepper.show(40)
    fake.press("+")
    stepper.show(50)
    fake.press("+")
    fake.press("-")
    assert.are.same({ 50, 50, 40 }, savedValues)
  end)

  it("reports a radio choice the player makes and moves the shown choice only when it changes", function()
    fake.reset()
    local chosen = {}
    local radio = controls.radio(
      fake.component(),
      0,
      0,
      300,
      28,
      {
        { id = "up", label = "Up" },
        { id = "down", label = "Down" },
      },
      2,
      function(value)
        chosen[#chosen + 1] = value
      end
    )
    radio.show("up")
    assert.are.equal("Up", fake.chosen(radio.group))
    fake.press("Down")
    radio.show("down")
    fake.writes = 0
    radio.show("down")
    assert.are.same({ { "down" }, 0 }, { chosen, fake.writes })
    radio.show("up")
    assert.are.equal("Up", fake.chosen(radio.group))
  end)

  it("reports a check box the player ticks, and not a tick the plugin shows", function()
    fake.reset()
    local toggled = {}
    local box = controls.check(fake.component(), 0, 0, 24, function(ticked)
      toggled[#toggled + 1] = ticked
    end)
    box.show(true)
    fake.writes = 0
    box.show(true)
    assert.are.same({ true, 0 }, { box.check.value, fake.writes })
    fake.tick(box.check)
    fake.hook(box.check, "ONBUTTONPRESSED", 0, 1)
    assert.are.same({ false }, toggled)
  end)

  it("unlights a close X when clicked, since its popup closes under the cursor", function()
    fake.reset()
    local closed = false
    local x = controls.closeButton(fake.component(), 0, 0, function()
      closed = true
    end)
    fake.hook(x, "ONMOUSEOVER")
    fake.hook(x, "ONCLICK")
    assert.are.same({ true, "RS3_BTN_MODAL_WINDOW_1_CLOSE_NML" }, { closed, x.sprite })
  end)
end)
