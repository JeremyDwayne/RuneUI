-- Resolves the saved appearance settings into the look every HUD element draws with: font names per text
-- role, text edge and colour, unit frame colours, border and frame size, the bars' sizes and the cast bar's
-- colour. Also parses and formats hex colours
-- and converts them to and from hue, saturation and value for the colour picker.
-- Pure: fonts are client font names, which src/view turns into ids.
local style = {}

-- Each HUD text role's size in points at text step 0.
style.ROLES = { body = 13, small = 10, seconds = 17, smallSeconds = 15 }

-- Bold font names by point size.
local function sizes(pattern, list)
  local out = {}
  for _, size in ipairs(list) do
    out[size] = string.format(pattern, size)
  end
  return out
end

local noto = {}
for size = 10, 24 do
  noto[size] = "NOTOSANS_BOLD_" .. size
end
-- Museo Sans has no bold below 13, so its smaller text uses Noto Sans Bold.
local museo = sizes("MUSEO_SANS_%dPT_BOLD", { 13, 15, 17, 19, 21, 24, 27 })
for size = 10, 12 do
  museo[size] = noto[size]
end

-- HUD font families in menu order, with their bold fonts by size.
style.FAMILIES = {
  { id = "museo", label = "Museo Sans", sizes = museo },
  { id = "noto", label = "Noto Sans", sizes = noto },
  { id = "verdana", label = "Verdana", sizes = sizes("VERDANA_%dPT_BOLD", { 11, 13 }) },
  { id = "cinzel", label = "Cinzel", sizes = sizes("CINZEL_%dPT_BOLD", { 12, 13, 15, 18 }) },
}

style.EDGES = {
  { id = "none", label = "None" },
  { id = "shadow", label = "Shadow" },
  { id = "outline", label = "Outline" },
  { id = "outlineShadow", label = "Outline + shadow" },
}

-- Auto draws white, and dark text over a fill style.dark picks.
style.TEXT_COLOURS = {
  { id = "white", label = "White", rgb = 0xffffff },
  { id = "yellow", label = "Game yellow", rgb = 0xffea00 },
  { id = "auto", label = "Auto", rgb = 0xffffff },
}
style.DARK_TEXT, style.LIGHT_EDGE, style.DARK_EDGE = 0x111316, 0xffffff, 0x000000

-- Fill colours by src/cooldowns combat style, shared by the cast bar and the Equipped preset.
style.STYLE_COLOURS = { magic = 0x2a5fa8, ranged = 0x2f7a33, melee = 0x8e2a26, necromancy = 0x6b3fa0 }
-- Each unit frame's own colour, the RuneUI preset.
style.FRAME_COLOURS = { player = 0x2f63a8, target = 0xa4511c }

-- Unit frame colour presets. RuneUI and Equipped have no rgb of their own: look resolves them per frame.
style.PRESETS = {
  { id = "runeui", label = "RuneUI" },
  { id = "gameGreen", label = "Game green", rgb = 0x2b8a1e },
  { id = "gameRed", label = "Game red", rgb = 0xc8281c },
  { id = "magic", label = "Magic", rgb = style.STYLE_COLOURS.magic },
  { id = "ranged", label = "Ranged", rgb = style.STYLE_COLOURS.ranged },
  { id = "melee", label = "Melee", rgb = style.STYLE_COLOURS.melee },
  { id = "necro", label = "Necro", rgb = style.STYLE_COLOURS.necromancy },
  { id = "equipped", label = "Equipped" },
}

-- The cast bar's RuneUI fill, for a channel with no combat style.
style.CAST_COLOUR = 0x23706a

-- Cast bar colour presets. Ability style has no rgb: the bar takes each channel's combat style colour.
style.CAST_PRESETS = {
  { id = "ability", label = "Ability style" },
  { id = "runeui", label = "RuneUI", rgb = style.CAST_COLOUR },
  { id = "gameGreen", label = "Game green", rgb = 0x2b8a1e },
  { id = "gameRed", label = "Game red", rgb = 0xc8281c },
  { id = "magic", label = "Magic", rgb = style.STYLE_COLOURS.magic },
  { id = "ranged", label = "Ranged", rgb = style.STYLE_COLOURS.ranged },
  { id = "melee", label = "Melee", rgb = style.STYLE_COLOURS.melee },
  { id = "necro", label = "Necro", rgb = style.STYLE_COLOURS.necromancy },
}

-- Where the spender rows sit: under the adrenaline bar, over it, or under the player frame.
style.SPENDER_PLACES = {
  { id = "below", label = "Below the bar" },
  { id = "above", label = "Above the bar" },
  { id = "player", label = "Under player frame" },
}

style.BORDERS = {
  { id = "runeui", label = "RuneUI" },
  { id = "game", label = "Game frame" },
  { id = "none", label = "None" },
}

-- The entry of list whose id is value, or nil.
function style.find(list, value)
  for _, entry in ipairs(list) do
    if entry.id == value then
      return entry
    end
  end
end

