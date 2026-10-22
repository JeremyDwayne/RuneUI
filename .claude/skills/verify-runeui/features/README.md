# RuneUI verification map

This folder is the maintained source for verifying what a RuneUI player sees and does. Read this index, then the feature file, before asking the player for a step.

## Baseline preconditions

- `scripts/doctor.sh` passes: beta client running, RuneUI loaded from this checkout, game window on screen, saved data present.
- The player ran `prl runeui` after the last change to `main.lua` or `src/`.
- The player is logged in, out of combat unless the recipe says otherwise, and standing somewhere safe, such as a bank or the combat dummies.
- The options window is closed and edit mode is off.

## Driving conventions

- The player performs every action in the game. The agent never sends input to the client.
- Name controls by the text the player sees: **Open RuneUI options**, **Buffs**, **Debuffs on you**, **Done**.
- Give one batch of steps per message, then end the turn and wait for "done". Use `scripts/shot.sh <name> <delay>` only for hovers, with a delay of at least 20 s.
- Combat recipes use a training dummy. Hitting it applies target debuffs; the player's own debuffs need a boss or a dummy that stuns.
- After a mutation, read the saved key with `scripts/db.sh` and say what changed.

## Proof and skip reporting

- A screenshot before and after each action, named `<sub-feature>-before.jpg` and `<sub-feature>-after.jpg`.
- Saved changes proven by `db.sh --save` text from before and after.
- Persistence proven by a capture after `prl runeui`.
- Report every sub-feature as verified, failed or not reached, with its artifacts. Never report one entry point as proof of another.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing what the player sees. Then four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the player and shot.sh`, and `Gotchas`. Keep implementation details out; name what the player sees and does.

## Features

- [HUD](./hud.md): unit frames, resource bar, cast bar, cooldown groups, aura rows and their tooltips.
- [Options window](./options-window.md): opening, page menu, closing with Done and Esc, popups.
- [Cooldown manager](./cooldown-manager.md): groups per style, adding abilities with the picker, reordering, custom groups.
- [Buffs page](./buffs-page.md): buff rows, tracked debuffs, sorting, Keep up and the Display tab.
- [Appearance and Bars pages](./appearance-and-bars.md): previews, text and frame settings, adrenaline and cast bar settings.
- [Edit mode](./edit-mode.md): moving, anchoring and snapping HUD elements.
