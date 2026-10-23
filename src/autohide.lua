-- Out of combat hiding: how the HUD shows from the Appearance page's Out of combat settings, whether the player
-- is in combat or has a target, and whether the options window or edit mode is open. main.lua reads
-- COMBATV2_PLAYER_IS_IN_COMBAT each server tick, since the var sends no changes, and applies the result through
-- view.hold and view.fade. Pure.
local autohide = {}

-- The HUD out of combat: at full, faded to the saved opacity, or hidden.
autohide.MODES = {
  { id = "show", label = "Show" },
  { id = "fade", label = "Fade" },
  { id = "hide", label = "Hide" },
}

-- Whether the combat var matters for appearance, so main.lua reads it only then.
function autohide.reads(appearance)
  return appearance.outOfCombat ~= "show"
end

-- Returns whether the HUD hides and the opacity it draws at, from 0 to 1. inCombat is the var's value, nil when
-- unread, which counts as in combat. With showWithTarget on, having a target shows it at full, and the options
-- window or edit mode, configuring, always does.
function autohide.state(appearance, inCombat, hasTarget, configuring)
  local mode = appearance.outOfCombat
  if mode == "show" or configuring or inCombat ~= 0 or (hasTarget and appearance.showWithTarget) then
    return false, 1
  end
  if mode == "hide" then
    return true, 1
  end
  return false, appearance.outOfCombatOpacity / 100
end

return autohide
