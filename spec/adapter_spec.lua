_G.log = function() end
_G.var = { VarPlayer = {} }
local adapter = require("src/adapter")

-- The worn inventory as the client returns it: valid reads nil and slots hold ObjType proxies.
local function wearing(...)
  local slots = {}
  for i, name in ipairs({ ... }) do
    slots[i] = { obj = { name = name }, count = 1 }
  end
  slots[#slots + 1] = { obj = { name = "" }, count = 0 }
  _G.Inventory = {
    Find = function()
      return {
        GetSlots = function()
          return slots
        end,
      }
    end,
  }
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
    [25] = {
      alpha = 1,
      IterateDynamicComponents = function(_, fn)
        fn(background)
      end,
    },
    [26] = {
      alpha = 0.5,
      IterateDynamicComponents = function(_, fn)
        fn(border)
      end,
    },
  }
  _G.ui = {
    Interfaces = {
      lookups = 0,
      GetComponent = function(self, interfaceID, staticID, categoryID)
        self.lookups = self.lookups + 1
        if interfaceID ~= 1490 then
          return nil
        end
        if categoryID == nil then
          return panel[staticID]
        end
        if staticID == 25 then
          return background
        end
      end,
    },
  }
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
    setmetatable(border, {
      __index = function(_, field)
        error("no field " .. field)
      end,
    })
    border.categoryID = nil
    border.dynamicID = nil
    adapter.hideTargetPanel(true)
    assert.are.equal(0, border.alpha)
    adapter.hideTargetPanel(false)
    assert.are.equal(1, panel[0].alpha)
  end)
end)

-- Interface 764 as the client builds it: the root, the time label :5 and the spark's glow :19.
local function loadCastBar()
  local bar = { [0] = { alpha = 1 }, [5] = { alpha = 1 }, [19] = { alpha = 1, hidden = false } }
  _G.ui = {
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID, categoryID)
        if interfaceID == 764 and categoryID == nil then
          return bar[staticID]
        end
      end,
    },
  }
  return bar
end

describe("adapter.hideCastBar", function()
  it("hides the spark's glow, whose alpha the client animates, and restores it", function()
    local bar = loadCastBar()
    adapter.hideCastBar(true)
    bar[19].alpha = 1
    adapter.keepCastBarHidden()
    assert.are.same({ 0, true }, { bar[0].alpha, bar[19].hidden })
    adapter.hideCastBar(false)
    assert.are.same({ 1, false }, { bar[0].alpha, bar[19].hidden })
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
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID)
          if interfaceID == 1490 then
            return slots[staticID]
          end
        end,
      },
    }
    assert.are.same({ 30097, 30098 }, adapter.targetReads().debuffs)
  end)
end)

describe("adapter.spriteName", function()
  it("names a sprite by id, and reads nil when the client has no name or raises", function()
    _G.id = {
      Sprite = {
        FromID = function(sprite)
          if sprite == 30212 then
            return "DEBUFF_ICON_NECROMANCY_HAUNTED"
          end
          if sprite == -2 then
            error("bad id")
          end
        end,
      },
    }
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
      [19] = { 30093, "6m", true },
      [20] = { -1, "5m", true },
      [21] = { 18857, "", false },
      [22] = { 14766, "20<br>(5)", true },
      [27] = { 27432, "9", true },
    }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, _, dynamicID)
          local slot = interfaceID == 284 and slots[staticID]
          if not slot then
            return nil
          end
          if dynamicID == 0 then
            return { spriteID = slot[1], visibleGlobal = false }
          end
          return { content = slot[2], visibleGlobal = slot[3] }
        end,
      },
    }
    assert.are.same({
      buffs = { { sprite = 30093, label = "6m" }, { sprite = 14766, label = "20<br>(5)" } },
      debuffs = {},
    }, adapter.auraReads())
  end)
end)

