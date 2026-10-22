#!/bin/sh
# Read-only check that the running client is worth driving: the beta client is up, it loads RuneUI from
# this checkout, its window is on screen, and RuneUI has saved data. Prints one line per check and exits 1
# when any check fails.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
fail=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

if pgrep -f "rs2client.* BETA " >/dev/null; then
  ok "beta client running (pid $(pgrep -f 'rs2client.* BETA ' | head -1))"
elif pgrep -x rs2client >/dev/null; then
  bad "a client is running but not on the beta; plugins load only on the beta"
else
  bad "no RuneScape client running; ask the player to launch the beta and log in"
fi

loaded="$HOME/Jagex/RuneScape-BETA/dev_plugins/runeui"
if [ -d "$loaded" ] && [ "$(cd "$loaded" && pwd -P)" = "$(cd "$repo" && pwd -P)" ]; then
  ok "client loads RuneUI from $repo"
else
  bad "dev_plugins/runeui is not this checkout ($repo); the client runs $(cd "$loaded" 2>/dev/null && pwd -P || echo nothing)"
fi

if win=$(swift "$here/gamewin.swift" 2>/dev/null); then
  ok "game window on screen (id x y w h: $win)"
else
  bad "no RuneScape window on screen"
fi

db="$HOME/Jagex/RuneScape-BETA/plugins/PluginData.db"
keys=$(sqlite3 -readonly "$db" "select count(*) from DataStore where PluginID = 'RuneUI'" 2>/dev/null || echo 0)
if [ "$keys" -gt 0 ]; then
  ok "RuneUI saved data: $keys keys, db modified $(stat -f '%Sm' "$db")"
else
  bad "no RuneUI rows in $db; RuneUI has never run on this client"
fi

branch=$(git -C "$repo" branch --show-current)
dirty=$(git -C "$repo" status --porcelain -- main.lua src | wc -l | tr -d ' ')
echo "info  checkout on ${branch:-detached} at $(git -C "$repo" rev-parse --short HEAD), $dirty changed plugin files"
echo "info  the client runs the code from the last 'prl runeui'; ask for one after any change"
exit $fail
