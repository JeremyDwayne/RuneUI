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

describe("editor.gridDropTarget", function()
  -- Five 36px tiles 38px apart in rows of 3: two in the second row.
  local GRID = { count = 5, step = 38, size = 36, perRow = 3 }

  it("counts the index across rows for the row under the cursor", function()
    assert.are.same({ kind = "swap", index = 5 }, editor.gridDropTarget(GRID, 56, 50))
    assert.are.same({ kind = "insert", index = 6 }, editor.gridDropTarget(GRID, 200, 50))
  end)

  it("keeps a cursor above or below the grid on its first or last row", function()
    assert.are.same({ kind = "insert", index = 1 }, editor.gridDropTarget(GRID, 0, -20))
    assert.are.same({ kind = "swap", index = 4 }, editor.gridDropTarget(GRID, 18, 400))
  end)
end)

describe("editor.dropAction", function()
  local list = { "A", "B", "C" }

  it("swaps with the tile under the cursor", function()
    assert.are.same({ op = "swap", other = "C" }, editor.dropAction(list, "A", { kind = "swap", index = 3 }))
  end)

  it("accounts for the dragged tile's own slot when moving it later in the list", function()
    assert.are.same({ op = "move", index = 2 }, editor.dropAction(list, "A", { kind = "insert", index = 3 }))
    assert.are.same({ op = "move", index = 1 }, editor.dropAction(list, "C", { kind = "insert", index = 1 }))
  end)

  it("does nothing when a tile is dropped on itself or back in its own slot", function()
    assert.is_nil(editor.dropAction(list, "B", { kind = "swap", index = 2 }))
    assert.is_nil(editor.dropAction(list, "B", { kind = "insert", index = 3 }))
  end)
end)

describe("editor.pickerSections", function()
  local function groups(rotation, utility)
    return {
      { name = "major", title = "Major", keys = {} },
      { name = "rotation", title = "Rotation", keys = rotation },
      { name = "utility", title = "Utility", keys = utility },
    }
  end

  it("lists abilities in no group, then each other group's, leaving out the open group's", function()
    assert.are.same({
      { title = "Not shown", keys = { "N" } },
      { title = "In Major", keys = {} },
      { title = "In Utility", keys = { "X" } },
    }, editor.pickerSections("rotation", groups({ "A" }, { "X" }), { "A", "N", "X" }))
  end)

  it("keeps a style's abilities and the style-free ones when given a style", function()
    local keys = { "MAGIC_SUNSHINE", "NECROMANCY_SOUL_SAP", "DEFENCE_FREEDOM", "STRENGTH_DESTROY" }
    assert.are.same(
      { "MAGIC_SUNSHINE", "DEFENCE_FREEDOM" },
      editor.pickerSections("rotation", groups({}, {}), keys, "magic")[1].keys
    )
    assert.are.same(
      { "DEFENCE_FREEDOM", "STRENGTH_DESTROY" },
      editor.pickerSections("rotation", groups({}, {}), keys, "melee")[1].keys
    )
  end)
end)