-- Interface 284 with a static root and a buff in slot :19, as the client builds it. fill(staticID) gives a
-- slot new shown, opaque children holding a buff, as the client does when a buff fills it.
local function loadBuffBar()
  local bar = { root = { alpha = 1 }, slots = {} }
  local statics = { [0] = bar.root }
  function bar.fill(staticID)
    local children = {}
    for dynamic = 0, 3 do
      children[dynamic] = { alpha = 1, hidden = false, categoryID = 0, dynamicID = dynamic }
    end
    children[0].spriteID, children[1].content = 30093, "6m"
    bar.slots[staticID] = children
    statics[staticID] = statics[staticID]
      or {
        alpha = 1,
        IterateDynamicComponents = function(_, fn)
          for dynamic = 0, 3 do
            fn(bar.slots[staticID][dynamic])
          end
        end,
      }
    return children
  end
  bar.fill(19)
  bar.interfaces = {
    lookups = 0,
    GetComponent = function(self, interfaceID, staticID, _, dynamicID)
      self.lookups = self.lookups + 1
      if interfaceID ~= 284 then
        return nil
      end
      if dynamicID == nil then
        return statics[staticID]
      end
      return bar.slots[staticID] and bar.slots[staticID][dynamicID]
    end,
  }
  _G.ui = { Interfaces = bar.interfaces }
  return bar
end

describe("adapter.hideBuffBars", function()
  it("hides slot icons, makes the rest transparent, and restores both when turned off", function()
    local bar = loadBuffBar()
    adapter.hideBuffBars(true)
    local slot = bar.slots[19]
    assert.are.same(
      { 0, true, false, 0, true, 0 },
      { bar.root.alpha, slot[0].hidden, slot[1].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha }
    )
    adapter.hideBuffBars(false)
    assert.are.same(
      { 1, false, 1, false, 1 },
      { bar.root.alpha, slot[0].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha }
    )
  end)

  it("leaves an icon the client hid hidden when restoring", function()
    local bar = loadBuffBar()
    local slot = bar.fill(20)
    slot[0].hidden, slot[2].hidden = true, true
    adapter.hideBuffBars(true)
    adapter.hideBuffBars(false)
    assert.are.same({ true, true, false }, { slot[0].hidden, slot[2].hidden, bar.slots[19][0].hidden })
  end)

  it("hides a slot again in the frames after a tick once the client fills it", function()
    local bar = loadBuffBar()
    adapter.hideBuffBars(true)
    adapter.hideBuffBars(true)
    local slot = bar.fill(19)
    adapter.keepBuffBarsHidden()
    assert.are.same({ true, 0, true, 0 }, { slot[0].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha })
    adapter.hideBuffBars(false)
  end)

  it("hides a slot a potion fills several slots past the last buff", function()
    local bar = loadBuffBar()
    adapter.hideBuffBars(true)
    adapter.auraReads()
    adapter.hideBuffBars(true)
    local slot = bar.fill(26)
    adapter.keepBuffBarsHidden()
    assert.is_true(slot[0].hidden)
    adapter.hideBuffBars(false)
  end)

  it("makes no client reads on a frame while the bars are shown or long after a tick", function()
    local bar = loadBuffBar()
    adapter.keepBuffBarsHidden()
    assert.are.equal(0, bar.interfaces.lookups)
    adapter.hideBuffBars(true)
    for _ = 1, 20 do
      adapter.keepBuffBarsHidden()
    end
    bar.interfaces.lookups = 0
    adapter.keepBuffBarsHidden()
    assert.are.equal(0, bar.interfaces.lookups)
    adapter.hideBuffBars(false)
  end)
end)

describe("adapter.barSlots", function()
  it("reads each slot's keybind, and that its ability can't be cast while the client dims its icon", function()
    -- Main bar 1430: slot 0 Concentrated Blast on Q, slot 1 Wild Magic dimmed with no keybind.
    local components = {
      [66] = { spriteID = 13309, rgb = 0xffffff },
      [73] = { content = "Q" },
      [79] = { spriteID = 14385, rgb = 0x333333 },
      [86] = { content = "" },
    }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID)
          if interfaceID == 1430 then
            return components[staticID]
          end
        end,
      },
    }
    assert.are.same({ [13309] = { keybind = "Q", usable = true }, [14385] = { usable = false } }, adapter.barSlots())
  end)
end)

