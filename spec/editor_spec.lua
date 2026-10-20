local editor = require("src/editor")

-- Three 42px tiles 44px apart starting at x = 0: centres at 21, 65 and 109.
local ROW = { count = 3, step = 44, size = 42, offset = 0 }

describe("editor.dropTarget", function()
  it("swaps when dropped on the middle of a tile", function()
    assert.are.same({ kind = "swap", index = 2 }, editor.dropTarget(ROW, 66))
  end)

  it("inserts before or after a tile outside its middle, and at the end past the last tile", function()
    assert.are.same({ kind = "insert", index = 2 }, editor.dropTarget(ROW, 50))
    assert.are.same({ kind = "insert", index = 3 }, editor.dropTarget(ROW, 80))
    assert.are.same({ kind = "insert", index = 4 }, editor.dropTarget(ROW, 200))
  end)

  it("inserts first into an empty row", function()
    local empty = { count = 0, step = 44, size = 42, offset = 0 }
    assert.are.same({ kind = "insert", index = 1 }, editor.dropTarget(empty, 30))
  end)
end)

describe("editor.dropAction", function()
  local groups = { rotation = { "A", "B", "C" }, cooldowns = { "X" } }

  it("swaps with the tile under the cursor", function()
    assert.are.same({ op = "swap", other = "X" },
      editor.dropAction(groups, "A", "cooldowns", { kind = "swap", index = 1 }))
  end)

  it("accounts for the dragged tile's own slot when moving it later in its group", function()
    assert.are.same({ op = "move", group = "rotation", index = 2 },
      editor.dropAction(groups, "A", "rotation", { kind = "insert", index = 3 }))
    assert.are.same({ op = "move", group = "cooldowns", index = 2 },
      editor.dropAction(groups, "A", "cooldowns", { kind = "insert", index = 2 }))
  end)

  it("does nothing when a tile is dropped on itself", function()
    assert.is_nil(editor.dropAction(groups, "B", "rotation", { kind = "swap", index = 2 }))
  end)
end)

describe("editor.pickerSections", function()
  it("lists abilities in neither group, then the other group's, leaving out the open group's", function()
    local groups = { rotation = { "A" }, cooldowns = { "X" } }
    assert.are.same({
      { title = "Not shown", keys = { "N" } },
      { title = "In cooldowns", keys = { "X" } },
    }, editor.pickerSections("rotation", groups, { "A", "N", "X" }))
  end)
end)
