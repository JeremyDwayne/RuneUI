# Contributing to RuneUI

Thanks for helping. Bug reports, fixes and ideas are all welcome.

## Before you start

Open an issue before starting anything bigger than a small fix, so we can agree on the approach first. A small fix can go straight to a pull request.

Every feature has to pass Jagex's plugin moderation, so RuneUI follows two rules:

- It only shows information the player can already see or know in the game. It never predicts hidden or future state, such as a boss's next attack.
- It never acts for the player. It sends no input, clicks, casts or menu actions.

A feature that bends either rule will be turned down, however useful it is.

## Setup

You need Lua 5.4 and LuaRocks. Install the test and lint tools:

```sh
luarocks --local --lua-version 5.4 install busted
luarocks --local --lua-version 5.4 install luacheck
eval "$(luarocks --lua-version 5.4 path)"
```

To try your changes in the game, follow the install steps in the README with your clone as the plugin folder, then run `prl runeui` in the game console after each save.

## Checks

Run all three from the repo root before opening a pull request. CI runs the same three.

```sh
busted
luacheck .
for f in main.lua src/*.lua spec/*.lua spec/support/*.lua; do luac5.4 -p "$f"; done
```

A bug fix starts with a spec that fails without the fix.

## How the code is laid out

- `src/adapter.lua` is the only module that reads the game client. It returns plain tables, so everything else can be tested without the game.
- `src/frames.lua`, `src/cooldowns.lua`, `src/channel.lua`, `src/auras.lua`, `src/auralists.lua`, `src/settings.lua`, `src/editor.lua`, `src/layout.lua`, `src/icons.lua` and `src/style.lua` are pure Lua, each with a spec in `spec/`. `src/presets.lua` is the data the groups start with, covered by `spec/settings_spec.lua`.
- `src/view.lua` draws the HUD, `src/options.lua` draws the options window, `src/appearancepage.lua` its Appearance page, `src/buffspage.lua` its Buffs page, `src/dragdrop.lua` the icon dragging the window shares, `src/editmode.lua` draws edit mode, and all six build on the helpers in `src/draw.lua`.

## Performance

RuneUI runs inside the game's frame, so its cost comes out of the player's frame rate.

- Redraw on the server tick, not every frame.
- Build components once at load and hide the ones not in use.
- Write component properties through `draw.set`, `draw.pos`, `draw.place`, `draw.width` and `draw.size`, which skip unchanged values. A tick where nothing changed should make no writes, and `spec/view_spec.lua` shows how to test that.
- Leave out looping animations, pulses and fades.

## Accessibility

Never carry meaning by colour alone. Avoid relying on red against green, green against brown, blue against purple, or light green against yellow. Add a second cue, such as text, position, shape or line style. Keep contrast high: light on very dark, or dark on light.

## Code style

- Follow the style of the file you are in. luacheck enforces the basics, including the 120 character line limit.
- Above each function, write a short comment saying what it does and how it is used. Leave history and the reasons for past decisions to commit messages.

## Pull requests

- Keep each pull request to one change, and keep commits small, with an imperative subject line such as "Hide the tooltip when the target dies".
- Say how you tested it. For anything visible, include a screenshot from the game.
- By contributing, you agree that your work is released under the project's MIT licence.

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
