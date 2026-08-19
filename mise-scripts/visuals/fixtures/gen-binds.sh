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
# Only binds that belong to a submap are kept — the overlay filters on submap
# anyway, and the global binds are the bulk of the list.
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
kept = [b for b in binds if b.get("submap")]
if not kept:
    sys.exit("no submap binds found — is this a live session with the config loaded?")
json.dump(kept, sys.stdout, indent=1)
sys.stdout.write("\n")
' > "$dir/binds.json"

printf 'wrote %s (%s entries)\n' "$dir/binds.json" \
  "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$dir/binds.json")"
