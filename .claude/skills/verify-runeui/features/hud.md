# HUD

RuneUI draws a player frame, a target frame, an adrenaline bar with spender rows, a cast bar, cooldown groups and four aura rows over the game. Hovering a cooldown or aura icon shows a tooltip with its name and details.

## Sub-features

- `hud-frames` player and target frames show name, lifepoints and percent.
- `hud-resource` the adrenaline bar fills and shows its markers; Necromancy adds soul and necrosis rows.
- `hud-castbar` a channelled ability shows on the cast bar with icon, name and seconds left.
- `hud-cooldowns` group icons show keybinds, dim and count down while cooling, and darken when the ability can't be cast.
- `hud-auras` buffs, your debuffs and target debuffs show in their rows with time left and stacks.
- `hud-tooltip-cooldown` hovering a cooldown icon shows its name, cooldown, keybind and ready state.
- `hud-tooltip-aura` hovering an aura icon shows its name and description.

## How to get to it (user POV)

- Log in with RuneUI on. The HUD shows at once.
- Attack a training dummy to fill the target frame, target debuffs and cooldowns.
- Hover any cooldown or aura icon for its tooltip.

## Driving it with the player and shot.sh

Preconditions:

- Baseline preconditions hold. The player stands at the combat dummies.

- **Idle HUD.** Ask the player to stand still out of combat. Run `scripts/shot.sh hud-idle`. The player frame, adrenaline bar and cooldown groups show; the target frame is empty.
- **Combat.** Ask the player to attack a dummy and use two abilities with cooldowns. Run `scripts/shot.sh hud-combat`. The target frame names the dummy, target debuffs sit above it, and the used icons are dim with seconds counting down.
- **Channel.** Ask the player to start a channelled ability, such as Asphyxiate or Rapid Fire. Run `scripts/shot.sh hud-castbar`. The cast bar shows the icon, name and seconds left.
- **Cooldown tooltip.** Tell the player to hover a cooldown icon within 25 seconds and hold still. Run `scripts/shot.sh hud-tooltip-cooldown 25`. The tooltip shows the ability's name, "Cooldown Ns", "Key K" and the ready state, with a white outline on the icon.
- **Aura tooltip.** Tell the player to hover a buff or debuff icon within 25 seconds. Run `scripts/shot.sh hud-tooltip-aura 25`. The tooltip shows the icon's name and, when the game has one, its description.

## Gotchas

- Target debuffs have no timer, because the game's target panel shows none.
- A newly seen icon shows a name built from its sprite for up to a minute while RuneUI looks up the game's name.
- The game's own buff bars, target panel and cast bar may be hidden by RuneUI's options. Check the Buffs page's Display tab and the Appearance page before reading a missing native bar as a bug.
- A delayed capture can land while the player is still moving the mouse. If the tooltip is missing, capture again with a longer delay.
