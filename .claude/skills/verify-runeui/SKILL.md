---
name: verify-runeui
description: Verify RuneUI, the RS3 combat HUD plugin, in the running RuneScape beta client. The player drives the game; the agent checks the client, screenshots the game window and reads RuneUI's saved data. Use to prove a HUD, options window, Buffs page or tooltip change in the game, and for the in-game checks a plan or review leaves open.
---

# Verify RuneUI in the game

RuneUI runs inside the RuneScape client, logged in to the player's own account. The agent never sends mouse or keyboard input to the client: synthetic input could read as macroing on the account. The player performs every game action. The agent checks the client, tells the player one step at a time what to do, screenshots the game window, and reads RuneUI's saved data to confirm side effects.

Helpers live in `scripts/` in the folder of this skill. Run them by path from anywhere; each finds the repo itself.

## Launch

The agent does not launch or log in to the client. If the doctor reports no client:

1. Ask the player to start the beta from the Jagex Launcher and log in.
2. Ask the player to open the console with Alt and the key under Esc, then run `prf` and `pon runeui`. After that, `prl runeui` reloads RuneUI after every code change.
3. Ready means the doctor passes and a screenshot shows the HUD, or the ribbon's **Open RuneUI options** button.

The client loads RuneUI from `~/Jagex/RuneScape-BETA/dev_plugins/runeui`, which is this checkout through a symlink. It runs whatever was on disk at the last `prl runeui`, so ask for a reload after every change, checkout or rebase. A git worktree elsewhere is never what the client runs: verify from the main checkout on the branch under test.

There is one client and one account, so runs never go side by side. Drive one feature at a time, and stop if the player is fighting or busy.

Teardown is nothing: the agent started no process. Leave the client as the player left it.

## Doctor

```sh
scripts/doctor.sh
```

Read-only. It checks that the beta client is running, that `dev_plugins/runeui` resolves to this checkout, that the game window is on screen, and that RuneUI has saved data. It prints the branch and commit and how many plugin files have uncommitted changes. Any `FAIL` line means stop and fix that first. Run it before every session and whenever a screenshot looks wrong.

## Drive

Each step pairs one player action with one observation:

1. Say exactly what to do, using the names shown on screen: "Open the plugin ribbon, press **Open RuneUI options**, then choose **Buffs** in the left menu."
2. End the turn and wait for the player to say it is done. Use a delayed capture only for a hover, such as a tooltip, which the player cannot hold while typing a reply: say what to hover, then start `scripts/shot.sh tooltip-freezing-blood 25` in the same message. The delay starts as the message appears, and the player still has to read it and switch to the game, so give at least 20 s. If the capture misses, ask the player to hover again and retry with a longer delay.
3. Capture with `scripts/shot.sh <name>`, then open the JPEG with the Read tool and check it against the expected result in the feature file.
4. For anything RuneUI saves, read the value before and after: `scripts/db.sh --save <name> <key>`. `scripts/db.sh` with no keys lists every saved key with its size.

Saved keys a feature changes: `auras` (each buff's row), `trackedTarget` and `trackedPlayer` (debuff choices), `keepUp`, `orderBuffs`, `orderTarget` and `orderPlayer` (Buffs page order), `debuffs` (icon names and struct ids), `cooldownGroups` and `groups` (Cooldown manager), `appearance`, `markers`, `layout` and `anchors` (positions), `known` (abilities seen).

Group several steps into one message when none needs a check in between, so the player is not asked one click at a time.

## Evidence

Proof goes to `.scratch/<branch>/verify-runeui/` in the repo: JPEGs from `shot.sh` and text from `db.sh --save`. It dies with the branch, like the spec and plan.

- Drive the real path a player takes: the ribbon button, the page, the click. A spec or a value written by hand does not count.
- Capture the state before the action and the state after it, not only the final screen.
- Confirm saved side effects with `db.sh` alongside the screenshot. A choice that shows on screen but is missing from the saved data has not survived a reload.
- To prove a value survives a reload, ask for `prl runeui` and capture again.
- Name each artifact after the feature file's sub-feature ID, such as `buffs-track-before.jpg`.
- Report each sub-feature as verified, failed or not reached, with the artifact paths. A step the player skipped is not reached, not verified.

## Cleanup

Delete only scratch copies the run made outside the evidence folder. Keep everything in `.scratch/<branch>/verify-runeui/`. If a verification run changed a setting the player did not want changed, list it in the report with its before value from `db.sh` and ask the player to put it back. Never edit `PluginData.db`.

## Feature map

`features/README.md` indexes one file per player-facing feature. Read the matching file before driving. A branch that changes how a player reaches or sees a feature updates that file in the same commit, and a new feature gets a new file.
