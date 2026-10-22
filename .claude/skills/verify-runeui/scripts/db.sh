#!/bin/sh
# Reads RuneUI's saved data from the beta client's PluginData.db, read-only. Values are JSON text.
# Usage:
#   db.sh                         lists RuneUI's keys with their sizes in bytes
#   db.sh trackedPlayer auras     prints those keys' values
#   db.sh --save before trackedPlayer
#                                 also writes the output to the evidence folder as before.txt
set -eu
db="$HOME/Jagex/RuneScape-BETA/plugins/PluginData.db"
[ -r "$db" ] || { echo "No PluginData.db at $db" >&2; exit 1; }
save=""
if [ "${1:-}" = "--save" ]; then
  save=${2:?usage: db.sh --save <name> [key...]}
  shift 2
fi
run() {
  if [ $# -eq 0 ]; then
    sqlite3 -readonly "$db" "select Key, length(Value) from DataStore where PluginID = 'RuneUI' order by Key"
    return
  fi
  for key in "$@"; do
    echo "== $key"
    sqlite3 -readonly "$db" "select cast(Value as text) from DataStore where PluginID = 'RuneUI' and Key = '$key'"
  done
}
if [ -z "$save" ]; then
  run "$@"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
branch=$(git -C "$repo" branch --show-current)
out="$repo/.scratch/${branch:-detached}/verify-runeui"
mkdir -p "$out"
run "$@" | tee "$out/$save.txt"
echo "saved $out/$save.txt" >&2
