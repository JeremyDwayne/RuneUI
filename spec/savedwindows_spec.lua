local fakeStore = require("spec/support/fake_store")
local savedwindows = require("src/savedwindows")

describe("savedwindows", function()
  it("reads each window's saved opacity, dropping unknown windows, held frames and malformed values", function()
    local s = savedwindows.load(fakeStore({
      windows = { CHAT_WINDOW = 40, INVENTORY_WINDOW = 42, MINIMAP_WINDOW = 100, ACTION_WINDOW = 50, NOPE = 10 },
    }))
    assert.are.same({ CHAT_WINDOW = 40 }, s.windowOpacities())
  end)

  it("saves an opacity on change, clears it at 100 and ignores a value off its steps", function()
    local store = fakeStore()
    local s = savedwindows.load(store)
    s.setWindowOpacity("CHAT_WINDOW", 40)
    s.setWindowOpacity("CHAT_WINDOW", 40)
    s.setWindowOpacity("CHAT_WINDOW", 42)
    assert.are.same({ CHAT_WINDOW = 40 }, savedwindows.load(store).windowOpacities())
    s.setWindowOpacity("CHAT_WINDOW", 100)
    assert.are.same({}, savedwindows.load(store).windowOpacities())
    assert.are.equal(2, store.writes)
  end)
end)