-- Action bars as the client builds them: every static of each bar, a child under the stat bar :9 and each
-- window frame static, and the main bar's root in window 1477 at :72. Writes and lookups count every alpha or
-- hidden write and component lookup. load(interfaceID) opens a bar, or rebuilds it at its first alphas.
local BAR_LAYOUTS = { [1430] = { last = 270, content = 72 }, [1670] = { last = 198, content = 77 } }
local function loadActionBars(...)
  local stub = { writes = 0, lookups = 0, bars = {}, window = {} }
  local function component(fields)
    local data = fields or {}
    data.alpha = data.alpha or 1
    data.hidden = data.hidden == true
    data.hooks = {}
    data.children = data.children or {}
    function data.IterateDynamicComponents(_, fn)
      for _, child in ipairs(data.children) do
        fn(child)
      end
    end
    function data.Subscribe(_, hook, _, fn)
      data.hooks[hook] = fn
    end
    function data.Unsubscribe(_, hook)
      data.hooks[hook] = nil
    end
    return setmetatable({}, {
      __index = data,
      __newindex = function(_, key, value)
        stub.writes = stub.writes + 1
        data[key] = value
      end,
    }),
      data
  end
  stub.top, stub.topData = component()
  function stub.load(interfaceID)
    local layout = BAR_LAYOUTS[interfaceID]
    local bar = {}
    for staticID = 0, layout.last do
      bar[staticID] = component()
    end
    rawset(getmetatable(bar[0]).__index, "parentStatic", { interfaceID = 1477, staticID = layout.content })
    getmetatable(bar[62]).__index.alpha = 0.5
    getmetatable(bar[72]).__index.hidden = true
    bar[9] = component({ children = { component({ categoryID = 0, dynamicID = 8 }) } })
    for _, staticID in ipairs({ layout.content - 2, layout.content - 1, layout.content + 1 }) do
      stub.window[staticID] = component({ children = { component({ categoryID = 0, dynamicID = 0 }) } })
    end
    stub.bars[interfaceID] = bar
    return bar
  end
  -- Fires hook on a bar's root, as the client does on mouse over.
  function stub.hook(interfaceID, hook)
    getmetatable(stub.bars[interfaceID][0]).__index.hooks[hook]()
  end
  for _, interfaceID in ipairs({ ... }) do
    stub.load(interfaceID)
  end
  _G.id = { Component = { TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = "top" } }
  _G.ui = {
    Hook = { ONMOUSEOVER = "ONMOUSEOVER", ONMOUSELEAVE = "ONMOUSELEAVE", ONRESIZE = "ONRESIZE" },
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID)
        stub.lookups = stub.lookups + 1
        if interfaceID == "top" then
          return stub.top
        end
        if interfaceID == 1477 then
          return stub.window[staticID]
        end
        return stub.bars[interfaceID] and stub.bars[interfaceID][staticID]
      end,
    },
  }
  stub.writes = 0
  return stub
end

-- Appearance settings with every action bar at 25% and unfaded, then fields.
local function look(fields)
  local appearance = { hideBarStats = false }
  for bar = 1, 5 do
    appearance["barOpacity" .. bar] = 25
    appearance["fadeBar" .. bar] = false
    appearance["hoverBar" .. bar] = true
  end
  for field, value in pairs(fields or {}) do
    appearance[field] = value
  end
  return appearance
end

-- Runs the Draw handler for the frames after a server tick in which the client resets keybind labels.
local function framesAfterTick()
  for _ = 1, 3 do
    adapter.keepActionBarsFaded()
  end
end

