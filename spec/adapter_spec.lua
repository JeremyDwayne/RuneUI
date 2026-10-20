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

-- Interface 1490 as the client builds it: static components, :26 holding a dynamic border sprite and :25 a
-- dynamic background sprite. rebuild() replaces both sprites with new opaque ones, as the client does.
local function loadTargetPanel()
  local border = { alpha = 1, categoryID = 0, dynamicID = 0 }
  local background = { alpha = 1, categoryID = 0, dynamicID = 0 }
  local panel = {
    [0] = { alpha = 1 },
    [21] = { alpha = 1 },
    [25] = { alpha = 1, IterateDynamicComponents = function(_, fn) fn(background) end },
    [26] = { alpha = 0.5, IterateDynamicComponents = function(_, fn) fn(border) end },
  }
  _G.ui = { Interfaces = { lookups = 0, GetComponent = function(self, interfaceID, staticID, categoryID)
    self.lookups = self.lookups + 1
    if interfaceID ~= 1490 then return nil end
    if categoryID == nil then return panel[staticID] end
    if staticID == 25 then return background end
  end } }
  local function rebuild()
    border = { alpha = 1, categoryID = 0, dynamicID = 0 }
    background = { alpha = 1, categoryID = 0, dynamicID = 0 }
    return border, background
  end
  return panel, border, rebuild
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

  it("makes rebuilt border and background sprites transparent on the next frame", function()
    local panel, _, rebuild = loadTargetPanel()
    adapter.hideTargetPanel(true)
    local border, background = rebuild()
    adapter.keepTargetPanelHidden()
    assert.are.same({ 0, 0, 0 }, { panel[21].alpha, border.alpha, background.alpha })
    adapter.hideTargetPanel(false)
  end)

  it("makes no client reads on a frame while the panel is shown", function()
    loadTargetPanel()
    adapter.keepTargetPanelHidden()
    assert.are.equal(0, ui.Interfaces.lookups)
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

describe("adapter.targetReads", function()
  it("lists only the debuff slots the panel shows, since expired slots keep their icon while invisible", function()
    _G.var = { VarPlayer = { NPCTARGET = { value = 25126 } }, VarClient = {} }
    local slots = {
      [38] = { spriteID = 30097, visibleGlobal = true },
      [41] = { spriteID = 30212, visibleGlobal = false },
      [44] = { spriteID = 30098, visibleGlobal = true },
      [47] = { spriteID = -1, visibleGlobal = false },
    }
    _G.ui = { Interfaces = { GetComponent = function(_, interfaceID, staticID)
      if interfaceID == 1490 then return slots[staticID] end
    end } }
    assert.are.same({ 30097, 30098 }, adapter.targetReads().debuffs)
  end)
end)

describe("adapter.spriteName", function()
  it("names a sprite by id, and reads nil when the client has no name or raises", function()
    _G.id = { Sprite = { FromID = function(sprite)
      if sprite == 30212 then return "DEBUFF_ICON_NECROMANCY_HAUNTED" end
      if sprite == -2 then error("bad id") end
    end } }
    assert.are.equal("DEBUFF_ICON_NECROMANCY_HAUNTED", adapter.spriteName(30212))
    assert.is_nil(adapter.spriteName(30098))
    assert.is_nil(adapter.spriteName(-2))
  end)
end)

describe("adapter.auraReads", function()
  it("reads shown icons with their labels, skipping item icons, hidden slots and slots past an empty run", function()
    -- { sprite, label, label visibleGlobal } per 284 slot from :19. Visibility comes from the label, since
    -- RuneUI hides the icons themselves.
    local slots = {
      [19] = { 30093, "6m", true }, [20] = { -1, "5m", true }, [21] = { 18857, "", false },
      [22] = { 14766, "20<br>(5)", true }, [27] = { 27432, "9", true },
    }
    _G.ui = { Interfaces = { GetComponent = function(_, interfaceID, staticID, _, dynamicID)
      local slot = interfaceID == 284 and slots[staticID]
      if not slot then return nil end
      if dynamicID == 0 then return { spriteID = slot[1], visibleGlobal = false } end
      return { content = slot[2], visibleGlobal = slot[3] }
    end } }
    assert.are.same({
      buffs = { { sprite = 30093, label = "6m" }, { sprite = 14766, label = "20<br>(5)" } },
      debuffs = {},
    }, adapter.auraReads())
  end)
end)

-- Interface 284 with a static root, a filled slot :19 and an empty slot :20, as the client builds them.
-- fill() replaces :19's children with new shown, opaque ones, as the client does when a buff fills the slot.
local function loadBuffBar()
  local function children()
    local list = {}
    for dynamic = 0, 3 do list[dynamic] = { alpha = 1, hidden = false, categoryID = 0, dynamicID = dynamic } end
    return list
  end
  local bar = { root = { alpha = 1 }, slot = children() }
  local statics = {
    [0] = bar.root,
    [19] = { alpha = 1, IterateDynamicComponents = function(_, fn)
      for dynamic = 0, 3 do fn(bar.slot[dynamic]) end
    end },
  }
  bar.interfaces = { lookups = 0, GetComponent = function(self, interfaceID, staticID, _, dynamicID)
    self.lookups = self.lookups + 1
    if interfaceID ~= 284 then return nil end
    if dynamicID == nil then return statics[staticID] end
    return staticID == 19 and bar.slot[dynamicID] or nil
  end }
  _G.ui = { Interfaces = bar.interfaces }
  function bar.fill() bar.slot = children() end
  return bar
end

describe("adapter.hideBuffBars", function()
  it("hides slot icons, makes the rest transparent, and restores both when turned off", function()
    local bar = loadBuffBar()
    adapter.hideBuffBars(true)
    local slot = bar.slot
    assert.are.same({ 0, true, false, 0, true, 0 },
      { bar.root.alpha, slot[0].hidden, slot[1].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha })
    adapter.hideBuffBars(false)
    assert.are.same({ 1, false, 1, false, 1 }, { bar.root.alpha, slot[0].hidden, slot[1].alpha, slot[2].hidden,
      slot[3].alpha })
  end)

  it("hides a slot again in the frames after a tick once the client fills it", function()
    local bar = loadBuffBar()
    adapter.hideBuffBars(true)
    adapter.hideBuffBars(true)
    bar.fill()
    adapter.keepBuffBarsHidden()
    assert.are.same({ true, 0, true, 0 }, { bar.slot[0].hidden, bar.slot[1].alpha, bar.slot[2].hidden,
      bar.slot[3].alpha })
    adapter.hideBuffBars(false)
  end)

  it("makes no client reads on a frame while the bars are shown or long after a tick", function()
    local bar = loadBuffBar()
    adapter.keepBuffBarsHidden()
    assert.are.equal(0, bar.interfaces.lookups)
    adapter.hideBuffBars(true)
    for _ = 1, 20 do adapter.keepBuffBarsHidden() end
    bar.interfaces.lookups = 0
    adapter.keepBuffBarsHidden()
    assert.are.equal(0, bar.interfaces.lookups)
    adapter.hideBuffBars(false)
  end)
end)
