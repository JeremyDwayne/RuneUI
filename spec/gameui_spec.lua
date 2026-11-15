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

describe("gameui.apply with hideTargetPanel", function()
  it("makes every panel component transparent, again after a reload, and restores original alphas", function()
    local panel, border = loadTargetPanel()
    gameui.apply({ hideTargetPanel = true })
    assert.are.same({ 0, 0, 0, 0 }, { panel[0].alpha, panel[21].alpha, panel[26].alpha, border.alpha })

    panel = loadTargetPanel()
    gameui.apply({ hideTargetPanel = true })
    assert.are.equal(0, panel[21].alpha)

    gameui.apply({ hideTargetPanel = false })
    assert.are.same({ 1, 1, 0.5 }, { panel[0].alpha, panel[21].alpha, panel[26].alpha })
  end)

  it("makes rebuilt border and background sprites transparent on the next frame", function()
    local panel, _, rebuild = loadTargetPanel()
    gameui.apply({ hideTargetPanel = true })
    local border, background = rebuild()
    gameui.onFrame()
    assert.are.same({ 0, 0, 0 }, { panel[21].alpha, border.alpha, background.alpha })
    gameui.apply({ hideTargetPanel = false })
  end)

  it("makes no client reads on a frame while the panel is shown", function()
    loadTargetPanel()
    gameui.onFrame()
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
    gameui.apply({ hideTargetPanel = true })
    assert.are.equal(0, border.alpha)
    gameui.apply({ hideTargetPanel = false })
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

describe("gameui.apply with hideCastBar", function()
  it("hides the spark's glow, whose alpha the client animates, and restores it", function()
    local bar = loadCastBar()
    gameui.apply({ hideCastBar = true })
    bar[19].alpha = 1
    gameui.onFrame()
    assert.are.same({ 0, true }, { bar[0].alpha, bar[19].hidden })
    gameui.apply({ hideCastBar = false })
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

describe("gameui.apply with hideBuffBars", function()
  it("hides slot icons, makes the rest transparent, and restores both when turned off", function()
    local bar = loadBuffBar()
    gameui.apply({ hideBuffBars = true })
    local slot = bar.slots[19]
    assert.are.same(
      { 0, true, false, 0, true, 0 },
      { bar.root.alpha, slot[0].hidden, slot[1].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha }
    )
    gameui.apply({ hideBuffBars = false })
    assert.are.same(
      { 1, false, 1, false, 1 },
      { bar.root.alpha, slot[0].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha }
    )
  end)

  it("leaves an icon the client hid hidden when restoring", function()
    local bar = loadBuffBar()
    local slot = bar.fill(20)
    slot[0].hidden, slot[2].hidden = true, true
    gameui.apply({ hideBuffBars = true })
    gameui.apply({ hideBuffBars = false })
    assert.are.same({ true, true, false }, { slot[0].hidden, slot[2].hidden, bar.slots[19][0].hidden })
  end)

  it("hides a slot again in the frames after a tick once the client fills it", function()
    local bar = loadBuffBar()
    gameui.apply({ hideBuffBars = true })
    gameui.apply({ hideBuffBars = true })
    local slot = bar.fill(19)
    gameui.onFrame()
    assert.are.same({ true, 0, true, 0 }, { slot[0].hidden, slot[1].alpha, slot[2].hidden, slot[3].alpha })
    gameui.apply({ hideBuffBars = false })
  end)

  it("hides a slot a potion fills several slots past the last buff", function()
    local bar = loadBuffBar()
    gameui.apply({ hideBuffBars = true })
    adapter.auraReads()
    gameui.apply({ hideBuffBars = true })
    local slot = bar.fill(26)
    gameui.onFrame()
    assert.is_true(slot[0].hidden)
    gameui.apply({ hideBuffBars = false })
  end)

  it("makes no client reads on a frame while the bars are shown or long after a tick", function()
    local bar = loadBuffBar()
    gameui.onFrame()
    assert.are.equal(0, bar.interfaces.lookups)
    gameui.apply({ hideBuffBars = true })
    for _ = 1, 20 do
      gameui.onFrame()
    end
    bar.interfaces.lookups = 0
    gameui.onFrame()
    assert.are.equal(0, bar.interfaces.lookups)
    gameui.apply({ hideBuffBars = false })
  end)
end)

-- The group window 1519 with its base :11 and its member list :3 holding the title and two rows' lifepoints
-- labels, in the window frame 1477 from :523 to :532 with a background :524 holding a sprite.
local function loadGroupWindow()
  local function child(dynamicID)
    return { alpha = 1, categoryID = 0, dynamicID = dynamicID }
  end
  local labels = { [0] = child(0), [23] = child(23), [46] = child(46) }
  local fill = child(0)
  -- Each member row's click area, as the client has it.
  local areas = { [0] = { clickthrough = true }, [1] = { clickthrough = true } }
  local function holding(children)
    return {
      alpha = 1,
      IterateDynamicComponents = function(_, fn)
        for _, c in pairs(children) do
          fn(c)
        end
      end,
    }
  end
  local window =
    { [11] = { alpha = 1 }, [3] = holding(labels), [20] = { alpha = 0.5 }, [18] = { alpha = 1, hidden = false } }
  local frame = { [523] = { alpha = 1 }, [524] = holding({ fill }), [528] = { alpha = 1 }, [533] = { alpha = 1 } }
  _G.ui = {
    Interfaces = {
      lookups = 0,
      GetComponent = function(self, interfaceID, staticID, categoryID, dynamicID)
        self.lookups = self.lookups + 1
        local statics = interfaceID == 1519 and window or interfaceID == 1477 and frame or {}
        if categoryID == nil then
          return statics[staticID]
        end
        if interfaceID == 1519 and staticID == 1 then
          return areas[dynamicID]
        end
        return interfaceID == 1519 and staticID == 3 and labels[dynamicID] or nil
      end,
    },
  }
  return window, frame, labels, fill, areas
end

describe("gameui.placeGroupRows", function()
  -- The group window's click area layer at 104, 250 with two rows' click areas, counting SetPos calls.
  local function loadRows()
    local moves = 0
    local function area(y)
      return {
        x = 5,
        y = y,
        width = 247,
        height = 38,
        SetPos = function(self, x, to)
          moves = moves + 1
          self.x, self.y = x, to
        end,
        SetSize = function(self, w, h)
          self.width, self.height = w, h
        end,
      }
    end
    local rows = { [0] = area(17), [1] = area(55) }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
          if interfaceID ~= 1519 or staticID ~= 1 then
            return nil
          end
          if categoryID == nil then
            return { xyGlobal = { x = 104, y = 250 } }
          end
          return rows[dynamicID]
        end,
      },
    }
    return rows, function()
      return moves
    end
  end

  it("puts each row's click area on its box, writes nothing once there, and puts it back", function()
    local rows, moves = loadRows()
    local boxes = { { x = 300, y = 500, w = 84, h = 40 }, false }
    gameui.placeGroupRows(boxes, 2)
    assert.are.same({ 196, 250, 84, 40 }, { rows[0].x, rows[0].y, rows[0].width, rows[0].height })
    assert.are.same({ 5, 55 }, { rows[1].x, rows[1].y })
    gameui.placeGroupRows(boxes, 2)
    assert.are.equal(1, moves())
    -- The client puts the row back, as on a rebuild.
    rows[0].x = 5
    gameui.placeGroupRows(boxes, 2)
    assert.are.equal(196, rows[0].x)
    gameui.placeGroupRows(nil, 0)
    assert.are.same({ 5, 17, 247, 38 }, { rows[0].x, rows[0].y, rows[0].width, rows[0].height })
    gameui.placeGroupRows(nil, 0)
    assert.are.equal(3, moves())
  end)
end)

-- A game component at x, y in its parent and gx, gy on screen, w by h, adding its moves to moves.n. Its screen
-- place follows its own moves, as if its parent stayed put.
local function boxed(x, y, w, h, gx, gy, moves)
  return {
    x = x,
    y = y,
    width = w,
    height = h,
    xyGlobal = { x = gx, y = gy },
    SetPos = function(self, toX, toY)
      moves.n = moves.n + 1
      self.xyGlobal.x, self.xyGlobal.y = self.xyGlobal.x + toX - self.x, self.xyGlobal.y + toY - self.y
      self.x, self.y = toX, toY
    end,
    SetSize = function(self, toW, toH)
      self.width, self.height = toW, toH
    end,
  }
end

-- Serves frame as interface 1477's statics and window as 1519's.
local function serve(frame, window)
  _G.ui = {
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID)
        return (interfaceID == 1477 and frame or interfaceID == 1519 and window or {})[staticID]
      end,
    },
  }