describe("adapter.fadeActionBars", function()
  after_each(function()
    adapter.restoreActionBars()
  end)

  it("fades each bar and its window frame to its own opacity, and restores what the client drew", function()
    local stub = loadActionBars(1430, 1670)
    local main = stub.bars[1430]
    adapter.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true, barOpacity2 = 50 }))
    -- Main bar slot 0: frame :63, flash :68, queue holder :70, highlight :72 and keybind :73.
    assert.are.same({ 0.125, 0.25, true, true, true, 0.25, 0.25, 0.5 }, {
      main[62].alpha,
      main[73].alpha,
      main[63].hidden,
      main[68].hidden,
      main[70].hidden,
      stub.window[71].alpha,
      stub.window[71].children[1].alpha,
      stub.bars[1670][1].alpha,
    })
    adapter.fadeActionBars(look())
    assert.are.same({ 0.5, 1, false, false, true, 1, 1 }, {
      main[62].alpha,
      main[73].alpha,
      main[63].hidden,
      main[68].hidden,
      main[72].hidden,
      stub.window[71].alpha,
      stub.bars[1670][1].alpha,
    })
  end)

  it("hides keybinds as well at 0%, and reads nothing in the frames after a tick", function()
    local stub = loadActionBars(1430)
    adapter.fadeActionBars(look({ fadeBar1 = true, barOpacity1 = 0 }))
    assert.are.same({ true, 0, 0 }, { stub.bars[1430][73].hidden, stub.bars[1430][62].alpha, stub.window[71].alpha })
    stub.lookups = 0
    framesAfterTick()
    assert.are.equal(0, stub.lookups)
  end)

  it("fades a keybind label again from the alpha the client resets it to after a tick", function()
    local stub = loadActionBars(1430)
    adapter.fadeActionBars(look({ fadeBar1 = true }))
    stub.bars[1430][86].alpha = 0.608
    framesAfterTick()
    assert.is_true(math.abs(stub.bars[1430][86].alpha - 0.152) < 1e-9)
    adapter.fadeActionBars(look())
    assert.are.equal(0.608, stub.bars[1430][86].alpha)
  end)

  it("shows a hovered bar at full while Show on hover is on, and fades it again on leave", function()
    local stub = loadActionBars(1430, 1670)
    adapter.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true, hoverBar2 = false }))
    stub.hook(1430, "ONMOUSEOVER")
    stub.hook(1670, "ONMOUSEOVER")
    assert.are.same(
      { 1, false, 0.25 },
      { stub.bars[1430][1].alpha, stub.bars[1430][63].hidden, stub.bars[1670][1].alpha }
    )
    stub.hook(1430, "ONMOUSELEAVE")
    assert.are.same({ 0.25, true }, { stub.bars[1430][1].alpha, stub.bars[1430][63].hidden })
  end)

  it("hides the stats strip at any opacity once chosen, and fades rebuilt stat bars again after a resize", function()
    local stub = loadActionBars(1430)
    local main = stub.bars[1430]
    adapter.fadeActionBars(look({ hideBarStats = true }))
    assert.are.same({ true, 0.5 }, { main[6].hidden, main[62].alpha })
    adapter.fadeActionBars(look({ fadeBar1 = true }))
    assert.is_false(main[6].hidden)
    framesAfterTick()
    main[9].children[1].alpha = 1
    stub.topData.hooks.ONRESIZE()
    adapter.keepActionBarsFaded()
    assert.are.equal(0.25, main[9].children[1].alpha)
  end)

  it("skips a bar that is not open, and fades a bar on the tick it opens or after the client rebuilds it", function()
    local stub = loadActionBars(1430)
    adapter.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true }))
    stub.load(1670)
    local main = stub.load(1430)
    adapter.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true }))
    assert.are.same({ 0.25, 0.25, true }, { stub.bars[1670][1].alpha, main[1].alpha, main[63].hidden })
  end)

  it("makes no writes on a steady tick and no reads on frames long after it or while no bar fades", function()
    local stub = loadActionBars(1430)
    adapter.fadeActionBars(look())
    adapter.keepActionBarsFaded()
    assert.are.same({ 0, 0 }, { stub.lookups, stub.writes })
    adapter.fadeActionBars(look({ fadeBar1 = true }))
    framesAfterTick()
    stub.writes = 0
    adapter.fadeActionBars(look({ fadeBar1 = true }))
    framesAfterTick()
    assert.are.equal(0, stub.writes)
    stub.lookups = 0
    adapter.keepActionBarsFaded()
    assert.are.equal(0, stub.lookups)
  end)
end)

