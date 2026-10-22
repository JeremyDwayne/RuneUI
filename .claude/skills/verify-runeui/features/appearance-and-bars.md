# Appearance and Bars pages

The Appearance page restyles the HUD's text, unit frames and game interfaces, and the Bars page sets up the adrenaline bar and the cast bar. Both show a live preview strip at the top and scrolling settings below it. Every change shows on the preview and the HUD at once.

## Sub-features

- `appearance-preview` the preview's Dark, Light and Game backdrops.
- `appearance-text` font, text size, text edge and text colour.
- `appearance-frames` player and target colour presets, Custom colour, typed hex, fill, border, lifepoints text, frame width and height.
- `appearance-interfaces` hiding the game's target panel and cast bar.
- `appearance-scroll` the settings scroll with the wheel and the scrollbar thumb.
- `bars-adrenaline` marker percents, bar width and height, and Spenders placement.
- `bars-castbar` width source, width, height, colour, font and text size.
- `appearance-number` number fields step with - and +, and take typed values.

## How to get to it (user POV)

- Open the options window; it opens on **Appearance**. Choose **Bars** in the left menu for the Bars page.

## Driving it with the player and shot.sh

Preconditions:

- Baseline preconditions hold.
- Run `scripts/db.sh --save appearance-before appearance markers`.

- **Preview backdrops.** Ask the player to press **Light**. Run `scripts/shot.sh appearance-preview`. The preview strip shows a light lilac backdrop.
- **Frame colour.** Ask the player to pick a different **Player colour** preset. Run `scripts/shot.sh appearance-frames-after` and `scripts/db.sh --save appearance-after appearance`. The preset has a white ring, the preview and HUD player frame change colour, and the saved appearance holds the new colour.
- **Scroll.** Ask the player to scroll the settings with the wheel, then drag the scrollbar thumb to the bottom. Run `scripts/shot.sh appearance-scroll`. The last section, Game interfaces, shows and the thumb sits at the bottom.
- **Number field.** Ask the player to press + on **Frame width** twice. Run `scripts/shot.sh appearance-number`. The width reads 2 more and both frames grow.
- **Bars.** Ask the player to open **Bars** and change **Bar width**. Run `scripts/shot.sh bars-adrenaline`. The preview and HUD adrenaline bar change width.
- **Restore.** Ask the player to put each changed setting back; confirm against `appearance-before.txt`.

## Gotchas

- With the **Game** backdrop the preview shows the world through the window, which can make text hard to judge. Use Dark or Light for screenshots.
- Text settings do not apply to the options window, edit mode or tooltips.
- Hiding a game interface makes it transparent; it still takes up its place in the game's layout.
