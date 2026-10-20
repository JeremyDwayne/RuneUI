![RuneUI — a clean combat HUD for RuneScape 3](assets/branding/runeui-banner.png)

# RuneUI

A clean combat HUD for RuneScape 3. RuneUI draws compact unit frames, a resource bar, two rows of ability cooldowns and rows of buffs and debuffs in one block below your character, so the numbers you check mid-fight sit close together. Game windows such as the bank draw over it.

## What it shows

- The player frame shows your name and lifepoints as "13.1K | 78%" on a health bar, with a thin prayer bar underneath.
- The target frame shows your target's name and lifepoints as "6,800 | 58%".
- The resource bar fills with your adrenaline and shows its percent, with two marker notches you can set, such as 50% and 100%. With Necromancy it adds rows of blocks for residual souls and necrosis stacks. The soul row grows to 5 blocks while a Soulbound lantern is worn.
- The rotation and cooldowns rows hold ability icons. Each icon shows its action bar keybind, and dims and counts down in whole seconds while cooling. Hover an icon to see its name, cooldown length, keybind and ready state. A thin line on each row takes the colour of the combat style you last used.

- Four aura rows show the icons from the game's buff bar, debuff bar and target panel. Target debuffs sit above the target frame and your debuffs above the player frame, both with an orange edge. Long buffs such as overloads and prayer renewals sit below the player frame, and short combat buffs such as ultimates sit above the cooldowns row. Each icon shows its time left as the game's own label does, its stacks in the top right, and a swipe that empties as it runs out. In its last 10%, or its last 3 seconds when that is longer, an icon gets a white ring and its time turns black on a white plate. Hover an icon to see its name and description. The first time RuneUI sees an icon, it shows a name taken from the icon until the game's own name and description load, within about a minute.

A buff joins a row the first time RuneUI sees it: the combat row if it has a minute or less left, the long buff row if it has more, and no row if it has no timer, such as a percent. Target debuffs show no timer, because the game's target panel does not show one.

Abilities join a row the first time you use them. Ones with a cooldown of 30 seconds or more go in the cooldowns row, and the rest go in the rotation row. You can rearrange both rows yourself in the options window.

## Install

RuneUI runs on the RuneScape beta while plugins are in testing.

1. Copy the `runeui` folder into `dev_plugins` in the beta client's folder, such as `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\runeui` on Windows or `~/Jagex/RuneScape-BETA/dev_plugins/runeui` on macOS. Create `dev_plugins` if it does not exist.
2. Log in to the beta and open the console with Alt and the key under Esc.
3. Run `prf` to refresh the plugin list, then `pon runeui` to turn RuneUI on.

## Options

Open the plugin ribbon and press **Open RuneUI options**. Press Esc or **Done** to close the window.

- The Cooldown manager page shows both ability rows. Drag an icon to reorder it or move it to the other row, press **+** to add an ability you have used, and click an icon for a Remove option. The **+** list opens on your current combat style, with tabs for the other styles and a search box for ability names.
- The Resource bar page sets the threshold and ultimate marker percents.
- The Appearance page picks a flat bar fill or a vertical or horizontal gradient. It can also hide the game's own target panel, since RuneUI's target frame replaces it. **Game buff bars** hides the game's own buff and debuff bars, since RuneUI's aura rows replace them. **Aura icons** picks plain icons or icons with a draining bar under each. With bars, an icon in that window gets a dashed white outline and a striped bar instead of the ring and plate.
- Edit mode, turned on from the window's footer, lets you drag any HUD element to move it. Everything anchored to that element moves with it. Press Esc to finish, or **Done** to return to the window.
- To anchor an element, press its **Anchor** button in edit mode, click another element, then choose a side and alignment from the menu. The element sits flush against that side and keeps its gap when the other element grows or shrinks, such as when an ability row gains a tile. Its button then names the anchor, such as "Rotation, left, bottom", and pressing it removes the anchor. The frames and bars start anchored to the rotation row, so dragging the row moves the whole HUD.
- While you drag, an element snaps to the edges and centers of other elements and of the game window, or to a 16 px grid, and a line marks each snap. Hold Shift to move freely. **Snap on** in the toolbar turns snapping and the grid off. **Reset positions** asks first, then puts every element and anchor back.

RuneUI saves your layout, rows, markers and appearance and keeps them between sessions.

## What RuneUI reads and does

RuneUI only displays information the game already shows you. It reads your lifepoints, prayer, adrenaline, stacks and cooldowns from the game, along with the icons and keybinds on your action bars, the icons and time labels on the game's buff and debuff bars, the game's own target panel and your worn equipment. Ability, buff and debuff names come from the game's own data, the same names its tooltips show. Until RuneUI has looked up an icon's name, it shows one built from the icon's name in the game data. RuneUI saves which row each buff joined.

It never clicks, casts or sends anything to the game on your behalf. It needs no permissions and sends no data off your computer.

Hiding the game's target panel makes it fully transparent rather than closing it, because RuneUI reads the target's name and debuffs from it. Hiding the game's buff bars hides each icon and makes the rest of the bars fully transparent, because RuneUI reads the time labels from them. Turning either option back off, reloading RuneUI or turning it off restores the game's interfaces.

## Development

Specs use [busted](https://lunarmodules.github.io/busted/) and linting uses [luacheck](https://github.com/lunarmodules/luacheck), both installed with LuaRocks for Lua 5.4. From the repo root:

```sh
busted
luacheck .
for f in main.lua src/*.lua spec/*.lua spec/support/*.lua; do luac5.4 -p "$f"; done
```

After saving a change, run `prl runeui` in the game console to reload the plugin.

`src/adapter.lua` is the only module that reads the game client. `src/frames.lua`, `src/cooldowns.lua`, `src/auras.lua`, `src/settings.lua`, `src/editor.lua`, `src/layout.lua` and `src/icons.lua` are pure Lua with specs. `src/view.lua`, `src/options.lua` and `src/editmode.lua` draw the HUD, the options window and edit mode.

## Contributing

Bug reports and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first, and follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

RuneUI is released under the [MIT licence](LICENSE).

RuneScape is a trademark of Jagex Ltd. RuneUI is a fan-made plugin and is not affiliated with or endorsed by Jagex.
