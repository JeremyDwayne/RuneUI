#!/bin/sh
# Screenshots the RuneScape client window, even behind other windows, into the branch's evidence folder.
# Usage: shot.sh <name> [delay-seconds]
#   shot.sh buffs-tab            captures now
#   shot.sh tooltip-freezing 25  captures in 25 s, so the player can hover first
# Prints the JPEG path.
set -eu
name=${1:?usage: shot.sh <name> [delay-seconds]}
delay=${2:-0}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
branch=$(git -C "$repo" branch --show-current)
out="$repo/.scratch/${branch:-detached}/verify-runeui"
mkdir -p "$out"
win=$(swift "$here/gamewin.swift") || { echo "No RuneScape client window on screen." >&2; exit 1; }
id=${win%% *}
path="$out/$name.jpg"
screencapture -x -o -t jpg -T "$delay" -l "$id" "$path"
echo "$path"