-- The font name for role in family, moved step points from the role's size and snapped to the nearest size the
-- family has, toward the step on a tie.
function style.font(family, role, step)
  local available = (style.find(style.FAMILIES, family) or style.FAMILIES[1]).sizes
  local want = style.ROLES[role] + step
  local best, bestGap = nil, math.huge
  for size in pairs(available) do
    local gap = math.abs(size - want)
    local better = gap < bestGap or gap == bestGap and (step < 0) == (size < best)
    if better then
      best, bestGap = size, gap
    end
  end
  return available[best]
end

local OUTLINE_FONTS = {
  NOTOSANS_BOLD_11 = "NOTO_SANS_11PT_BOLD_OUTLINE",
  NOTOSANS_BOLD_13 = "NOTO_SANS_13PT_BOLD_OUTLINE",
  NOTOSANS_BOLD_21 = "NOTO_SANS_21PT_BOLD_OUTLINE",
}

-- The client's outlined copy of a font name, or nil when it has none.
function style.outlineFont(name)
  return OUTLINE_FONTS[name]
end

-- A typed "#RRGGBB" or "RRGGBB" as a number, or nil.
function style.parseHex(text)
  local digits = type(text) == "string" and text:match("^%s*#?(%x%x%x%x%x%x)%s*$")
  return digits and tonumber(digits, 16)
end

function style.formatHex(rgb)
  return string.format("#%06X", rgb)
end

local function channels(rgb)
  return (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
end

-- Hue in degrees from 0 to 360, saturation and value from 0 to 1.
function style.hsv(rgb)
  local r, g, b = channels(rgb)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local d = max - min
  local h = 0
  if d > 0 then
    if max == r then
      h = ((g - b) / d) % 6
    elseif max == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
  end
  return h * 60, max > 0 and d / max or 0, max / 255
end

function style.rgb(h, s, v)
  local function channel(n)
    local k = (n + h / 60) % 6
    return math.floor((v - v * s * math.max(0, math.min(k, 4 - k, 1))) * 255 + 0.5)
  end
  return (channel(5) << 16) | (channel(3) << 8) | channel(1)
end

-- sRGB relative luminance above which a fill needs dark text.
local DARK_TEXT_LUMINANCE = 0.28

local function linear(c)
  c = c / 255
  return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

-- Whether Auto draws dark text over a fill of rgb.
function style.dark(rgb)
  local r, g, b = channels(rgb)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > DARK_TEXT_LUMINANCE
end

-- A saved frame colour, a preset id or a hex number, as rgb for frame.
local function frameColour(saved, frame, equippedStyle)
  if type(saved) == "number" then
    return saved
  end
  if saved == "equipped" then
    return style.STYLE_COLOURS[equippedStyle] or style.FRAME_COLOURS[frame]
  end
  local preset = style.find(style.PRESETS, saved)
  return preset and preset.rgb or style.FRAME_COLOURS[frame]
end

-- A saved cast bar colour as rgb, or nil for Ability style.
local function castColour(saved)
  if type(saved) == "number" then
    return saved
  end
  local preset = style.find(style.CAST_PRESETS, saved)
  return preset and preset.rgb
end

-- The look every element's setLook takes, from src/settings appearance and the worn weapon's combat style:
-- { fonts = { [role] = font name }, outline, shadow, auto, text, player, target, texture, border, frameWidth,
-- frameHeight, barWidth, barHeight, castWidth, castHeight, castColour, spenders }. fonts.cast is the cast bar's
-- body font, the HUD's unless the cast bar has its own font or size; castColour is nil for Ability style. Build
-- it only when one of them changes, as setLook skips a look it already shows.
function style.look(appearance, equippedStyle)
  local fonts = {}
  for role in pairs(style.ROLES) do
    fonts[role] = style.font(appearance.font, role, appearance.textStep)
  end
  local castFamily = appearance.castFont == "hud" and appearance.font or appearance.castFont
  local castStep = appearance.castTextSize == "hud" and appearance.textStep
    or appearance.castTextSize - style.ROLES.body
  fonts.cast = style.font(castFamily, "body", castStep)
  local edge, textColour = appearance.edge, style.find(style.TEXT_COLOURS, appearance.textColour)
  return {
    fonts = fonts,
    outline = edge == "outline" or edge == "outlineShadow",
    shadow = edge == "shadow" or edge == "outlineShadow",
    auto = textColour.id == "auto",
    text = textColour.rgb,
    player = frameColour(appearance.playerColour, "player", equippedStyle),
    target = frameColour(appearance.targetColour, "target", equippedStyle),
    texture = appearance.texture,
    border = appearance.border,
    frameWidth = appearance.frameWidth,
    frameHeight = appearance.frameHeight,
    barWidth = appearance.barWidth,
    barHeight = appearance.barHeight,
    castWidth = appearance.castMatchWidth and appearance.barWidth or appearance.castWidth,
    castHeight = appearance.castHeight,
    castColour = castColour(appearance.castColour),
    spenders = appearance.spenders,
  }
end

return style
