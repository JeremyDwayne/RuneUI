_G.log = function() end
_G.var = { VarPlayer = {} }
local adapter = require("src/adapter")

-- The worn inventory as the client returns it: valid reads nil and slots hold ObjType proxies.
local function wearing(...)
  local slots = {}
  for i, name in ipairs({ ... }) do slots[i] = { obj = { name = name }, count = 1 } end
  slots[#slots + 1] = { obj = { name = "" }, count = 0 }
  _G.Inventory = { Find = function() return { GetSlots = function() return slots end } end }
end

describe("adapter.resourceReads", function()
  it("detects a worn soulbound lantern, augmented or not, rescanning only when worn gear changes", function()
    wearing("Crown of the First Necromancer", "Augmented Soulbound lantern")
    adapter.inventoryChanged({ inv = { id = 94 } })
    assert.is_true(adapter.resourceReads({}).lantern)
    wearing("Crown of the First Necromancer")
    adapter.inventoryChanged({ inv = { id = 93 } })
    assert.is_true(adapter.resourceReads({}).lantern)
    adapter.inventoryChanged({ inv = { id = 94 } })
    assert.is_false(adapter.resourceReads({}).lantern)
  end)
end)

-- Interface 1490 as the client builds it: static components, one holding a dynamic border sprite.
local function loadTargetPanel()
  local border = { alpha = 1, categoryID = 0, dynamicID = 0 }
  local panel = {
    [0] = { alpha = 1 },
    [21] = { alpha = 1 },
    [26] = { alpha = 0.5, IterateDynamicComponents = function(_, fn) fn(border) end },
  }
  _G.ui = { Interfaces = { GetComponent = function(_, interfaceID, staticID)
    if interfaceID == 1490 then return panel[staticID] end
  end } }
  return panel, border
end

describe("adapter.hideTargetPanel", function()
  it("makes every panel component transparent, again after a reload, and restores original alphas", function()
    local panel, border = loadTargetPanel()
    adapter.hideTargetPanel(true)
    assert.are.same({ 0, 0, 0, 0 }, { panel[0].alpha, panel[21].alpha, panel[26].alpha, border.alpha })

    panel = loadTargetPanel()
    adapter.hideTargetPanel(true)
    assert.are.equal(0, panel[21].alpha)

    adapter.hideTargetPanel(false)
    assert.are.same({ 1, 1, 0.5 }, { panel[0].alpha, panel[21].alpha, panel[26].alpha })
  end)

  it("hides a dynamic child whose ids cannot be read", function()
    local panel, border = loadTargetPanel()
    setmetatable(border, { __index = function(_, field) error("no field " .. field) end })
    border.categoryID, border.dynamicID = nil, nil
    adapter.hideTargetPanel(true)
    assert.are.equal(0, border.alpha)
    adapter.hideTargetPanel(false)
    assert.are.equal(1, panel[0].alpha)
  end)
end)
