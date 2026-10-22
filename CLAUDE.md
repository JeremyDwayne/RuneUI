# RuneUI for coding agents

RuneUI is a combat HUD plugin for RuneScape 3, written in Lua 5.4 and loaded by the game client. Read `CONTRIBUTING.md` first. It holds the moderation rules, setup, the four checks, the module layout, and the performance, accessibility and style rules. This file adds what an agent needs on top of it.

## Priorities

When goals conflict, settle them in this order:

1. The moderation rules. A plugin that breaks them does not ship.
2. Game performance. RuneUI costs the player frame time, so a feature that adds steady-tick writes, client reads or per-frame work gets cut or redesigned.
3. Established practice for game UI and Lua: tick-driven updates, components built once and reused, no allocation on the hot path, accessible colour and contrast, and every drag cancellable.
4. Features and visual polish.

## Working rules

- Done means the four checks from `CONTRIBUTING.md` pass: `busted`, `luacheck .`, `luac5.4 -p` on every file and `stylua --check main.lua src spec tools`. Report their output, not "should pass".
- A bug fix starts with a spec that fails without the fix. View and options specs drive real modules through `spec/support/fake_ui.lua`.
- Specs prove logic and write counts, not what the client draws. Anything visible is done when it has been seen in the game after `prl runeui`. Say which in-game checks are still open.
- Before building a visible change, agree on the look with a mockup or screenshot.
- Keep `README.md` in step with every change a player can see. Moderation reads it.
- Comments say what code does and how it is used. They never record where a fact was learned, past decisions or history.
- Commit messages are imperative and describe the change on its own terms. Leave out AI attribution: no co-author trailers, session links or tool notes.
- Write plain sentences in docs, comments and commits, with no em dashes.

## Architecture

- `src/adapter.lua` is the only module that calls the client. Every read goes through `pcall` and comes back as a plain table, and a read can always be nil: interfaces unload, and vars are nil before login.
- `src/frames.lua`, `src/cooldowns.lua`, `src/channel.lua`, `src/auras.lua`, `src/auralists.lua`, `src/settings.lua`, `src/editor.lua`, `src/layout.lua`, `src/icons.lua`, `src/search.lua`, `src/style.lua`, `src/presets.lua` and `src/catalog.lua` are pure. Keep client globals out of them.
- `src/view.lua`, `src/options.lua`, `src/appearancepage.lua`, `src/buffspage.lua`, `src/aurasearch.lua`, `src/scrollbar.lua`, `src/dragdrop.lua` and `src/editmode.lua` draw through `src/draw.lua`, whose `set`, `pos`, `place`, `width` and `size` skip unchanged values.
- `main.lua` wires events: `VarTransmit` feeds the cooldown and channel trackers, `ServerLogic` reads the adapter and redraws, `Logic` redraws the cast bar and cooldown groups after their vars change and counts them down, and `PluginShutdown` destroys every component.

## Hot path

Handlers run inside the player's frame. The rates are measured, not documented.

- `Event.Draw` fires once per rendered frame, about 30 a second when measured. `Event.Logic` fires 50 times a second. `Event.ServerLogic` fires every 0.6 s tick. `VarTransmit` arrives in bursts during combat.
- A steady tick, where nothing in the game changed, makes 0 component writes. Specs in `spec/view_spec.lua`, `spec/options_spec.lua` and `spec/editmode_spec.lua` assert this. Keep them passing.
- `VarTransmit` handlers record the change and return. They make no client reads and draw nothing.
- `Draw` and `Logic` handlers return before any client call or allocation when idle, such as when no drag is under way. While a channel runs or a cooldown is cooling, a `Logic` handler counts the cast bar and the cooling tiles down and moves recharge bars with no client reads. On the Logic tick after a channel or cooldown var changes, it redraws the cast bar or the groups from the trackers, reading the channelled ability's struct once and reusing the action bar slots read on the last server tick. Three exceptions: while the native target panel is hidden, a `Draw` handler reads two of its alphas, because the client rebuilds the panel's frame sprites opaque between server ticks. While the native cast bar is hidden, a `Draw` handler reads the alphas of its root and time label. While the native buff bars are hidden, a `Draw` handler reads the icon of each slot up to 8 past the last buff for 8 frames after each server tick, because the client fills slots a few frames after the tick, and a potion fills several at once.
- Build components at load and hide the spares. Create and destroy only on player actions.
- Save to PersistentDB when a value changes, never per tick. A drag saves on release.

## Client behaviour found by testing

The client API is thinly documented, and these facts came from probing it in the game. When code depends on behaviour not listed here, confirm it in the game with a small throwaway plugin before relying on it. Add what you learn to this list and, where specs can model it, to `spec/support/fake_ui.lua`.

