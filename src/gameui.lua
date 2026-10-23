-- Hides and restores the game's own interfaces: the target panel, buff bars and cast bar held transparent
-- while RuneUI replaces them, with the action bars faded through src/actionbars. The client rebuilds parts of
-- each between server ticks, so onFrame reads a few watched components each rendered frame and writes them
-- back, and nothing while no interface is held. Every change has a restore path: apply with the option off,
-- or restore on shutdown.
local actionbars = require("src/actionbars")
local interfaces = require("src/interfaces")

local gameui = {}

local read = interfaces.read
local component = interfaces.component
local BUFF_BARS = interfaces.BUFF_BARS
-- Rendered frames after each server tick in which a buff bar can fill a slot.
local FILL_FRAMES = 8

-- Whether c reads an alpha above 0.
local function opaque(c)
  if c == nil then
    return false
  end
  local alpha = read(c, "alpha")
  return alpha ~= nil and alpha > 0
end

-- An interface RuneUI can hold transparent with alpha 0, since hiding its components stops them updating.
-- lastStatic is its highest static ID. watched lists { staticID, categoryID, dynamicID } addresses, without
-- the last two for a static, that read opaque once the client reloads or rebuilds the interface. animated lists
-- static IDs whose alpha the client animates, which take hidden instead. Returns { hide(hidden), keep() }: hide
-- runs each server tick and false restores the original alphas and hidden states; keep runs on every rendered
-- frame, reading only the watched components while hidden and nothing while shown.
local function transparency(interfaceID, lastStatic, watched, animated)
  -- Original alpha of each component while held transparent, keyed "static" or "static:category:dynamic".
  local originals = nil

  -- Calls fn(key, component) for every component, dynamic children included, since a component's alpha
  -- does not reach its children.
  local function each(fn)
    for staticID = 0, lastStatic do
      local c = component(interfaceID, staticID)
      if c ~= nil then
        fn(tostring(staticID), c)
        pcall(function()
          c:IterateDynamicComponents(function(child)
            fn(
              staticID .. ":" .. tostring(read(child, "categoryID")) .. ":" .. tostring(read(child, "dynamicID")),
              child
            )
            return false
          end)
        end)
      end
    end
  end

  local function setAlpha(transparent)
    each(function(key, c)
      if transparent and originals[key] == nil then
        originals[key] = read(c, "alpha") or 1
      end
      local alpha = 0
      if not transparent then
        alpha = originals[key] or 1
      end
      pcall(function()
        c.alpha = alpha
      end)
    end)
    for _, staticID in ipairs(animated or {}) do
      local c = component(interfaceID, staticID)
      local key = "hidden " .. staticID
      if c ~= nil and (transparent or originals[key] ~= nil) then
        if transparent and originals[key] == nil then
          originals[key] = read(c, "hidden") == true
        end
        local hidden = transparent or originals[key]
        pcall(function()
          c.hidden = hidden
        end)
      end
    end
  end

  local t = {}

  function t.keep()
    if originals == nil then
      return
    end
    for _, at in ipairs(watched) do
      if opaque(component(interfaceID, at[1], at[2], at[3])) then
        setAlpha(true)
        return
      end
    end
  end

  function t.hide(hidden)
    if hidden then
      originals = originals or {}
      t.keep()
    elseif originals ~= nil then
      setAlpha(false)
      originals = nil
    end
  end

  return t
end

-- The target panel rebuilds its frame sprites opaque between server ticks. A visible name label means the
-- panel reloaded, and a visible background means its frame was rebuilt.
local targetPanel = transparency(
  interfaces.TARGET_PANEL,
  interfaces.TARGET_LAST_STATIC,
  { { interfaces.TARGET_NAME }, { interfaces.TARGET_BACKGROUND, 0, 0 } }
)

-- Runs on every rendered frame, making the target panel transparent again when the client rebuilt it.
gameui.keepTargetPanelHidden = targetPanel.keep

-- Runs each server tick with whether the native target panel should be hidden. Hiding sets alpha 0,
-- because hidden stops the panel filling its debuff slots, which src/adapter's targetReads falls back to.
gameui.hideTargetPanel = targetPanel.hide

-- The game's cast bar, held transparent so the client's own showing and hiding of it is left alone and
-- restoring never shows a bar the client hid. A visible root or time label means the client rebuilt it. The
-- client fades the glow of the bar's moving spark in from opaque each tick, so the glow takes hidden.
local castBar = transparency(
  interfaces.CAST_BAR,
  interfaces.CAST_BAR_LAST_STATIC,
  { { 0 }, { interfaces.CAST_BAR_DURATION } },
  { interfaces.CAST_BAR_GLOW }
)

-- Runs on every rendered frame, making the game's cast bar transparent again when the client rebuilt it.
gameui.keepCastBarHidden = castBar.keep

