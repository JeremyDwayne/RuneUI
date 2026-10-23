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
    fake.hook(stepper.buttons[2].bg, "ONCLICK", 0, 0)
    stepper.show(50)
    fake.hook(stepper.buttons[2].bg, "ONCLICK", 0, 0)
    fake.hook(stepper.buttons[1].bg, "ONCLICK", 0, 0)
    assert.are.same({ 50, 50, 40 }, savedValues)
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
