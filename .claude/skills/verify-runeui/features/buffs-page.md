# Buffs page

The Buffs page lists every buff and debuff RuneUI has seen, plus the default debuff lists, in tabs. Buffs sit in Combat buffs, Upkeep buffs or Hidden; each debuff tab splits debuffs into Tracked and Not tracked, and only tracked debuffs show on the HUD. Icons drag to sort, and a click opens a menu of moves. The Display tab holds the game buff bar and aura icon options.

## Sub-features

- `buffs-tabs` Buffs, Target debuffs, Your debuffs and Display tabs switch the page.
- `buffs-move` the click menu moves an icon to another group, and the HUD row follows.
- `buffs-track` moving a debuff to Tracked or Not tracked shows or hides it on the HUD.
- `buffs-sort` dragging an icon swaps or inserts it, and the HUD row takes that order.
- `buffs-keepup` Keep up on an upkeep buff marks it K and shows a dim tile while it is missing with a target.
- `buffs-tooltip` hovering a page icon shows its name.
- `buffs-display` Game buff bars hides the game's own bars; Aura icons picks plain icons or icons with bars.

## How to get to it (user POV)

- Open the options window and choose **Buffs** in the left menu, then a tab.

## Driving it with the player and shot.sh

Preconditions:

- Baseline preconditions hold. The player has at least one upkeep buff active, such as a prayer renewal or an aura.
- Run `scripts/db.sh --save buffs-before auras trackedTarget trackedPlayer keepUp orderBuffs`.

- **Tabs.** Ask the player to open **Buffs**, then **Your debuffs**. Run `scripts/shot.sh buffs-tabs`. Tracked and Not tracked groups show with counts.
- **Track.** Ask the player to click a Not tracked debuff and choose **Track**. Run `scripts/shot.sh buffs-track-after` and `scripts/db.sh --save buffs-track-after trackedPlayer`. The icon moves to Tracked, and `trackedPlayer` holds its sprite as `true`.
- **Move a buff.** On the **Buffs** tab, ask the player to click a combat buff and choose **Hidden**. Run `scripts/shot.sh buffs-move-after`. The icon sits in Hidden and leaves the HUD's combat buff row; `db.sh auras` shows it as `hidden`.
- **Sort.** Ask the player to drag an icon between two others in its group. Run `scripts/shot.sh buffs-sort-after`. It sits where it was dropped, and the HUD row matches.
- **Keep up.** Ask the player to click an upkeep buff and turn **Keep up** on, then let it run out with a dummy targeted. Run `scripts/shot.sh buffs-keepup`. The page tile shows a K; the HUD shows it dim in a dashed outline with no time.
- **Tooltip.** Tell the player to hover a page icon within 25 seconds. Run `scripts/shot.sh buffs-tooltip 25`. The tooltip names the icon.
- **Restore.** Compare with `buffs-before.txt` and ask the player to undo leftover moves.

## Gotchas

- A debuff on the default lists is listed and tracked before it has ever been seen.
- Target debuffs only show on the HUD while the player has a target.
- The menu lists only the moves that apply; a debuff's menu has Track or Stop tracking, not both.
- Hovering waits for names; an icon seen for the first time may say it is looking up its name.
