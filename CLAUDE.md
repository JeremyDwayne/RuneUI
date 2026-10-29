# RuneUI for agents

RuneUI is a combat HUD plugin for RuneScape 3, written in Lua 5.4 and loaded by the game client. `CONTRIBUTING.md` has the setup, the checks, the code layout and the style rules. This file adds what an agent needs beyond it.

## Priorities

1. Moderation: show only what the player can already know, never act for them, and restore every game interface you change.
2. Frame rate: no steady-tick writes, client reads or per-frame work beyond what the client forces.
3. Game UI practice: tick-driven updates, components built once, no allocation on the hot path, accessible colour, every drag cancellable.
4. Features and polish.

## Working rules

- Done means all four checks pass. Paste their output, not "should pass".
- A bug fix starts with a spec that fails without it.
- Specs prove logic and write counts, not what the client draws. Anything visible is done when it has been seen in the game after `prl runeui`. Say which in-game checks are still open.
- Agree on the look of a visible change with a mockup before building it.
- Keep the README in step with anything a player can see.
- Comments say what code does and how it is used, never history. Commits are imperative with no AI attribution. No em dashes anywhere.

## How it runs

- The adapter reads the client through `pcall` and returns plain tables, and any read can be nil. Everything else is pure or draws through primitives that skip unchanged writes.
- `main.lua` wires the events: var changes feed the trackers, the server tick reads the adapter and redraws, the logic tick counts the cast bar and cooldowns down, the draw frame keeps hidden game interfaces hidden, and shutdown restores everything.
- Measured rates: Draw about 30 a second, Logic 50 a second, ServerLogic every 0.6 s, var changes in bursts during combat.
- A steady tick makes zero component writes, and the view, options and edit mode specs assert it. Draw and Logic handlers return before any client call when idle. The few per-frame reads exist because the client rebuilds a hidden interface between ticks, and each is commented where it happens.
- Every plugin on a root layer shares its 4096 dynamic component ids. The HUD on `TOPLEVEL_V2__GAME_AREA` is built once at load; the options window and edit mode on `TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP` hold nothing while closed. A create the client refuses gets a stand-in from `draw.new`, so build every component through it, and never pass a constructor straight to `pcall`, which aborts the client.
- Save to PersistentDB when a value changes, never per tick.

## Client behaviour

The client API is thinly documented. `docs/client-notes.md` lists what testing in the game found. Read it before touching game interfaces, hooks or input, confirm anything not listed with a throwaway plugin, and add what you learn.
