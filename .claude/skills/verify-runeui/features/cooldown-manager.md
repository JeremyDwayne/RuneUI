# Cooldown manager

The Cooldown manager page sets which abilities each cooldown group shows, per combat style. A player picks a group, sets its size and wrap, adds abilities from the **+** picker, drags icons to reorder them, and adds or deletes groups of their own.

## Sub-features

- `cooldowns-style` the page opens on the equipped style, marked Equipped, with tabs for the others.
- `cooldowns-settings` a group's icon size, per-row count, growth and shared-across-styles setting.
- `cooldowns-picker` **+** opens a list of known abilities with style tabs and a search box; picking one adds it.
- `cooldowns-reorder` dragging an icon moves it within the group.
- `cooldowns-remove` clicking an icon offers Remove.
- `cooldowns-custom` **New group** adds a group; **Delete** asks for a second click.

## How to get to it (user POV)

- Open the options window and choose **Cooldown manager** in the left menu.

## Driving it with the player and shot.sh

Preconditions:

- Baseline preconditions hold. The player has a weapon equipped.
- Run `scripts/db.sh --save cooldowns-before cooldownGroups groups`.

- **Open on style.** Ask the player to open **Cooldown manager**. Run `scripts/shot.sh cooldowns-style`. The equipped style's tab is current and marked Equipped.
- **Picker.** Ask the player to choose a group, press **+**, and type part of an ability name in the search box. Run `scripts/shot.sh cooldowns-picker`. The list shows only matching abilities, each with its icon.
- **Add.** Ask the player to click one result. Run `scripts/shot.sh cooldowns-add` and `scripts/db.sh --save cooldowns-after cooldownGroups`. The icon joins the group's grid, and the saved groups list the ability under that group and style.
- **Reorder.** Ask the player to drag the new icon to the front of the group. Run `scripts/shot.sh cooldowns-reorder`. It sits first, and the HUD group shows it first.
- **Remove.** Ask the player to click the icon and choose Remove. Run `scripts/shot.sh cooldowns-remove`. It leaves the grid and the HUD.
- **Restore.** Compare `cooldowns-before.txt` and a fresh `db.sh cooldownGroups`; ask the player to undo any change left over.

## Gotchas

- The picker lists preset abilities and abilities the player has used. An ability never used is missing until it is used once.
- Search text stays in the field while the picker is open; it clears when the picker opens again.
- Picking an ability that sits in another group moves it here rather than copying it.
- The picker closes when the page changes or the window closes. It has no close control of its own yet.
