_G.log = function() end
local actionbars = require("src/actionbars")

-- Action bars as the client builds them: every static of each bar, a child under the stat bar :9 and each
-- window frame static, and the main bar's root in window 1477 at :72. Writes and lookups count every alpha or
-- hidden write and component lookup. load(interfaceID) opens a bar, or rebuilds it at its first alphas. With
-- roundAlpha set, an alpha written is held in a byte, as the client holds it.
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
        if key == "alpha" and stub.roundAlpha then
          value = math.floor(value * 255) / 255
        end
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
    Hook = { ONMOUSEOVER = "ONMOUSEOVER", ONMOUSELEAVE = "ONMOUSELEAVE", ONCLICK = "ONCLICK", ONRESIZE = "ONRESIZE" },
    Interfaces = {
      GetComponent = function(_, ...)
        stub.lookups = stub.lookups + 1
        -- The client refuses a nil in any argument given, such as a top-level layer looked up with a nil static.
        for i = 1, select("#", ...) do
          if select(i, ...) == nil then
            error("sol: no matching function call takes this number of arguments and the specified types")
          end
        end
        local interfaceID, staticID, categoryID, dynamicID = ...
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
    actionbars.keepFaded()
  end
end

describe("actionbars.fade", function()
  after_each(function()
    actionbars.restore()
  end)

  it("fades each bar and its window frame to its own opacity, and restores what the client drew", function()
    local stub = loadActionBars(1430, 1670)
    local main = stub.bars[1430]
    actionbars.fade(look({ fadeBar1 = true, fadeBar2 = true, barOpacity2 = 50 }))
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
    actionbars.fade(look())
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
      actionbars.fade(look({ fadeBar1 = true, barOpacity1 = 0 }))
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
    actionbars.fade(look({ fadeBar1 = true }))
    stub.bars[1430][86].alpha = 0.608
    framesAfterTick()
    assert.is_true(math.abs(stub.bars[1430][86].alpha - 0.152) < 1e-9)
    actionbars.fade(look())
    assert.are.equal(0.608, stub.bars[1430][86].alpha)
  end)

  it("shows a hovered bar at full while Show on hover is on, and fades it again on leave", function()
    local stub = loadActionBars(1430, 1670)
    actionbars.fade(look({ fadeBar1 = true, fadeBar2 = true, hoverBar2 = false }))
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
      actionbars.fade(faded)
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
      actionbars.fade(faded)
      assert.are.equal(0.25, stub.bars[1430][1].alpha)
    end
  )

  it(
    "shows a bar at full while the mouse is over a slot button reaching past its root, until it leaves both",
    function()
      local stub = loadActionBars(1430)
      actionbars.fade(look({ fadeBar1 = true }))
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

  it("keeps a bar shown for three ticks after a press on a slot, so a drag off it can finish", function()
    local stub = loadActionBars(1430)
    local main = stub.bars[1430]
    actionbars.fade(look({ fadeBar1 = true }))
    stub.hook(1430, "ONMOUSEOVER")
    stub.hook(1430, "ONCLICK", 65)
    stub.hook(1430, "ONMOUSELEAVE")
    assert.are.equal(1, main[1].alpha)
    for _ = 1, 3 do
      actionbars.fade(look({ fadeBar1 = true }))
      assert.are.equal(1, main[1].alpha)
    end
    actionbars.fade(look({ fadeBar1 = true }))
    assert.are.equal(0.25, main[1].alpha)
  end)

  it("fades a hovered bar again on the tick after the mouse left it without a leave hook", function()
    local stub = loadActionBars(1430)
    actionbars.fade(look({ fadeBar1 = true }))
    stub.hook(1430, "ONMOUSEOVER", 65)
    actionbars.fade(look({ fadeBar1 = true }))
    assert.are.equal(1, stub.bars[1430][1].alpha)
    getmetatable(stub.bars[1430][65]).__index.isMouseOver = false
    actionbars.fade(look({ fadeBar1 = true }))
    assert.are.equal(0.25, stub.bars[1430][1].alpha)
  end)

  it(
    "keeps the main bar shown while the mouse stays on its lock, which the root stops reporting once clicked",
    function()
      local stub = loadActionBars(1430)
      actionbars.fade(look({ fadeBar1 = true }))
      stub.hook(1430, "ONMOUSEOVER")
      stub.hook(1430, "ONMOUSEOVER", 270)
      getmetatable(stub.bars[1430][0]).__index.isMouseOver = false
      actionbars.fade(look({ fadeBar1 = true }))
      assert.are.equal(1, stub.bars[1430][1].alpha)
    end
  )

  it("fades the window frame and stat bars again from the alpha the client gives them on lock and unlock", function()
    local stub = loadActionBars(1430)
    local background, border, stat = stub.window[70].children[1], stub.window[71].children[1], stub.bars[1430][9]
    actionbars.fade(look({ fadeBar1 = true, barOpacity1 = 0 }))
    framesAfterTick()
    -- The client draws the frame transparent or opaque between server ticks, as locking the interface does.
    background.alpha, border.alpha = 0, 0
    actionbars.keepFaded()
    stub.hook(1430, "ONMOUSEOVER")
    assert.are.same({ 0, 0 }, { background.alpha, border.alpha })
    stub.hook(1430, "ONMOUSELEAVE")
    background.alpha, border.alpha, stat.children[1].alpha = 1, 1, 1
    actionbars.keepFaded()
    assert.are.same({ 0.01, 0.01, 0.01 }, { background.alpha, border.alpha, stat.children[1].alpha })
  end)

  it("fades the main bar's stat bars again after a window resize rebuilds them", function()
    local stub = loadActionBars(1430)
    local main = stub.bars[1430]
    actionbars.fade(look({ fadeBar1 = true }))
    framesAfterTick()
    main[9].children[1].alpha = 1
    stub.topData.hooks.ONRESIZE()
    actionbars.keepFaded()
    assert.are.equal(0.25, main[9].children[1].alpha)
  end)

  it("holds a bar at 0% while the client keeps alphas in a byte, shows it at full on hover and restores it", function()
    local stub = loadActionBars(1430)
    stub.roundAlpha = true
    local main = stub.bars[1430]
    local faded = look({ fadeBar1 = true, barOpacity1 = 0 })
    actionbars.fade(faded)
    framesAfterTick()
    actionbars.fade(faded)
    framesAfterTick()
    stub.writes = 0
    actionbars.fade(faded)
    framesAfterTick()
    assert.are.equal(0, stub.writes)
    local half = math.floor(0.5 * 255) / 255
    stub.hook(1430, "ONMOUSEOVER")
    assert.are.same({ 1, half, false }, { main[1].alpha, main[62].alpha, main[63].hidden })
    stub.hook(1430, "ONMOUSELEAVE")
    actionbars.fade(look())
    assert.are.same({ 1, half, false }, { main[1].alpha, main[62].alpha, main[63].hidden })
  end)

  it("fades the rest of a bar from their own alphas when the client resets only its root", function()
    local stub = loadActionBars(1430)
    local main = stub.bars[1430]
    actionbars.fade(look({ fadeBar1 = true }))
    getmetatable(main[0]).__index.alpha = 1
    actionbars.fade(look({ fadeBar1 = true }))
    assert.are.same({ 0.25, 0.125, true }, { main[0].alpha, main[62].alpha, main[63].hidden })
    actionbars.fade(look())
    assert.are.same({ 1, 0.5, false }, { main[0].alpha, main[62].alpha, main[63].hidden })
  end)

  it("keeps a bar's fade while its interface is unreadable and restores it once it is read again", function()
    local stub = loadActionBars(1430)
    local main = stub.bars[1430]
    actionbars.fade(look({ fadeBar1 = true }))
    stub.bars[1430] = nil
    actionbars.fade(look({ fadeBar1 = true }))
    stub.bars[1430] = main
    actionbars.fade(look())
    assert.are.same({ 1, 0.5, false }, { main[0].alpha, main[62].alpha, main[63].hidden })
  end)

  it("skips a bar that is not open, and fades a bar on the tick it opens or after the client rebuilds it", function()
    local stub = loadActionBars(1430)
    actionbars.fade(look({ fadeBar1 = true, fadeBar2 = true }))
    stub.load(1670)
    local main = stub.load(1430)
    actionbars.fade(look({ fadeBar1 = true, fadeBar2 = true }))
    assert.are.same({ 0.25, 0.25, true }, { stub.bars[1670][1].alpha, main[1].alpha, main[63].hidden })
  end)

  it(
    "makes no writes on a steady tick, reads two components on frames long after it, and none while no bar fades",
    function()
      local stub = loadActionBars(1430)
      actionbars.fade(look())
      actionbars.keepFaded()
      assert.are.same({ 0, 0 }, { stub.lookups, stub.writes })
      actionbars.fade(look({ fadeBar1 = true }))
      framesAfterTick()
      stub.writes = 0
      actionbars.fade(look({ fadeBar1 = true }))
      framesAfterTick()
      assert.are.equal(0, stub.writes)
      stub.lookups = 0
      actionbars.keepFaded()
      assert.are.equal(2, stub.lookups)
    end
  )
end)
