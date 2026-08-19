#!/bin/sh
# Regenerate the which-key fixture from a LIVE Hyprland session.
#
#   mise-scripts/visuals/fixtures/gen-binds.sh
#
# The capture rig has no Hyprland, so Keymap.qml's `hyprctl binds -j` returns
# nothing there and the submap overlay would only ever render synthetic entries.
# This dumps the real binds once, into a committed fixture the rig feeds back via
# QS_BINDS_CMD.
#
# ALL binds are kept, global ones included. The which-key strip only ever shows a
# submap, so filtering to submaps looked right — but the fullscreen KeymapOverlay
# has a "Global" root node, and against a submap-only fixture it renders the tree
# correctly and then reports "0 binds". Keep the whole list.
#
# Re-run after changing keybindings.lua, or the screenshots drift from the config.
set -eu

dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

command -v hyprctl > /dev/null 2>&1 || {
  echo "hyprctl not found — run this from a live Hyprland session" >&2
  exit 1
}

hyprctl binds -j | python3 -c '
import json, sys
binds = json.load(sys.stdin)
if not binds:
    sys.exit("no binds found — is this a live session with the config loaded?")
json.dump(binds, sys.stdout, indent=1)
sys.stdout.write("\n")
' > "$dir/binds.json"

printf 'wrote %s (%s entries)\n' "$dir/binds.json" \
  "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$dir/binds.json")"