describe("adapter.iconStruct", function()
  it("reads combat and spell structs with an icon and a name, and skips other structs", function()
    local params = {
      COMBATV2_ABILITY_ICON = { id = 1 },
      COMBATV2_ABILITY_NAME = { id = 2 },
      COMBATV2_ABILITY_INFO = { id = 3 },
    }
    local function struct(configName, values)
      return {
        configName = configName,
        HasParam = function(_, p)
          return values[p.id] ~= nil
        end,
        GetParamValue = function(_, p)
          return values[p.id]
        end,
      }
    end
    local structs = {
      [1] = struct("MAGIC_VULNERABILITY", { 14395, "Vulnerability" }),
      [2] = struct("COMBATV2_STUNNED_DUMMY_ABILITY", { 26103, "Stunned" }),
      [3] = struct("QUEST_REWARD", { 99, "Lamp" }),
    }
    _G.config = {
      Param = params,
      Struct = {
        FromID = function(structID)
          return structs[structID]
        end,
      },
    }
    assert.are.same({ configName = "MAGIC_VULNERABILITY", icon = 14395, name = "Vulnerability" }, adapter.iconStruct(1))
    assert.are.equal("Stunned", adapter.iconStruct(2).name)
    assert.is_nil(adapter.iconStruct(3))
  end)
end)

describe("adapter.auraReads", function()
  it("reads a buff slot that shows an item, such as an overload, as minus the item id", function()
    local slots = {
      [19] = { icon = { spriteID = 30099 }, label = { content = "" } },
      [20] = { icon = { spriteID = -1, associatedObjectID = 49039 }, label = { content = "5m" } },
    }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, _, dynamicID)
          local slot = interfaceID == 284 and slots[staticID]
          if slot then
            return dynamicID == 0 and slot.icon or slot.label
          end
        end,
      },
    }
    assert.are.same({ { sprite = 30099 }, { sprite = -49039, label = "5m" } }, adapter.auraReads().buffs)
  end)
end)

describe("adapter.structInfo", function()
  it("reads a struct's description, or nil when it has none", function()
    local info = { id = 3 }
    local function struct(text)
      return {
        HasParam = function(_, p)
          return p == info and text ~= nil
        end,
        GetParamValue = function()
          return text
        end,
      }
    end
    local structs = { [1] = struct("Swollen."), [2] = struct(nil) }
    local function fromID(structID)
      return structs[structID]
    end
    _G.config = { Param = { COMBATV2_ABILITY_INFO = info }, Struct = { FromID = fromID } }
    assert.are.same({ "Swollen.", nil, nil }, { adapter.structInfo(1), adapter.structInfo(2), adapter.structInfo(9) })
  end)

  it("falls back to the text after the dash in a struct's name when it has no description", function()
    local info = { id = 3 }
    local name = { id = 4 }
    local params = { [name] = "Drenched - Each stack slows you." }
    local struct = {
      HasParam = function(_, p)
        return params[p] ~= nil
      end,
      GetParamValue = function(_, p)
        return params[p]
      end,
    }
    _G.config = {
      Param = { COMBATV2_ABILITY_INFO = info, COMBATV2_ABILITY_NAME = name },
      Struct = {
        FromID = function()
          return struct
        end,
      },
    }
    assert.are.equal("Each stack slows you.", adapter.structInfo(1))
    params[name] = "Stunned"
    assert.is_nil(adapter.structInfo(1))
  end)
end)

describe("adapter.abilityInfo", function()
  it("reads an ability's description by its key, or nil when its struct is missing", function()
    local info = { id = 3 }
    local struct = {
      HasParam = function(_, p)
        return p == info
      end,
      GetParamValue = function()
        return "Inflict searing pain on the target."
      end,
    }
    _G.config = {
      Param = { COMBATV2_ABILITY_INFO = info },
      Struct = setmetatable({ COMBATV2_ABILITY_MAGIC_FINGER_OF_DEATH = struct }, {
        __index = function(_, structName)
          error("no struct " .. structName)
        end,
      }),
    }
    assert.are.equal("Inflict searing pain on the target.", adapter.abilityInfo("MAGIC_FINGER_OF_DEATH"))
    assert.is_nil(adapter.abilityInfo("MAGIC_DRAGON_BREATH"))
  end)
end)

describe("adapter.itemName", function()
  it("names an item by id", function()
    local salve = { name = "Elder overload salve (6)" }
    _G.config =
      { Obj = {
        FromID = function(objID)
          return objID == 49039 and salve or nil
        end,
      } }
    assert.are.same({ "Elder overload salve (6)", nil }, { adapter.itemName(49039), adapter.itemName(1) })
  end)
end)
