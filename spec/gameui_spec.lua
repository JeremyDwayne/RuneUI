_G.log = function() end
_G.var = { VarPlayer = {} }
local adapter = require("src/adapter")
local gameui = require("src/gameui")

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

describe("gameui.hideTargetPanel", function()
  it("makes every panel component transparent, again after a reload, and restores original alphas", function()
    local panel, border = loadTargetPanel()
    gameui.hideTargetPanel(true)
    assert.are.same({ 0, 0, 0, 0 }, { panel[0].alpha, panel[21].alpha, panel[26].alpha, border.alpha })

    panel = loadTargetPanel()
    gameui.hideTargetPanel(true)
    assert.are.equal(0, panel[21].alpha)

    gameui.hideTargetPanel(false)
    assert.are.same({ 1, 1, 0.5 }, { panel[0].alpha, panel[21].alpha, panel[26].alpha })
  end)

  it("makes rebuilt border and background sprites transparent on the next frame", function()
    local panel, _, rebuild = loadTargetPanel()
    gameui.hideTargetPanel(true)
    local border, background = rebuild()
    gameui.keepTargetPanelHidden()
    assert.are.same({ 0, 0, 0 }, { panel[21].alpha, border.alpha, background.alpha })
    gameui.hideTargetPanel(false)
  end)

  it("makes no client reads on a frame while the panel is shown", function()
    loadTargetPanel()
    gameui.keepTargetPanelHidden()
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
    gameui.hideTargetPanel(true)
    assert.are.equal(0, border.alpha)
    gameui.hideTargetPanel(false)
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

describe("gameui.hideCastBar", function()
  it("hides the spark's glow, whose alpha the client animates, and restores it", function()
    local bar = loadCastBar()
    gameui.hideCastBar(true)
    bar[19].alpha = 1
    gameui.keepCastBarHidden()
    assert.are.same({ 0, true }, { bar[0].alpha, bar[19].hidden })
    gameui.hideCastBar(false)
    assert.are.same({ 1, false }, { bar[0].alpha, bar[19].hidden })
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

describe("gameui.hideBuffBars", function()
  it("hides slot icons, makes the rest transparent, and restores both when turned off", function()
    local bar = loadBuffBar()
    gameui.hideBuffBars(true)
    local slot = bar.slots[19]
    assert.are.same(
      { 0, true, false, 0, true, 0 },
      { bar.root.alpha, slot[0].hidden, slot[1].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha }
    )
    gameui.hideBuffBars(false)
    assert.are.same(
      { 1, false, 1, false, 1 },
      { bar.root.alpha, slot[0].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha }
    )
  end)

  it("leaves an icon the client hid hidden when restoring", function()
    local bar = loadBuffBar()
    local slot = bar.fill(20)
    slot[0].hidden, slot[2].hidden = true, true
    gameui.hideBuffBars(true)
    gameui.hideBuffBars(false)
    assert.are.same({ true, true, false }, { slot[0].hidden, slot[2].hidden, bar.slots[19][0].hidden })
  end)

  it("hides a slot again in the frames after a tick once the client fills it", function()
    local bar = loadBuffBar()
    gameui.hideBuffBars(true)
    gameui.hideBuffBars(true)
    local slot = bar.fill(19)
    gameui.keepBuffBarsHidden()
    assert.are.same({ true, 0, true, 0 }, { slot[0].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha })
    gameui.hideBuffBars(false)
  end)

  it("hides a slot a potion fills several slots past the last buff", function()
    local bar = loadBuffBar()
    gameui.hideBuffBars(true)
    adapter.auraReads()
    gameui.hideBuffBars(true)
    local slot = bar.fill(26)
    gameui.keepBuffBarsHidden()
    assert.is_true(slot[0].hidden)
    gameui.hideBuffBars(false)
  end)

  it("makes no client reads on a frame while the bars are shown or long after a tick", function()
    local bar = loadBuffBar()
    gameui.keepBuffBarsHidden()
    assert.are.equal(0, bar.interfaces.lookups)
    gameui.hideBuffBars(true)
    for _ = 1, 20 do
      gameui.keepBuffBarsHidden()
    end
    bar.interfaces.lookups = 0
    gameui.keepBuffBarsHidden()
    assert.are.equal(0, bar.interfaces.lookups)
    gameui.hideBuffBars(false)
  end)
end)

-- Action bars as the client builds them: every static of each bar, a child under the stat bar :9 and each
-- window frame static, and the main bar's root in window 1477 at :72. Writes and lookups count every alpha or
-- hidden write and component lookup. load(interfaceID) opens a bar, or rebuilds it at its first alphas.
local BAR_LAYOUTS = {
  [1430] = { last = 270, content = 72 },
  [1670] = { last = 198, content = 77 },
  [1671] = { last = 198, content = 82 },
}
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
  -- Fires hook on a bar's static, its root unless given, and sets its isMouseOver, as the client does on mouse over.
  function stub.hook(interfaceID, hook, staticID)
    local data = getmetatable(stub.bars[interfaceID][staticID or 0]).__index
    data.isMouseOver = hook == "ONMOUSEOVER"
    data.hooks[hook]()
  end
  for _, interfaceID in ipairs({ ... }) do
    stub.load(interfaceID)
  end
  _G.id = { Component = { TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = "top" } }
  _G.ui = {
    Hook = { ONMOUSEOVER = "ONMOUSEOVER", ONMOUSELEAVE = "ONMOUSELEAVE", ONRESIZE = "ONRESIZE" },
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
        stub.lookups = stub.lookups + 1
        if interfaceID == "top" then
          return stub.top
        end
        local static = (interfaceID == 1477 and stub.window or stub.bars[interfaceID] or {})[staticID]
        if static == nil or dynamicID == nil then
          return static
        end
        for _, child in ipairs(static.children) do
          if child.categoryID == categoryID and child.dynamicID == dynamicID then
            return child
          end
        end
      end,
    },
  }
  stub.writes = 0
  return stub
end

-- Appearance settings with every action bar at 25% and unfaded, then fields.
local function look(fields)
  local appearance = {}
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
    gameui.keepActionBarsFaded()
  end
end

describe("gameui.fadeActionBars", function()
  after_each(function()
    gameui.restoreActionBars()
  end)

  it("fades each bar and its window frame to its own opacity, and restores what the client drew", function()
    local stub = loadActionBars(1430, 1670)
    local main = stub.bars[1430]
    gameui.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true, barOpacity2 = 50 }))
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
    gameui.fadeActionBars(look())
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

  it(
    "hides keybinds as well at 0%, and reads only the watched window frame and stat bar in the frames after a tick",
    function()
      local stub = loadActionBars(1430)
      gameui.fadeActionBars(look({ fadeBar1 = true, barOpacity1 = 0 }))
      assert.are.same(
        { true, 0.005, 0.01 },
        { stub.bars[1430][73].hidden, stub.bars[1430][62].alpha, stub.window[71].alpha }
      )
      stub.lookups = 0
      framesAfterTick()
      assert.are.equal(6, stub.lookups)
    end
  )

  it("fades a keybind label again from the alpha the client resets it to after a tick", function()
    local stub = loadActionBars(1430)
    gameui.fadeActionBars(look({ fadeBar1 = true }))
    stub.bars[1430][86].alpha = 0.608
    framesAfterTick()
    assert.is_true(math.abs(stub.bars[1430][86].alpha - 0.152) < 1e-9)
    gameui.fadeActionBars(look())
    assert.are.equal(0.608, stub.bars[1430][86].alpha)
  end)

  it("shows a hovered bar at full while Show on hover is on, and fades it again on leave", function()
    local stub = loadActionBars(1430, 1670)
    gameui.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true, hoverBar2 = false }))
    stub.hook(1430, "ONMOUSEOVER")
    stub.hook(1670, "ONMOUSEOVER")
    assert.are.same(
      { 1, false, 0.25 },
      { stub.bars[1430][1].alpha, stub.bars[1430][63].hidden, stub.bars[1670][1].alpha }
    )
    stub.hook(1430, "ONMOUSELEAVE")
    assert.are.same({ 0.25, true }, { stub.bars[1430][1].alpha, stub.bars[1430][63].hidden })
  end)

  it(
    "shows every faded bar with Show on hover on while the mouse is over any, once Hover shows all bars is on",
    function()
      local stub = loadActionBars(1430, 1670, 1671)
      local faded = look({ fadeBar1 = true, fadeBar2 = true, fadeBar3 = true, hoverBar3 = false, hoverAllBars = true })
      gameui.fadeActionBars(faded)
      stub.hook(1670, "ONMOUSEOVER", 20)
      local alphas = function()
        return { stub.bars[1430][1].alpha, stub.bars[1670][1].alpha, stub.bars[1671][1].alpha }
      end
      assert.are.same({ 1, 1, 0.25 }, alphas())
      stub.hook(1670, "ONMOUSELEAVE", 20)
      assert.are.same({ 0.25, 0.25, 0.25 }, alphas())
      -- Action bar 2 closes with the mouse over it, so its leave never comes.
      stub.hook(1670, "ONMOUSEOVER", 20)
      stub.bars[1670] = nil
      gameui.fadeActionBars(faded)
      assert.are.equal(0.25, stub.bars[1430][1].alpha)
    end
  )

  it(
    "shows a bar at full while the mouse is over a slot button reaching past its root, until it leaves both",
    function()
      local stub = loadActionBars(1430)
      gameui.fadeActionBars(look({ fadeBar1 = true }))
      -- Slot 0's button :65 takes the mouse first, then the root, which the mouse leaves before the button.
      stub.hook(1430, "ONMOUSEOVER", 65)
      assert.are.equal(1, stub.bars[1430][1].alpha)
      stub.hook(1430, "ONMOUSEOVER")
      stub.hook(1430, "ONMOUSELEAVE")
      assert.are.equal(1, stub.bars[1430][1].alpha)
      stub.hook(1430, "ONMOUSELEAVE", 65)
      assert.are.equal(0.25, stub.bars[1430][1].alpha)
    end
  )

  it("fades a hovered bar again on the tick after the mouse left it without a leave hook", function()
    local stub = loadActionBars(1430)
    gameui.fadeActionBars(look({ fadeBar1 = true }))
    stub.hook(1430, "ONMOUSEOVER", 65)
    gameui.fadeActionBars(look({ fadeBar1 = true }))
    assert.are.equal(1, stub.bars[1430][1].alpha)
    getmetatable(stub.bars[1430][65]).__index.isMouseOver = false
    gameui.fadeActionBars(look({ fadeBar1 = true }))
    assert.are.equal(0.25, stub.bars[1430][1].alpha)
  end)

  it(
    "keeps the main bar shown while the mouse stays on its lock, which the root stops reporting once clicked",
    function()
      local stub = loadActionBars(1430)
      gameui.fadeActionBars(look({ fadeBar1 = true }))
      stub.hook(1430, "ONMOUSEOVER")
      stub.hook(1430, "ONMOUSEOVER", 270)
      getmetatable(stub.bars[1430][0]).__index.isMouseOver = false
      gameui.fadeActionBars(look({ fadeBar1 = true }))
      assert.are.equal(1, stub.bars[1430][1].alpha)
    end
  )

  it("fades the window frame and stat bars again from the alpha the client gives them on lock and unlock", function()
    local stub = loadActionBars(1430)
    local background, border, stat = stub.window[70].children[1], stub.window[71].children[1], stub.bars[1430][9]
    gameui.fadeActionBars(look({ fadeBar1 = true, barOpacity1 = 0 }))
    framesAfterTick()
    -- The client draws the frame transparent or opaque between server ticks, as locking the interface does.
    background.alpha, border.alpha = 0, 0
    gameui.keepActionBarsFaded()
    stub.hook(1430, "ONMOUSEOVER")
    assert.are.same({ 0, 0 }, { background.alpha, border.alpha })
    stub.hook(1430, "ONMOUSELEAVE")
    background.alpha, border.alpha, stat.children[1].alpha = 1, 1, 1
    gameui.keepActionBarsFaded()
    assert.are.same({ 0.01, 0.01, 0.01 }, { background.alpha, border.alpha, stat.children[1].alpha })
  end)

  it("fades the main bar's stat bars again after a window resize rebuilds them", function()
    local stub = loadActionBars(1430)
    local main = stub.bars[1430]
    gameui.fadeActionBars(look({ fadeBar1 = true }))
    framesAfterTick()
    main[9].children[1].alpha = 1
    stub.topData.hooks.ONRESIZE()
    gameui.keepActionBarsFaded()
    assert.are.equal(0.25, main[9].children[1].alpha)
  end)

  it("skips a bar that is not open, and fades a bar on the tick it opens or after the client rebuilds it", function()
    local stub = loadActionBars(1430)
    gameui.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true }))
    stub.load(1670)
    local main = stub.load(1430)
    gameui.fadeActionBars(look({ fadeBar1 = true, fadeBar2 = true }))
    assert.are.same({ 0.25, 0.25, true }, { stub.bars[1670][1].alpha, main[1].alpha, main[63].hidden })
  end)

  it(
    "makes no writes on a steady tick, reads two components on frames long after it, and none while no bar fades",
    function()
      local stub = loadActionBars(1430)
      gameui.fadeActionBars(look())
      gameui.keepActionBarsFaded()
      assert.are.same({ 0, 0 }, { stub.lookups, stub.writes })
      gameui.fadeActionBars(look({ fadeBar1 = true }))
      framesAfterTick()
      stub.writes = 0
      gameui.fadeActionBars(look({ fadeBar1 = true }))
      framesAfterTick()
      assert.are.equal(0, stub.writes)
      stub.lookups = 0
      gameui.keepActionBarsFaded()
      assert.are.equal(2, stub.lookups)
    end
  )
end)
