-- Restyles the game's window frames, listed by src/windowframes: every sprite under each open window's frame
-- background, border and tab strip in 1477 takes the appearance's frame or background colour, and a window with
-- an opacity below 100 draws its background sprites at that share of their own alpha. Locking or unlocking the
-- interface replaces every frame's sprites with new ones in the game's look, and a handle kept from before goes
-- on reading the old values, so every check looks a sprite up again. onFrame reads one restyled sprite and the
-- window layer of each open window with tabs each rendered frame, and restyles every open frame once the sprite
-- reads otherwise or one of those windows hides: a tab switch shows the next window on that same frame, with
-- some of its sprites new. A window that opens otherwise is restyled on the next server tick.
-- Game for both colours with every window at 100, or restore on shutdown, writes the game's look back.
local interfaces = require("src/interfaces")
local style = require("src/style")
local windowframes = require("src/windowframes")

local windowskin = {}

local read = interfaces.read
local write = interfaces.write
local component = interfaces.component
local WINDOWS = interfaces.WINDOWS
local NO_TINT = style.NO_TINT
-- How far an alpha may read from the one written: the client holds an alpha in a byte.
local EPSILON = 0.005

-- The tints wanted on frames and on backgrounds, NO_TINT for the game's own colours, and each window's opacity
-- in percent by name, for the windows below 100.
local frameTint, backgroundTint = NO_TINT, NO_TINT
local opacities = {}
-- Frames restyled since load, by name, so a change repaints closed ones too.
local painted = {}
-- Each background sprite's alpha before RuneUI faded it, by "name:category:dynamic".
local originals = {}
-- Each open frame's probe by name: { static, category, dynamic, rgb, alpha }, a sprite whose look says whether the
-- frame is still restyled, or false for a frame left in the game's look. nil until the frame is painted, and
-- while the client has built no sprite under it, so the next tick tries again.
local probes = {}
-- The probe of the first open frame that has one, which onFrame reads; nil while nothing is restyled.
local watch = nil
-- The open frames with tabs as paintOpen last found them, the first tabbedCount of them, whose windows onFrame
-- reads. Reused, so a tick allocates nothing.
local tabbed = {}
local tabbedCount = 0

-- What paintChild writes to one static's sprites: its rgb, and for a background the frame's name and the share
-- of each sprite's own alpha to draw at, nil to put each original back. Reused, so painting allocates nothing
-- per sprite.
local target = {}

-- Writes target's look to child when it is a sprite, which reads a number spriteID, -1 while a lock blanks it.
local function paintChild(_, child, category, dynamic)
  if type(read(child, "spriteID")) ~= "number" then
    return
  end
  if read(child, "rgb") ~= target.rgb then
    write(child, "rgb", target.rgb)
  end
  if target.name == nil then
    return
  end
  local key = target.name .. ":" .. tostring(category) .. ":" .. tostring(dynamic)
  local alpha = read(child, "alpha")
  local original = originals[key]
  if target.alpha ~= nil and original == nil then
    original = alpha or 1
    originals[key] = original
  elseif target.alpha == nil then
    originals[key] = nil
  end
  local want = original and original * (target.alpha or 1)
  if want ~= nil and (alpha == nil or math.abs(alpha - want) > EPSILON) then
    write(child, "alpha", want)
  end
end

-- The first sprite child of staticID as a probe expecting rgb, and when faded the alpha it reads as just
-- painted, or nil while staticID has no sprite.
local function probeOf(staticID, rgb, faded)
  local found = nil
  interfaces.eachChild(component(WINDOWS, staticID), "", function(_, child, category, dynamic)
    if found == nil and type(read(child, "spriteID")) == "number" then
      local alpha = faded and read(child, "alpha") or nil
      found = { static = staticID, category = category, dynamic = dynamic, rgb = rgb, alpha = alpha }
    end
  end)
  return found
end

-- The share of its own alpha frame draws its background at, or nil for the game's own.
local function alphaOf(frame)
  local percent = not frame.held and opacities[frame.name]
  return percent and percent / 100 or nil
end

