local search = require("src/search")

-- Catalog rows: Stunned is a General debuff on you that Telos also applies and a debuff you inflict with any
-- style, and 14235 is the sprite of Flames of Zamorak and Shadow Tear.
local ROWS = {
  { sprite = 26103, name = "Stunned", struct = 100, source = "General", kind = "debuff" },
  { sprite = 26103, name = "Stunned", struct = 100, source = "Telos", kind = "debuff", cause = "Double Tap" },
  { sprite = 800, name = "Red virus", struct = 33657, source = "Telos", kind = "debuff" },
  { sprite = 14235, name = "Flames of Zamorak", struct = 41806, source = "Zamorak", kind = "debuff" },
  { sprite = 14235, name = "Shadow Tear", struct = 51850, source = "Amascut", kind = "debuff" },
  { sprite = 20000, name = "Soul Split", struct = 200, source = "Curses", kind = "buff" },
  { sprite = 26103, name = "Stunned", struct = 100, source = "Any style", kind = "target", cause = "Stuns" },
  { sprite = 14395, name = "Vulnerability", struct = 300, source = "Magic", kind = "target", cause = "Vulnerability" },
}

local function names(rows)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r.name
  end
  return out
end

describe("search.sources", function()
  it("lists All first, then the groups, then bosses by name, each with its count of one kind", function()
    assert.are.same({
      { name = "All", count = 4 },
      { name = "General", count = 1 },
      { name = "Amascut", count = 1 },
      { name = "Telos", count = 2 },
      { name = "Zamorak", count = 1 },
    }, search.sources(ROWS, "debuff", ""))
  end)

  it("lists a debuff you inflict by combat style, styles in their fixed order", function()
    assert.are.same(
      { { name = "All", count = 2 }, { name = "Magic", count = 1 }, { name = "Any style", count = 1 } },
      search.sources(ROWS, "target", "")
    )
  end)

  it("counts only matches on effect, source and cause names, ignoring case", function()
    assert.are.same(
      { { name = "All", count = 2 }, { name = "Telos", count = 2 } },
      search.sources(ROWS, "debuff", "TELOS")
    )
    assert.are.same(
      { { name = "All", count = 1 }, { name = "Telos", count = 1 } },
      search.sources(ROWS, "debuff", "double")
    )
    assert.are.same(
      { { name = "All", count = 1 }, { name = "Zamorak", count = 1 } },
      search.sources(ROWS, "debuff", "flames")
    )
  end)
end)

describe("search.rows", function()
  it("lists a shared effect under its boss and under General", function()
    assert.are.same({ "Red virus", "Stunned" }, names(search.rows(ROWS, "debuff", "Telos", "", {})))
    assert.are.same({ "Stunned" }, names(search.rows(ROWS, "debuff", "General", "", {})))
    assert.are.equal("Double Tap", search.rows(ROWS, "debuff", "Telos", "", {})[2].cause)
  end)

  it("lists only rows of its kind", function()
    assert.are.same({ "Stunned", "Vulnerability" }, names(search.rows(ROWS, "target", "All", "", {})))
    assert.are.same({ "Soul Split" }, names(search.rows(ROWS, "buff", "All", "", {})))
  end)

  it("reads every row of a tracked sprite as tracked", function()
    local rows = search.rows(ROWS, "debuff", "All", "", { [14235] = true })
    local tracked = {}
    for _, r in ipairs(rows) do
      tracked[r.name] = r.tracked
    end
    assert.are.same(
      { ["Flames of Zamorak"] = true, ["Shadow Tear"] = true, Stunned = false, ["Red virus"] = false },
      tracked
    )
  end)
end)

describe("search.withSeen", function()
  it("adds seen sprites the catalog lacks for a kind to General, named by name(sprite)", function()
    local rows = search.withSeen(ROWS, "debuff", { 26103, 30098 }, function(sprite)
      return sprite == 30098 and "Bloated" or nil
    end)
    assert.are.same({ "Bloated", "Stunned" }, names(search.rows(rows, "debuff", "General", "", {})))
    assert.are.equal(30098, search.rows(rows, "debuff", "General", "bloat", {})[1].sprite)
    local buffs = search.withSeen(ROWS, "buff", { 26103 }, function() end)
    assert.are.same({ "Unknown effect" }, names(search.rows(buffs, "buff", "General", "", {})))
  end)

  it("adds seen target sprites the catalog lacks to Any style, the target tab having no General", function()
    local rows = search.withSeen(ROWS, "target", { 30098 }, function()
      return "Bloated"
    end)
    assert.are.same({ "Bloated", "Stunned" }, names(search.rows(rows, "target", "Any style", "", {})))
  end)
end)
