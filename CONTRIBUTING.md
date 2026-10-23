# Contributing

Bug reports, fixes and ideas are welcome. Open an issue before anything bigger than a small fix, so we can agree on the approach first.

## Two rules

RuneUI has to pass Jagex's plugin moderation, so:

- It only shows what the player can already see or know in the game. It never predicts hidden or future state.
- It never acts for the player. It sends no input, clicks, casts or menu actions.

Hiding or recolouring a game interface is fine as long as turning the option off, reloading or disabling the plugin restores it. Never unhide a game component, or move or resize the click zones of action bars, inventory or equipment.

## Setup

Install Lua 5.4, LuaRocks and [StyLua](https://github.com/JohnnyMorganz/StyLua), then:

```sh
luarocks --local --lua-version 5.4 install busted
luarocks --local --lua-version 5.4 install luacheck
eval "$(luarocks --lua-version 5.4 path)"
```

To try changes in the game, follow the install steps in the README with your clone as the plugin folder and run `prl runeui` in the console after each save.

## Checks

Run all four before opening a pull request. CI runs the same.

```sh
busted
luacheck .
for f in main.lua src/*.lua spec/*.lua spec/support/*.lua tools/*.lua; do luac5.4 -p "$f"; done
stylua --check main.lua src spec tools
```

A bug fix starts with a spec that fails without it.

## How the code fits together

- One module reads the game client and two write to its interfaces. Everything else sees plain tables, so it runs in specs without the game.
- Trackers turn var changes and tick reads into display models. Saved settings load through a small store, which specs replace with a fake.
- Each HUD element, options page and popup is its own module. All of them draw through one set of primitives that skip unchanged writes.
- The catalog of every buff and debuff is generated from a dump of the game's data. Edit the sources beside it and regenerate, rather than the output.

Each module's first comment says what it does and how it is used.

## Performance

The plugin runs inside the game's frame, so its cost is the player's frame rate.

- Redraw on the server tick or on the event that changed the data, not every frame.
- Build a component once and hide it when unused: the HUD at load, the options window on its first open, and a group or row's tiles as they are first needed.
- Write through the primitives that skip unchanged values. A tick where nothing changed makes no writes, and the view specs assert it.
- No looping animations, pulses or fades.

## Style

- StyLua formats everything and luacheck catches unused and shadowed names.
- Never carry meaning by colour alone, and keep contrast high: light on very dark. Avoid red against green, green against brown, blue against purple, and light green against yellow.
- Comments say what code does and how it is used, not history.
- Commits are small with an imperative subject. Say how you tested, with a game screenshot for anything visible.

By contributing you agree that your work is released under the MIT licence. Everyone follows the [code of conduct](CODE_OF_CONDUCT.md).