-- Restyles every sprite of frame and returns its probe: a background sprite while the background is tinted or
-- faded, a border sprite while only the frame is tinted, and false for a frame left in the game's look, since a
-- part in the game's look reads the same before and after a lock.
local function paint(frame)
  local alpha = alphaOf(frame)
  for _, staticID in ipairs({ frame.background, frame.border, frame.tabs }) do
    local c = component(WINDOWS, staticID)
    if c ~= nil then
      local background = staticID == frame.background
      target.rgb = background and backgroundTint or frameTint
      target.name = background and frame.name or nil
      target.alpha = background and alpha or nil
      interfaces.eachChild(c, "", paintChild)
    end
  end
  painted[frame.name] = frame
  if backgroundTint ~= NO_TINT or alpha ~= nil then
    return probeOf(frame.background, backgroundTint, alpha ~= nil)
  end
  return frameTint ~= NO_TINT and probeOf(frame.border, frameTint)
end

-- Whether probe's sprite, looked up again, reads another look than it expects.
local function stale(probe)
  local c = component(WINDOWS, probe.static, probe.category, probe.dynamic)
  if c == nil or read(c, "rgb") ~= probe.rgb then
    return true
  end
  if probe.alpha == nil then
    return false
  end
  local alpha = read(c, "alpha")
  return alpha ~= nil and math.abs(alpha - probe.alpha) > EPSILON
end

-- Paints every open frame not painted since it opened, or whose probe reads otherwise, watches the first
-- probe and lists the open frames with tabs. Reads each frame's window layer, about 90 lookups.
local function paintOpen()
  watch = nil
  tabbedCount = 0
  for _, frame in ipairs(windowframes) do
    if read(component(WINDOWS, frame.window), "visibleGlobal") == true then
      local probe = probes[frame.name]
      if probe == nil or (probe and stale(probe)) then
        probe = paint(frame)
        probes[frame.name] = probe
      end
      watch = watch or probe or nil
      if frame.tabs ~= nil then
        tabbedCount = tabbedCount + 1
        tabbed[tabbedCount] = frame
      end
    else
      probes[frame.name] = nil
    end
  end
end

-- Whether an open window with tabs has hidden since paintOpen listed it.
local function tabHidden()
  for i = 1, tabbedCount do
    if read(component(WINDOWS, tabbed[i].window), "visibleGlobal") ~= true then
      return true
    end
  end
  return false
end

-- Whether saved, { [name] = percent }, differs from the opacities in use.
local function opacitiesChanged(saved)
  for name, percent in pairs(saved) do
    if opacities[name] ~= percent then
      return true
    end
  end
  for name in pairs(opacities) do
    if saved[name] == nil then
      return true
    end
  end
  return false
end

-- Runs each server tick with the appearance settings and each window's opacity, { [name] = percent } for the
-- windows below 100. A change repaints every frame restyled so far; with nothing to restyle nothing more is read
-- until a setting changes.
function windowskin.apply(appearance, saved)
  saved = saved or {}
  local frame = style.windowTint(style.WINDOW_FRAME_PRESETS, appearance.windowFrameColour)
  local background = style.windowTint(style.WINDOW_BACKGROUND_PRESETS, appearance.windowBackgroundColour)
  if frame ~= frameTint or background ~= backgroundTint or opacitiesChanged(saved) then
    frameTint, backgroundTint = frame, background
    opacities = {}
    for name, percent in pairs(saved) do
      opacities[name] = percent
    end
    for _, f in pairs(painted) do
      paint(f)
    end
    probes = {}
    watch = nil
    tabbedCount = 0
    if frameTint == NO_TINT and backgroundTint == NO_TINT and next(opacities) == nil then
      painted = {}
    end
  end
  if frameTint == NO_TINT and backgroundTint == NO_TINT and next(opacities) == nil then
    return
  end
  paintOpen()
end

-- Runs on every rendered frame: one lookup and two reads for the probe while a frame is restyled, one of each per
-- open window with tabs while anything is, and nothing otherwise. Locking the interface replaces every frame's
-- sprites at once, so one probe reading otherwise repaints every open frame.
function windowskin.onFrame()
  if (watch ~= nil and stale(watch)) or tabHidden() then
    paintOpen()
  end
end

-- The frames the Windows page lists, in src/windowframes order: each one whose alpha RuneUI does not hold
-- elsewhere and whose window is open, or whose opacity saved, { [name] = percent }, holds.
function windowskin.listed(saved)
  local out = {}
  for _, frame in ipairs(windowframes) do
    local open = saved[frame.name] ~= nil or read(component(WINDOWS, frame.window), "visibleGlobal") == true
    if open and not frame.held then
      out[#out + 1] = frame
    end
  end
  return out
end

-- Writes the game's look back to every frame restyled, on shutdown.
function windowskin.restore()
  windowskin.apply({}, {})
end

return windowskin
