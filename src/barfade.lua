-- How the game's action bars draw while faded: each bar's opacity from the appearance settings, and each
-- component's hidden state and alpha scale from its part. src/actionbars writes the result to the client.
local barfade = {}

-- A slot's parts by static ID offset from its background sprite. Any other offset is "other".
barfade.SLOT_PARTS = { [-1] = "frame", [4] = "flash", [6] = "queue", [8] = "highlight", [9] = "keybind" }

-- Parts hidden at any opacity below 100. The client animates the flash, queue circle and highlight, and sets a
-- slot's frame opaque on any frame of a tick, so a fade cannot hold on them.
local HIDDEN = { frame = true, flash = true, queue = true, highlight = true }

-- Percent opacity bar, 1 for the main bar to 5, draws at: its barOpacity while faded, or 100 while unfaded, while
-- fadeBars, the switch over every bar, is off, or while hovered with Show on hover on. hovered is whether the
-- mouse is over this bar and anyHovered whether it is over any faded bar, which counts as hovering every bar
-- while hoverAllBars is on.
function barfade.level(appearance, bar, hovered, anyHovered)
  local shown = hovered or (anyHovered and appearance.hoverAllBars)
  local off = appearance.fadeBars == false or not appearance["fadeBar" .. bar]
  if off or (shown and appearance["hoverBar" .. bar]) then
    return 100
  end
  return appearance["barOpacity" .. bar]
end

-- Whether a component of part, a SLOT_PARTS value or "other", is hidden at level percent, and the scale for the
-- alpha the client gave it. At 100 nothing is hidden and the scale is 1. The scale stays at 1% or more, too faint
-- to see, so a component the client sets transparent reads apart from one RuneUI faded.
function barfade.state(part, level)
  if level >= 100 then
    return false, 1
  end
  if HIDDEN[part] or (level == 0 and part == "keybind") then
    return true, 1
  end
  return false, math.max(level, 1) / 100
end

return barfade