-- Runs each server tick with whether the game's cast bar should be hidden. false restores its alphas.
gameui.hideCastBar = castBar.hide

-- Original alpha of each buff bar component while RuneUI hides the bars, keyed "bar:static" or
-- "bar:static:category:dynamic", and the keys of the icons it set hidden.
local barAlpha = nil
local barHidden = nil
-- Rendered frames since the last server tick, counted up to FILL_FRAMES.
local framesSinceTick = FILL_FRAMES

-- Hides c: a slot's icon :0:0 and :0:2 take hidden, which the client undoes only when it fills the slot.
-- An icon already hidden is left alone, so restoring never shows one the client hid. Everything else takes
-- alpha 0, which the client resets every few frames on an icon but not on these.
local function hideBarComponent(key, c, icon)
  if icon then
    if read(c, "hidden") ~= false then
      return
    end
    barHidden[key] = true
    pcall(function()
      c.hidden = true
    end)
    return
  end
  if barAlpha[key] == nil then
    barAlpha[key] = read(c, "alpha") or 1
  end
  pcall(function()
    c.alpha = 0
  end)
end

-- Calls fn(key, child, icon) for each dynamic child of bar's static staticID.
local function eachSlotChild(bar, staticID, c, fn)
  local slot = staticID >= bar.first and staticID <= bar.last
  pcall(function()
    c:IterateDynamicComponents(function(child)
      local category = read(child, "categoryID")
      local dynamic = read(child, "dynamicID")
      fn(
        bar.id .. ":" .. staticID .. ":" .. tostring(category) .. ":" .. tostring(dynamic),
        child,
        slot and category == 0 and (dynamic == 0 or dynamic == 2)
      )
      return false
    end)
  end)
end

-- Calls fn(key, component, icon) for every component of both buff bars, dynamic children included, since
-- a component's alpha does not reach its children.
local function eachBarComponent(fn)
  for _, bar in pairs(BUFF_BARS) do
    for staticID = 0, bar.lastStatic do
      local c = component(bar.id, staticID)
      if c ~= nil then
        fn(bar.id .. ":" .. staticID, c, false)
        eachSlotChild(bar, staticID, c, fn)
      end
    end
  end
end

-- Runs on every rendered frame while the buff bars are hidden. For a few frames after each server tick it
-- reads the icon of each slot up to watchLast, and hides a slot again once the client fills it, which
-- shows its icon and makes its label and frame opaque. No reads otherwise.
function gameui.keepBuffBarsHidden()
  if barAlpha == nil or framesSinceTick >= FILL_FRAMES then
    return
  end
  framesSinceTick = framesSinceTick + 1
  for _, bar in pairs(BUFF_BARS) do
    for staticID = bar.first, bar.watchLast or bar.last do
      if read(component(bar.id, staticID, 0, 0), "hidden") == false then
        eachSlotChild(bar, staticID, component(bar.id, staticID), hideBarComponent)
      end
    end
  end
end

-- Runs each server tick with whether the native buff and debuff bars should be hidden. Their labels keep
-- counting and their slots keep filling while hidden, which auraReads relies on. A bar whose first static
-- reads opaque reloaded, so it is hidden again whole. false restores what RuneUI changed.
function gameui.hideBuffBars(hidden)
  if hidden then
    framesSinceTick = 0
    if barAlpha == nil then
      barAlpha = {}
      barHidden = {}
      eachBarComponent(hideBarComponent)
      return
    end
    for _, bar in pairs(BUFF_BARS) do
      local root = component(bar.id, 0)
      local alpha = root and read(root, "alpha")
      if alpha ~= nil and alpha > 0 then
        eachBarComponent(hideBarComponent)
        return
      end
    end
  elseif barAlpha ~= nil then
    eachBarComponent(function(key, c)
      if barHidden[key] then
        pcall(function()
          c.hidden = false
        end)
      end
      local alpha = barAlpha[key]
      if alpha ~= nil then
        pcall(function()
          c.alpha = alpha
        end)
      end
    end)
    barAlpha = nil
    barHidden = nil
  end
end

-- Runs each server tick with the appearance settings, hiding or showing each game interface as they say.
function gameui.apply(appearance)
  gameui.hideTargetPanel(appearance.hideTargetPanel)
  gameui.hideBuffBars(appearance.hideBuffBars)
  gameui.hideCastBar(appearance.hideCastBar)
  actionbars.fade(appearance)
end

-- Runs on every rendered frame, putting back whatever the client rebuilt on a held interface.
function gameui.onFrame()
  gameui.keepTargetPanelHidden()
  gameui.keepBuffBarsHidden()
  gameui.keepCastBarHidden()
  actionbars.keepFaded()
end

-- Puts every game interface back as the client drew it, on shutdown.
function gameui.restore()
  gameui.hideTargetPanel(false)
  gameui.hideBuffBars(false)
  gameui.hideCastBar(false)
  actionbars.restore()
end

return gameui
