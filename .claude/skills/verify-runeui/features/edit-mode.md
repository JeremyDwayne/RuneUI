# Edit mode

Edit mode lets the player drag any HUD element to move it, anchor one element to another's side, and snap to edges, centers and a 16 px grid. Everything anchored to an element moves with it.

## Sub-features

- `edit-open` the footer checkbox turns edit mode on and shows each element's tag.
- `edit-drag` dragging an element moves it and everything anchored to it.
- `edit-snap` a drag snaps to edges, centers and the grid with a line marking each snap; Shift moves freely; **Snap on** turns snapping off.
- `edit-anchor` **Anchor**, a click on another element and a side choice anchor an element; pressing the named button removes it.
- `edit-reset` **Reset positions** asks first, then restores the default layout.
- `edit-exit` Esc or **Done** leaves edit mode.

## How to get to it (user POV)

- Open the options window and tick the edit mode checkbox in the footer.

## Driving it with the player and shot.sh

Preconditions:

- Baseline preconditions hold.
- Run `scripts/db.sh --save edit-before layout anchors`.

- **Open.** Ask the player to tick the edit mode checkbox. Run `scripts/shot.sh edit-open`. Each HUD element shows its tag and the toolbar shows **Snap on** and **Reset positions**.
- **Drag.** Ask the player to drag the resource bar a short way. Run `scripts/shot.sh edit-drag-after` and `scripts/db.sh --save edit-after layout`. The whole HUD moved with the bar, and the saved layout changed.
- **Exit.** Ask the player to press Esc. Run `scripts/shot.sh edit-exit`. Tags are gone and the HUD keeps its new place.
- **Restore.** Ask the player to drag the bar back, or to use **Reset positions** only if the layout was the default before; compare with `edit-before.txt`.

## Gotchas

- **Reset positions** discards the player's own layout. Never ask for it unless the before layout was already the default.
- A drag saves on release, so `db.sh` read during a drag shows the old layout.
- Shift is tracked from key presses; holding Shift before the drag starts is what frees the move.