end

local function boxOf(c)
  return { c.x, c.y, c.width, c.height }
end

describe("gameui.spreadGroupWindow", function()
  -- The window frame and the group window's layers, strips and two buttons, as the client lays them out. Sizing
  -- layer 9 moves strip 10 to its bottom edge, as the client does with a part anchored there.
  local function loadLayers(moves)
    local frame = { [523] = boxed(0, 511, 262, 175, 0, 511, moves), [525] = boxed(4, 16, 254, 155, 4, 527, moves) }
    local window = {
      [11] = boxed(0, 0, 254, 155, 4, 527, moves),
      [9] = boxed(0, 0, 254, 155, 4, 527, moves),
      [5] = boxed(0, 0, 254, 122, 4, 527, moves),
      [1] = boxed(0, 0, 254, 122, 4, 527, moves),
      [10] = boxed(0, 125, 254, 30, 4, 652, moves),
      [18] = boxed(0, 0, 254, 30, 4, 652, moves),
      [20] = boxed(3, 3, 24, 24, 7, 655, moves),
      [23] = boxed(161, 3, 24, 24, 165, 655, moves),
    }
    local size = window[9].SetSize
    window[9].SetSize = function(self, w, h)
      size(self, w, h)
      window[10].y, window[10].width = h - 30, w
    end
    serve(frame, window)
    return frame, window
  end

  it("sizes each layer above the rows and buttons past the screen's edges, and writes nothing once there", function()
    local moves = { n = 0 }
    local frame, window = loadLayers(moves)
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.same({ -64, -64, 1838, 1169 }, boxOf(frame[523]))
    for _, c in ipairs({ frame[525], window[11], window[9], window[5], window[1], window[10] }) do
      assert.are.same({ 0, 0, 1838, 1169 }, boxOf(c))
    end
    assert.are.equal(7, moves.n)
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.equal(7, moves.n)
    -- The client lays the window out again.
    frame[523].width = 262
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.equal(1838, frame[523].width)
    gameui.spreadGroupWindow(nil)
  end)

  it("puts each layer, strip and button back where the client had it before any was sized", function()
    local moves = { n = 0 }
    local frame, window = loadLayers(moves)
    gameui.spreadGroupWindow(1710, 1041)
    gameui.placeGroupButtons({
      bands = { { strip = 18, x = 0, y = 316, w = 64, h = 52 } },
      tiles = {
        { text = "2/50", plain = true, x = 6, y = 300, w = 52, h = 16 },
        { static = 20, x = 6, y = 316, w = 24, h = 24 },
        { static = 23, x = 34, y = 316, w = 24, h = 24 },
      },
    })
    local function screen(c)
      return { c.xyGlobal.x, c.xyGlobal.y, c.width, c.height }
    end
    assert.are.same({ 0, 316, 64, 52 }, screen(window[18]))
    assert.are.same({ 6, 316, 24, 24 }, screen(window[20]))
    assert.are.same({ 34, 316, 24, 24 }, screen(window[23]))
    gameui.spreadGroupWindow(nil)
    assert.are.same({ 0, 511, 262, 175 }, boxOf(frame[523]))
    assert.are.same({ 4, 16, 254, 155 }, boxOf(frame[525]))
    assert.are.same({ 0, 125, 254, 30 }, boxOf(window[10]))
    assert.are.same({ 0, 0, 254, 30 }, boxOf(window[18]))
    assert.are.same({ 3, 3, 24, 24 }, boxOf(window[20]))
    assert.are.same({ 161, 3, 24, 24 }, boxOf(window[23]))
    local restored = moves.n
    gameui.spreadGroupWindow(nil)
    assert.are.equal(restored, moves.n)
  end)
end)

