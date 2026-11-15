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
  local window = {
    [11] = { alpha = 1 },
    [3] = holding(labels),
    [20] = { alpha = 0.5 },
    [18] = { alpha = 1, hidden = false },
    [30] = { alpha = 1, hidden = false },
  }
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

-- A game component the client lays out in parent: pos is { x, y, xParentPc, yParentPc, xSelfPc, ySelfPc } and
-- size { width, height, widthParentPc, heightParentPc }, offsets plus shares of the parent's size, less shares
-- of its own, 0 when left out. Its x, y, width, height and xyGlobal resolve on each read, so it follows its
-- parent. SetPos adds to moves.n.
local function laid(parent, pos, size, moves)
  local c = {}
  function c.SetPos(self, x, y, xParentPc, yParentPc, xSelfPc, ySelfPc)
    moves.n = moves.n + 1
    self.position = {
      x = x,
      y = y,
      xParentPc = xParentPc or 0,
      yParentPc = yParentPc or 0,
      xSelfPc = xSelfPc or 0,
      ySelfPc = ySelfPc or 0,
    }
  end
  function c.SetSize(self, width, height, widthParentPc, heightParentPc)
    self.size =
      { width = width, height = height, widthParentPc = widthParentPc or 0, heightParentPc = heightParentPc or 0 }
  end
  c:SetPos(pos[1], pos[2], pos[3], pos[4], pos[5], pos[6])
  c:SetSize(size[1], size[2], size[3], size[4])
  moves.n = 0
  return setmetatable(c, {
    __index = function(self, key)
      local at, box = rawget(self, "position"), rawget(self, "size")
      if box == nil then
        return nil
      elseif key == "width" then
        return math.floor(box.width + box.widthParentPc * parent.width)
      elseif key == "height" then
        return math.floor(box.height + box.heightParentPc * parent.height)
      elseif key == "x" then
        return math.floor(at.x + at.xParentPc * parent.width - at.xSelfPc * self.width)
      elseif key == "y" then
        return math.floor(at.y + at.yParentPc * parent.height - at.ySelfPc * self.height)
      elseif key == "xyGlobal" then
        return { x = parent.xyGlobal.x + self.x, y = parent.xyGlobal.y + self.y }
      end
    end,
  })
end

