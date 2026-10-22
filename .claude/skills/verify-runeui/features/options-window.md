# Options window

The options window holds RuneUI's settings on four pages: Appearance, Cooldown manager, Buffs and Bars. It opens from the plugin ribbon and closes with Done or Esc. Popups inside it, such as the ability picker and the Buffs page's icon menu, open over a page.

## Sub-features

- `options-open` the ribbon button opens the window on Appearance.
- `options-pages` the left menu switches pages and marks the current one.
- `options-done` Done closes the window.
- `options-esc` Esc closes the window, or ends edit mode first when it is on.
- `options-popups` a page's popup closes when the page changes or the window closes.

## How to get to it (user POV)

- Open the plugin ribbon and press **Open RuneUI options**.
- Press **Done** in the footer, or Esc, to close.

## Driving it with the player and shot.sh

Preconditions:

- Baseline preconditions hold.

- **Open.** Ask the player to press **Open RuneUI options** in the plugin ribbon. Run `scripts/shot.sh options-open`. The window shows with RuneUI in gold at top left and Appearance marked in the menu.
- **Switch pages.** Ask the player to choose **Cooldown manager**, then **Buffs**. Run `scripts/shot.sh options-pages`. The Buffs page shows its tabs and the menu marks Buffs.
- **Popup closes with the page.** Ask the player to open **Cooldown manager**, press the **+** tile, then choose **Buffs** in the menu. Run `scripts/shot.sh options-popups`. The Buffs page shows with no ability picker over it.
- **Done.** Ask the player to press **Done**. Run `scripts/shot.sh options-done`. The window is gone and the HUD shows.
- **Esc.** Ask the player to open the window again and press Esc. Run `scripts/shot.sh options-esc`. The window is gone.

## Gotchas

- Esc also reaches the game. With no RuneUI window open, Esc may close a game interface instead.
- A click with either mouse button counts as a click; RuneUI cannot tell them apart.
- The window draws over game interfaces such as the bank. Close the bank before judging the window's layout.
