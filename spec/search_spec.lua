local search = require("src/search")

-- Catalog rows: Stunned is a General struct that Telos also applies, and 14235 is the sprite of Flames of
-- Zamorak and Shadow Tear.
local ROWS = {
  { sprite = 26103, name = "Stunned", struct = 100, source = "General" },
  { sprite = 26103, name = "Stunned", struct = 100, source = "Telos", cause = "Double Tap" },
  { sprite = 800, name = "Red virus", struct = 33657, source = "Telos" },
  { sprite = 14235, name = "Flames of Zamorak", struct = 41806, source = "Zamorak" },
  { sprite = 14235, name = "Shadow Tear", struct = 51850, source = "Amascut" },
  { sprite = 20000, name = "Soul Split", struct = 200, source = "Curses" },
}

local function names(rows)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r.name
  end
  return out
end

describe("search.sources", function()
  it("lists All first, then the groups, then bosses by name, each with its count", function()
    assert.are.same({
      { name = "All", count = 5 },
      { name = "General", count = 1 },
      { name = "Curses", count = 1 },
      { name = "Amascut", count = 1 },
      { name = "Telos", count = 2 },
      { name = "Zamorak", count = 1 },
    }, search.sources(ROWS, ""))
  end)

  it("counts only matches on effect, source and cause names, ignoring case", function()
    assert.are.same({ { name = "All", count = 2 }, { name = "Telos", count = 2 } }, search.sources(ROWS, "TELOS"))
    assert.are.same({ { name = "All", count = 1 }, { name = "Telos", count = 1 } }, search.sources(ROWS, "double"))
    assert.are.same({ { name = "All", count = 1 }, { name = "Zamorak", count = 1 } }, search.sources(ROWS, "flames"))
  end)
end)

describe("search.rows", function()
  it("lists a shared effect under its boss and under General", function()
    assert.are.same({ "Red virus", "Stunned" }, names(search.rows(ROWS, "Telos", "", {})))
    assert.are.same({ "Stunned" }, names(search.rows(ROWS, "General", "", {})))
    assert.are.equal("Double Tap", search.rows(ROWS, "Telos", "", {})[2].cause)
  end)

  it("reads every row of a tracked sprite as tracked", function()
    local rows = search.rows(ROWS, "All", "", { [14235] = true })
    local tracked = {}
    for _, r in ipairs(rows) do
      tracked[r.name] = r.tracked
    end
    assert.are.same({
      ["Flames of Zamorak"] = true,
      ["Shadow Tear"] = true,
      Stunned = false,
      ["Red virus"] = false,
      ["Soul Split"] = false,
    }, tracked)
  end)
end)

describe("search.withSeen", function()
  it("adds seen sprites the catalog lacks to General, named by name(sprite)", function()
    local rows = search.withSeen(ROWS, { 26103, 30098 }, function(sprite)
      return sprite == 30098 and "Bloated" or nil
    end)
    assert.are.same({ "Bloated", "Stunned" }, names(search.rows(rows, "General", "", {})))
    assert.are.equal(30098, search.rows(rows, "General", "bloat", {})[1].sprite)
  end)
end)