describe("gameui.spreadGroupWindow", function()
  -- The window frame and the group window's layers, strips, two buttons and a list tab on a 1710 by 1041 screen,
  -- laid out as the client does: each layer fills its parent, strip 10 sits on the bottom edge and the buttons
  -- along the bottom of strip 18.
  local function loadLayers(moves)
    local screen = { width = 1710, height = 1041, xyGlobal = { x = 0, y = 0 } }
    local fill = { 0, 0, 1, 1 }
    local frame, window = {}, {}
    frame[523] = laid(screen, { 0, 511 }, { 262, 175 }, moves)
    frame[525] = laid(frame[523], { 4, 16 }, { -8, -20, 1, 1 }, moves)
    window[11] = laid(frame[525], { 0, 0 }, fill, moves)
    window[9] = laid(window[11], { 0, 0 }, fill, moves)
    window[5] = laid(window[9], { 0, 0 }, { 0, -33, 1, 1 }, moves)
    window[1] = laid(window[5], { 0, 0 }, fill, moves)
    window[10] = laid(window[9], { 0, 0, 0, 1, 0, 1 }, { 0, 30, 1, 0 }, moves)
    window[18] = laid(window[10], { 0, 0 }, fill, moves)
    window[20] = laid(window[18], { 3, -3, 0, 1, 0, 1 }, { 24, 24 }, moves)
    window[23] = laid(window[18], { 161, -3, 0, 1, 0, 1 }, { 24, 24 }, moves)
    window[30] = laid(window[10], { 215, 7 }, { 17, 17 }, moves)
    serve(frame, window)
    return frame, window
  end

  it("sizes each layer above the rows and buttons past the screen's edges, and writes nothing once there", function()
    local moves = { n = 0 }
    local frame, window = loadLayers(moves)
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.same({ -64, -64, 1838, 1169 }, boxOf(frame[523]))
    for _, c in ipairs({ frame[525], window[11], window[9], window[5], window[1] }) do
      assert.are.same({ 0, 0, 1838, 1169 }, boxOf(c))
    end
    -- A layer that fills its parent is there once the parent is, and keeps its own layout.
    assert.are.equal(3, moves.n)
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.equal(3, moves.n)
    -- The client lays the window out again.
    frame[523]:SetSize(262, 175)
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.equal(1838, frame[523].width)
    gameui.spreadGroupWindow(nil)
  end)

  it("leaves the window alone while a part's layout does not read, as it could not be put back", function()
    local moves = { n = 0 }
    local frame, window = loadLayers(moves)
    window[10].size = nil
    gameui.spreadGroupWindow(1710, 1041)
    assert.are.equal(0, moves.n)
    assert.are.equal(262, frame[523].width)
  end)

  it("puts each layer, strip and button back as the client laid it out, still following its parent", function()
    local moves = { n = 0 }
    local frame, window = loadLayers(moves)
    local column = {
      bands = { { strip = 18, x = 0, y = 316, w = 64, h = 52 } },
      tiles = {
        { text = "2/50", plain = true, x = 6, y = 300, w = 52, h = 16 },
        { static = 20, x = 6, y = 316, w = 24, h = 24 },
        { static = 23, x = 34, y = 316, w = 24, h = 24 },
      },
    }
    -- Nothing moves until the window is spread, when each part's place has been read.
    gameui.placeGroupButtons(column)
    assert.are.equal(0, moves.n)
    gameui.spreadGroupWindow(1710, 1041)
    gameui.placeGroupButtons(column)
    local function screen(c)
      return { c.xyGlobal.x, c.xyGlobal.y, c.width, c.height }
    end
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
    -- The player resizes the window.
    frame[523]:SetSize(400, 300)
    assert.are.same({ 0, 250, 392, 30 }, boxOf(window[10]))
    assert.are.same({ 0, 0, 392, 30 }, boxOf(window[18]))
  end)

  it("keeps the icon strip at the game's width with only the band inside strip 10, leaving its row outside", function()
    local moves = { n = 0 }
    local _, window = loadLayers(moves)
    local column = {
      bands = { { strip = 18, x = 300, y = 316, w = 64, h = 52 } },
      tiles = {
        { static = 20, x = 306, y = 316, w = 24, h = 24 },
        { static = 23, x = 334, y = 316, w = 24, h = 24 },
      },
    }
    gameui.spreadGroupWindow(1710, 1041)
    gameui.placeGroupButtons(column)
    assert.are.same(
      { 300, 316, 64, 52 },
      { window[10].xyGlobal.x, window[10].xyGlobal.y, window[10].width, window[10].height }
    )
    assert.are.same({ -190, 0, 254, 52 }, boxOf(window[18]))
    assert.are.same({ 306, 316 }, { window[20].xyGlobal.x, window[20].xyGlobal.y })
    -- The client puts its buttons back in its own row along the strip's bottom.
    window[20]:SetPos(3, -3, 0, 1, 0, 1)
    window[23]:SetPos(161, -3, 0, 1, 0, 1)
    for _, button in ipairs({ window[20], window[23] }) do
      assert.is_true(button.xyGlobal.x + button.width <= window[10].xyGlobal.x)
    end
    gameui.placeGroupButtons(column)
    assert.are.same({ 334, 316 }, { window[23].xyGlobal.x, window[23].xyGlobal.y })
    gameui.spreadGroupWindow(nil)
  end)
end)

describe("gameui.holdGroupWindow", function()
  it("makes the window, its rows and its frame transparent, and restores each one's alpha", function()
    local window, frame, labels, fill = loadGroupWindow()
    gameui.holdGroupWindow(true, 2, false)
    assert.is_false(window[18].hidden)
    -- The list tabs, which the client places inside strip 10 wherever that is, are hidden throughout.
    assert.is_true(window[30].hidden)
    gameui.holdGroupWindow(true, 2, true)
    assert.are.same({ 0, 0, 0, 0 }, { window[11].alpha, window[20].alpha, labels[0].alpha, labels[46].alpha })
    assert.are.same({ 0, 0, 0, 1 }, { frame[523].alpha, frame[528].alpha, fill.alpha, frame[533].alpha })
    assert.is_true(window[18].hidden)
    assert.is_nil(window[3].hidden)
    gameui.holdGroupWindow(false)
    assert.is_false(window[18].hidden)
    assert.is_false(window[30].hidden)
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
