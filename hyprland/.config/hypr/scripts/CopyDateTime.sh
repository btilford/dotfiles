#!/bin/sh
# Copy a formatted current date/time onto the Wayland clipboard.
#
# Bound from the `time-cmd` submap in lua/keybindings.lua. Takes a format NAME, never
# a raw date(1) format string: the table lives here, so the keybindings file stays
# readable and a format is fixed in one place rather than in seven binds.
#
# clipborg is not asked to generate the value — it is a watcher, and the clipboard
# write below is what it watches. The `clipborg insert` alongside exists only so the
# entry carries a real source instead of the class of whatever window happened to be
# focused; clipborg's hash dedup collapses the two into one entry.

set -u

usage() {
  echo "usage: CopyDateTime.sh <format>" >&2
  echo "  date time datetime iso stamp epoch daily" >&2
  echo "  date-utc time-utc datetime-utc iso-utc" >&2
}

[ $# -eq 1 ] || {
  usage
  exit 2
}

# `date -u -Iseconds` renders the offset form (+00:00), which is correct and not what
# anyone wants pasted — iso-utc spells the Z explicitly.
case "$1" in
  date) value=$(date +%Y-%m-%d) ;;
  time) value=$(date +%H:%M:%S) ;;
  datetime) value=$(date "+%Y-%m-%d %H:%M:%S") ;;
  iso) value=$(date -Iseconds) ;;
  stamp) value=$(date +%Y-%m-%dT%H:%M:%S) ;; # Operon frontmatter shape
  epoch) value=$(date +%s) ;;
  daily) value=$(date +%b-%d-%a) ;; # vault daily-note filename
  date-utc) value=$(date -u +%Y-%m-%d) ;;
  time-utc) value=$(date -u +%H:%M:%S) ;;
  datetime-utc) value=$(date -u "+%Y-%m-%d %H:%M:%S") ;;
  iso-utc) value=$(date -u +%Y-%m-%dT%H:%M:%SZ) ;;
  *)
    echo "CopyDateTime.sh: unknown format '$1'" >&2
    usage
    exit 2
    ;;
esac

# printf, not echo, and wl-copy -n: a trailing newline in a pasted timestamp is the
# entire bug class this feature invites. `echo` would add one, and wl-copy keeps
# whatever it is given.
printf '%s' "$value" | wl-copy -n || {
  echo "CopyDateTime.sh: wl-copy failed" >&2
  exit 1
}

# Best-effort, and never fatal: a missing or stopped clipborg must not fail a copy
# that already succeeded.
if command -v clipborg > /dev/null 2>&1; then
  printf '%s' "$value" | clipborg insert --source hypr-datetime > /dev/null 2>&1 || true
fi

# Also best-effort. The copy is the feature; the toast is feedback about it.
notify-send -u low -t 1500 -a clipboard "Copied $1" "$value" > /dev/null 2>&1 || true