describe("gameui.holdGroupWindow", function()
  it("makes the window, its rows and its frame transparent, and restores each one's alpha", function()
    local window, frame, labels, fill = loadGroupWindow()
    gameui.holdGroupWindow(true, 2, false)
    assert.is_false(window[18].hidden)
    gameui.holdGroupWindow(true, 2, true)
    assert.are.same({ 0, 0, 0, 0 }, { window[11].alpha, window[20].alpha, labels[0].alpha, labels[46].alpha })
    assert.are.same({ 0, 0, 0, 1 }, { frame[523].alpha, frame[528].alpha, fill.alpha, frame[533].alpha })
    assert.is_true(window[18].hidden)
    assert.is_nil(window[3].hidden)
    gameui.holdGroupWindow(false)
    assert.is_false(window[18].hidden)
    assert.are.same({ 1, 0.5, 1, 1 }, { window[11].alpha, window[20].alpha, labels[46].alpha, fill.alpha })
  end)

  it("lets clicks pass the window's frame but not its rows or button strips, and puts each back", function()
    local window, frame, _, _, areas = loadGroupWindow()
    local function writes()
      local n = 0
      for _, c in ipairs({ frame[523], window[0], window[18], areas[0], areas[1] }) do
        n = n + c.writes
      end
      return n
    end
    -- Counts each clickthrough write on a component the client has at value.
    local function counted(c, value)
      local state = { clickthrough = value }
      c.writes = 0
      return setmetatable(c, {
        __index = state,
        __newindex = function(self, key, to)
          if key == "clickthrough" then
            rawset(self, "writes", self.writes + 1)
            state.clickthrough = to
          else
            rawset(self, key, to)
          end
        end,
      })
    end
    counted(frame[523], false)
    -- The strip that holds strip 18 is sized over the screen, so it has to go on passing clicks.
    window[10] = counted({}, true)
    window[0] = counted({}, true)
    counted(window[18], false)
    areas[0].clickthrough, areas[1].clickthrough = nil, nil
    counted(areas[0], true)
    counted(areas[1], true)
    gameui.holdGroupWindow(true, 2, false, true)
    assert.are.same({ true, false, false, false, false }, {
      frame[523].clickthrough,
      window[0].clickthrough,
      window[18].clickthrough,
      areas[0].clickthrough,
      areas[1].clickthrough,
    })
    assert.are.equal(4, writes())
    assert.are.same({ true, 0 }, { window[10].clickthrough, window[10].writes })
    gameui.holdGroupWindow(true, 2, false, true)
    assert.are.equal(4, writes())
    -- The client puts the frame back, as on a rebuild.
    frame[523].clickthrough = false
    gameui.holdGroupWindow(true, 2, false, true)
    assert.is_true(frame[523].clickthrough)
    gameui.holdGroupWindow(true, 2, false, false)
    assert.are.same({ false, true, false, true, true }, {
      frame[523].clickthrough,
      window[0].clickthrough,
      window[18].clickthrough,
      areas[0].clickthrough,
      areas[1].clickthrough,
    })
    gameui.holdGroupWindow(false)
  end)

  it("makes a row transparent again on the frame after the client shows it, for any listed member", function()
    local window, _, labels = loadGroupWindow()
    gameui.holdGroupWindow(true, 2)
    labels[46].alpha = 1
    window[20].alpha = 1
    gameui.onFrame()
    assert.are.same({ 0, 0 }, { labels[46].alpha, window[20].alpha })
    gameui.restore()
    assert.are.same({ 1, 0.5 }, { labels[46].alpha, window[20].alpha })
  end)

  it("makes no client reads on a frame while the window is not held", function()
    loadGroupWindow()
    gameui.onFrame()
    assert.are.equal(0, ui.Interfaces.lookups)
  end)
end)