- `MoveToFront` on a hidden component, or on a layer holding one, stops it drawing for good, even after it is shown. Raise only while visible, as the tooltip does on its first show.
- Stacking follows creation order, for labels as for rects. Build what must sit on top last.
- `ONSCROLLWHEEL` fires dozens of times per scroll with deltas from 1 to 14, so scale the delta by pixels.
- `ONRELEASE` fires as soon as the cursor leaves the pressed component, with the button still held. A drag keeps the pressed component under the cursor until release. A 30px hit area that follows the cursor loses fast moves; `src/dragdrop.lua` grows it into a transparent 160px square centred on the cursor, which holds the press even under components created after it.
- A component hidden during its own press gets no `ONRELEASE`.
- Hooks cannot tell mouse buttons apart, so a right click fires `ONCLICK` too. A destructive action needs a second step.
- `Mouse.GetX` and `GetY` report physical pixels, twice the UI units on a Retina display. Convert with the ratio taken in a press hook, as `pressAt` in `src/draw.lua` does.
- Plain components start with `enabled = false` and `clickthrough = true`. Hover still fires on them. Each clickable thing has one hit area with both flipped, drawn under its label.
- A hit area stops a click from reaching hit areas under it, on other layers too, so a click on a popup row never also clicks the page behind it.
- `ui.Text` reports no wrapped height or line count. A label's wrapped height is estimated from its character count, as `view.tooltip` does.
- Alpha 0 is not hidden. Treat a transparent component as still taking clicks.
- `ui.Text` draws nothing until `font` is set. A `ui.InputField` draws no text without a `stylesheetID`: `id.StyleSheet.INPUT_DEFAULT` draws a plain field and `INPUT_SEARCHBOX_24PX` a search box. No call gives a field focus, so it takes keys only once clicked. Its `ONCONTENTCHANGED` fires on each keystroke, and again on Enter, Esc and focus loss, possibly after its popup has closed.
- Children of `TOPLEVEL_V2__GAME_AREA` draw under game windows such as the bank, so the HUD lives there. Children of `TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP` draw over everything, so the options window lives there. Both span the window.
- A layer anchored with `SetPos(x, y, px, py)` reports its resolved position in `x` and `y`. `xyGlobal` holds absolute screen coordinates.
- PersistentDB returns every number as a float, so convert with `math.tointeger` before indexing. A structured value of 400 entries of about 70 bytes saved and 800 failed, with the setter returning `false`, so check its result.
- `pairs(id.Component)`, `pairs(id.StyleSheet)` and `pairs(id.Sprite)` yield number keys with name values. `id.Sprite.FromID(sprite)` returns one sprite's name, while `id.Sprite[sprite]` with a number raises.
- `Keyboard.IsShiftDown()` and `IsGameKeyDown(GameKey.SHIFT)` read false inside `Event.Logic` with Shift held. Track Shift from `KeyDown` and `KeyUp`, as `src/editmode.lua` does.
- Hiding target panel components stops its debuff slots updating, even when only the frame containers `:25` and `:26` are hidden: a debuff appeared and never cleared. Make the panel transparent instead.
- A server tick's var changes arrive right after its `Event.ServerLogic`, before the next Draw frame.
- On the cast bar 764, the client fades the spark's glow `:19` in from opaque around each tick, so alpha 0 does not hold there. Hiding it holds.
- On the buff bars 284 and 291, the client sets each filled slot's icon `:0:0` and `:0:2` opaque several times a tick, so alpha 0 does not hold there. Hiding those two keeps the label counting and the slot filling, and the client shows them again only when it fills the slot. A hidden icon reads `visibleGlobal` false, so read a slot's visibility from its label `:0:1`.
- A buff bar slot can show an item instead of a sprite: an overload's icon reads `spriteID` -1 with `associatedObjectID` set to the item. `src/adapter.lua` reads such a slot as minus the item id, and `draw.icon` shows it with `SetAssociatedObject`.
- Moving a native interface off screen freezes it: its labels stop counting and new icons wait until it returns.
- A layer clips its children: a child reaching past its edge draws only the part inside, which edit mode's overlays depend on. A click hook on a part-clipped child reports y from the child's own top, clipped part included. Whether a clipped part takes clicks is unconfirmed, so `src/appearancepage.lua` checks each click lands where its row shows.
- A layer's `alpha` reads back but does not fade its children. Fade each component instead.
- A gradient with a transparent end blends over a canvas's earlier elements, so a filled rect, a white-to-clear `AddGradientH` and a clear-to-black `AddGradientV` draw a shade square.
- A label's shadow colour cannot be set: writing `shadowRGBA` or `shadowColour` raises. `isShadowed` works.
- No game font draws the check mark U+2713; each draws `?`. Mark a chosen option by fill and ring instead.
- `NOTO_SANS_11PT_BOLD_OUTLINE`, `_13PT_` and `_21PT_` draw white text with a dark outline that reads on white.
- The global `os` is nil, so there is no `os.clock` for timing. The two root layers report the whole window in UI units, such as 1710 by 1041 on a Retina Mac.

## Moderation

Beyond the two rules in `CONTRIBUTING.md`: hiding or recolouring a game interface is allowed, but every change needs a restore path on shutdown, on reload and when the option turns off. Never unhide a game component, or move or resize the click zones of action bars, inventory or equipment.
