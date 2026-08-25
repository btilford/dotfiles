#!/usr/bin/env bash
# Ranking tests for the quickshell launcher's selection history.
#
# Usage:
#   mise-scripts/launcher-rank-test.sh [--shell FILE] [--keep]
#
#   --shell FILE  quickshell entry point. Default: the copy in this repo, so a run tests the
#                 working tree rather than what happens to be stowed.
#   --keep        leave the nested session running afterwards (debugging).
#
# Boots a private headless wlroots compositor (sway, WLR_BACKENDS=headless) on its own session
# bus and its own $XDG_RUNTIME_DIR, seeds a THROWAWAY launcher database with backdated rows, runs
# `qs` inside it, and asserts the order that `qs ipc call launcher results` returns.
#
# What it proves, in order:
#
#   1. Decay is real. A row with 50 hits from 90 days ago ranks BELOW one with 8 hits from
#      yesterday. Backdated `last_used_at` is what exercises that without waiting 30 days.
#   2. The recency pin is exactly one row, and it is per KIND.
#   3. The keystroke path does no I/O. `sqlite3` is shadowed by a wrapper that logs every call;
#      the log must not grow while characters are typed into the launcher.
#   4. Directories stay above files in files mode, however hot a file is.
#   5. Fail-open on all three routes: an unwritable path, no sqlite3 binary at all, and a
#      corrupt database. The middle one matters most because it never reaches fail() — with no
#      binary to spawn, `ready` and `loaded` simply stay false while `healthy` stays true.
#
# DANGER, the same one visual-capture.sh carries: a compositor started without a forced headless
# backend takes DRM master and kills the live session and every app in it. Never start one from
# here without BOTH an isolated $XDG_RUNTIME_DIR and WLR_BACKENDS=headless.
#
# A private display is NOT a private bus. quickshell runs a notification server, so a rig on the
# live session bus claims org.freedesktop.Notifications away from the running daemon. This starts
# its own dbus-daemon and refuses to run without one.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="$REPO/quickshell/.config/quickshell/shell.qml"
KEEP=0
SIZE="1280x800"

log() { printf '\033[1;36m[rank]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[rank]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[rank]\033[0m %s\n' "$*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --shell)
      SHELL_QML="${2:-}"
      shift 2
      ;;
    --keep)
      KEEP=1
      shift
      ;;
    -h | --help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -f "$SHELL_QML" ] || die "no quickshell entry point at $SHELL_QML"
for tool in sway qs grim sqlite3 dbus-daemon jq; do
  command -v "$tool" > /dev/null 2>&1 || die "missing required tool: $tool"
done

# The system sqlite3, not whatever wins $PATH. On this host a bare `sqlite3` resolves through
# mise to the Android platform-tools build, which has no pow() — the seeding below only needs
# plain SQL, but the wrapper in step 3 has to exec something that works.
REAL_SQLITE="$(command -v sqlite3)"
[ -x /usr/bin/sqlite3 ] && REAL_SQLITE=/usr/bin/sqlite3

WIDTH="${SIZE%x*}"
HEIGHT="${SIZE#*x}"

# Short path on purpose: a wayland socket path over 108 bytes is rejected by libwayland, and the
# scratch directories agents run under are long. mktemp keeps it unique without reusing a pid.
RUNTIME="$(mktemp -d /tmp/qs-rank.XXXXXX)" || die "cannot create a scratch directory"
SWAY_PID=""
QS_PID=""
DBUS_PID=""
KBD_PID=""

cleanup() {
  [ "$KEEP" = "1" ] && {
    log "--keep: session left at XDG_RUNTIME_DIR=$RUNTIME"
    return
  }
  [ -n "$KBD_PID" ] && kill "$KBD_PID" 2> /dev/null
  [ -n "$QS_PID" ] && kill "$QS_PID" 2> /dev/null
  [ -n "$SWAY_PID" ] && kill "$SWAY_PID" 2> /dev/null
  [ -n "$DBUS_PID" ] && kill "$DBUS_PID" 2> /dev/null
  sleep 0.3
  rm -rf "$RUNTIME"
}
trap cleanup EXIT INT TERM

chmod 700 "$RUNTIME"

failures=0
checks=0
check() {
  local what="$1" want="$2" got="$3"
  checks=$((checks + 1))
  if [ "$want" = "$got" ]; then
    printf '\033[1;32m  ok  \033[0m %s\n' "$what"
  else
    printf '\033[1;31m FAIL \033[0m %s\n       want: %s\n        got: %s\n' "$what" "$want" "$got"
    failures=$((failures + 1))
  fi
}

# --- the fixtures ------------------------------------------------------------
# Desktop entries of our own, in a private XDG_DATA_HOME **and** XDG_DATA_DIRS, so the
# assertions do not depend on whatever happens to be installed on the machine running this.
# Both are needed: XDG_DATA_HOME alone still leaves /usr/share/applications in the search path,
# and the launcher then lists every app on the box.
APPDIR="$RUNTIME/data/applications"
mkdir -p "$APPDIR"
mkapp() {
  cat > "$APPDIR/$1.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=/bin/true
Terminal=false
EOF
}
# Names chosen so plain alphabetical order is known, and so that one query ("ar") separates
# every match tier: Arcade has it as a PREFIX, the other four only as a substring.
mkapp zz-arcade "Arcade"
mkapp zz-aardvark "Aardvark"
mkapp zz-barnacle "Barnacle"
mkapp zz-cormorant "Cormorant"
mkapp zz-dromedary "Dromedary"

DB="$RUNTIME/launcher.db"
NOW="$(date +%s000)"
DAY=86400000
seed() {
  # seed <kind> <key> <label> <hits> <score> <days ago>
  local ago=$((NOW - $6 * DAY))
  "$REAL_SQLITE" "$DB" "INSERT INTO selections (kind,key,label,hits,score,first_used_at,last_used_at)
    VALUES ('$1','$2','$3',$4,$5,$ago,$ago);"
}

"$REAL_SQLITE" "$DB" "
CREATE TABLE IF NOT EXISTS selections (
  kind TEXT NOT NULL, key TEXT NOT NULL, label TEXT,
  hits INTEGER NOT NULL DEFAULT 0, score REAL NOT NULL DEFAULT 0,
  first_used_at INTEGER NOT NULL, last_used_at INTEGER NOT NULL,
  PRIMARY KEY (kind, key));" || die "could not seed $DB"

# The key is DesktopEntry.id, which carries NO `.desktop` suffix (verified on qs 0.3.0:
# `zz-cormorant`, not `zz-cormorant.desktop`).
#
# THE DECAY CASE. Cormorant is the stale heavyweight: 50 selections, none in 90 days. Dromedary
# is the light recent one: 8 selections, yesterday. Raw counts say Cormorant; a 30-day half-life
# says Dromedary, by a factor of eight (90 days = three half-lives).
seed app zz-cormorant Cormorant 50 50.0 90
seed app zz-dromedary Dromedary 8 8.0 1
# Barnacle is the most recent pick of all, with a trivial score. It gets the pin on an empty
# query and must lose it the moment anything is typed.
seed app zz-barnacle Barnacle 1 1.0 0
# An emoji, to prove the pin is per kind rather than global.
seed emoji "🦀" "crab" 3 3.0 0

# --- private session bus -----------------------------------------------------
DBUS_ADDR="$(dbus-daemon --session --fork --print-address --print-pid=3 3> "$RUNTIME/dbus.pid")"
DBUS_PID="$(cat "$RUNTIME/dbus.pid" 2> /dev/null)"
[ -n "$DBUS_ADDR" ] || die "no private session bus — refusing to run on the live one"
export DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR"

# --- headless compositor -----------------------------------------------------
cat > "$RUNTIME/sway.conf" << EOF
output HEADLESS-1 mode ${WIDTH}x${HEIGHT}@60Hz position 0 0
default_border none
default_floating_border none
focus_follows_mouse no
EOF

env -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
  XDG_RUNTIME_DIR="$RUNTIME" \
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
  sway -c "$RUNTIME/sway.conf" > "$RUNTIME/sway.log" 2>&1 &
SWAY_PID=$!

WL=""
for _ in $(seq 1 50); do
  WL="$(find "$RUNTIME" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -printf '%f\n' 2> /dev/null | head -1)"
  [ -n "$WL" ] && break
  sleep 0.2
done
[ -n "$WL" ] || die "headless compositor never came up — see $RUNTIME/sway.log"
export XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="$WL"
unset DISPLAY HYPRLAND_INSTANCE_SIGNATURE
log "headless ${WIDTH}x${HEIGHT} session on $WL"

# WLR_LIBINPUT_NO_DEVICES=1 leaves the seat with no keyboard at all, and a seat with no keyboard
# never advertises the capability — so no surface is ever told it has focus and every synthetic
# keypress is discarded. wtype's virtual keyboard lives only as long as its process, so one is
# parked here for the whole run (-s is the delay BETWEEN keystrokes).
if command -v wtype > /dev/null 2>&1; then
  wtype -s 3600000 -- " " " " > /dev/null 2>&1 &
  KBD_PID=$!
  sleep 0.3
else
  warn "wtype not installed — the keystroke test will be skipped"
fi

# --- the sqlite3 wrapper (test 3) --------------------------------------------
# Every sqlite3 invocation the shell makes is logged here. This is what turns "ranking must not
# start a subprocess on the keystroke path" from an intention into an assertion.
SQL_LOG="$RUNTIME/sqlite3-calls.log"
: > "$SQL_LOG"
mkdir -p "$RUNTIME/bin"
cat > "$RUNTIME/bin/sqlite3" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$SQL_LOG"
exec "$REAL_SQLITE" "\$@"
EOF
chmod +x "$RUNTIME/bin/sqlite3"

# start_qs <db> [path] [home]
# `path` REPLACES $PATH for the shell under test rather than prefixing it — test 10 needs a
# $PATH with no sqlite3 anywhere on it, and a prefix would leave /usr/bin reachable behind it.
start_qs() {
  # shellcheck disable=SC2097,SC2098  # deliberate: the env is scoped to the qs process only
  PATH="${2:-$RUNTIME/bin:$PATH}" \
    HOME="${3:-$HOME}" \
    XDG_DATA_HOME="$RUNTIME/data" \
    XDG_DATA_DIRS="$RUNTIME/data" \
    HYPR_NOTIFY=swaync \
    QS_LAUNCHER_DB="$1" \
    QS_NOTIFY_DB="$RUNTIME/notifications.db" \
    qs -p "$SHELL_QML" > "$RUNTIME/qs.log" 2>&1 &
  QS_PID=$!
  for _ in $(seq 1 100); do
    grep -q "Configuration Loaded" "$RUNTIME/qs.log" 2> /dev/null && return 0
    kill -0 "$QS_PID" 2> /dev/null || break
    sleep 0.2
  done
  return 1
}

stop_qs() {
  [ -n "$QS_PID" ] && kill "$QS_PID" 2> /dev/null
  wait "$QS_PID" 2> /dev/null
  QS_PID=""
  sleep 0.5
}

ipc() { qs ipc --pid "$QS_PID" call -- "$@" 2> /dev/null; }
# `--` is load-bearing: `show` is also an `ipc` subcommand name.
ipc_quiet() { qs ipc --pid "$QS_PID" call -- "$@" > /dev/null 2>&1; }

# Wait until a keypress actually reaches the launcher, and prove it by its effect rather than by
# sleeping. A layer surface has to be given the keyboard before any synthetic key lands, and how
# long that takes varies — sleeping "long enough" is what made the Ctrl+Del step flaky, and a
# keyboard test that silently does nothing passes for the wrong reason.
#
# The probe types a character that matches none of the fixtures, so the result count collapses,
# then deletes it again. When the count moves, the surface has the keyboard.
focus_ready() {
  local before after
  for _ in $(seq 1 20); do
    before="$(ipc launcher results 40 | jq 'length')"
    wtype -- "z" > /dev/null 2>&1
    sleep 0.3
    after="$(ipc launcher results 40 | jq 'length')"
    wtype -k BackSpace > /dev/null 2>&1
    sleep 0.2
    [ -n "$before" ] && [ "$after" != "$before" ] && return 0
  done
  warn "the launcher never took the keyboard"
  return 1
}

# Labels of the ranked results, one per line, for the kinds asked for.
labels() { ipc launcher results 40 | jq -r ".[] | select(.kind == \"$1\") | .label"; }
keys() { ipc launcher results 40 | jq -r ".[] | select(.kind == \"$1\") | .key"; }

start_qs "$DB" || die "quickshell never loaded — see $RUNTIME/qs.log"
log "quickshell up ($SHELL_QML)"
sleep 1.5 # the store's initial load is a subprocess; ranking is the pre-history order until it lands

# --- 1 + 2: empty query, in drun --------------------------------------------
ipc_quiet launcher show drun
sleep 1.0
got="$(labels app | head -4 | paste -sd, -)"
# Barnacle is pinned (most recent for this kind), then decayed score: Dromedary (8 hits
# yesterday) above Cormorant (50 hits, 90 days old), then the unused Aardvark alphabetically.
check "empty query: pin, then decayed score, then alphabetical" \
  "Barnacle,Dromedary,Cormorant,Aardvark" "$got"

# --- 3: no I/O on the keystroke path ----------------------------------------
if [ -n "$KBD_PID" ]; then
  focus_ready
  before="$(wc -l < "$SQL_LOG")"
  wtype -s 40 -- "ar" > /dev/null 2>&1
  sleep 0.8
  after="$(wc -l < "$SQL_LOG")"
  check "typing starts no sqlite3 process" "$before" "$after"

  # --- 4: a typed query outranks history --------------------------------------
  # Four of the five contain "ar" (Cormorant does not), which separates both rules at once:
  #
  #   Arcade     prefix (tier 1), NO history at all — and it still leads
  #   Dromedary  substring (tier 3), score 8 decayed one day -> 7.8
  #   Barnacle   substring (tier 3), score 1                 -> 1.0  (its pin does not apply)
  #   Aardvark   substring (tier 3), no history              -> 0
  #
  # So the match tier decides first, usage only breaks ties WITHIN a tier, and the recency pin
  # is gone the moment anything is typed.
  got="$(labels app | head -5 | paste -sd, -)"
  check "non-empty query: match tier first, score only within a tier" \
    "Arcade,Dromedary,Barnacle,Aardvark" "$got"
  wtype -k BackSpace -k BackSpace > /dev/null 2>&1
  sleep 0.5
else
  warn "skipping the keystroke tests (no wtype)"
fi

ipc_quiet launcher hide
sleep 0.5

# --- 5: the pin is per KIND, not global --------------------------------------
# The seeded crab is the newest selection of any kind, but opening the emoji tab must pin the
# last EMOJI, and opening drun must pin the last app — which the first check already showed.
# From the tree under test, not from $HOME: --shell defaults to the repo copy, so keying this off
# the stowed path would silently warn-skip the check on an unstowed clone.
EMOJI_JSON="$(dirname "$SHELL_QML")/config/emoji.json"
if [ -f "$EMOJI_JSON" ]; then
  ipc_quiet launcher show emoji
  sleep 1.2
  got="$(keys emoji | head -1)"
  check "the recency pin is per kind" "🦀" "$got"
  ipc_quiet launcher hide
  sleep 0.4
else
  warn "skipping the per-kind pin check (no $EMOJI_JSON)"
fi

# --- 6: the forget key -------------------------------------------------------
# Ctrl+Del on the top row drops its history and it falls back to alphabetical position.
if [ -n "$KBD_PID" ]; then
  ipc_quiet launcher show drun
  sleep 0.8
  focus_ready # the surface has to take the keyboard again after every hide/show

  # An app row must still know its own history key at this point, several tab switches after it
  # was built. It did not: the row held the DesktopEntry itself, DesktopEntries hands out a fresh
  # wrapper on every read, and the captured one read back as null — so Ctrl+Del silently did
  # nothing about half the time and the results IPC reported blank keys. Rows now copy the id as
  # a string. Checked HERE rather than at first open because the reference dies with a delay.
  got="$(keys app | grep -c '^$')"
  check "app rows still carry their history key after a tab round-trip" "0" "$got"

  wtype -M ctrl -k Delete -m ctrl > /dev/null 2>&1
  sleep 1.0
  got="$(labels app | head -5 | paste -sd, -)"
  # Barnacle loses both its pin and its score, so Dromedary leads and Barnacle sits
  # alphabetically among the unused rows — still IN the list, which is the whole point.
  check "Ctrl+Del drops the row's history, not the row" \
    "Dromedary,Cormorant,Aardvark,Arcade,Barnacle" "$got"
  ipc_quiet launcher hide
  sleep 0.3
fi

# --- 7: a selection is actually written ---------------------------------------
# End to end: pick the top row and read the row back out of the file. Aardvark has no history at
# all going in, so a `hits` of 1 can only have come from this.
if [ -n "$KBD_PID" ]; then
  ipc_quiet launcher show drun
  sleep 0.8
  focus_ready
  # after the forget above the order is Dromedary, Cormorant, Aardvark, ... — walk down to
  # Aardvark and launch it (Exec=/bin/true)
  wtype -k Down -k Down -k Return > /dev/null 2>&1
  sleep 2.0 # the write batches through a subprocess ~200ms later, then re-reads
  got="$("$REAL_SQLITE" -readonly -noheader "$DB" \
    "SELECT key || ':' || hits FROM selections WHERE kind='app' AND key='zz-aardvark';")"
  check "a selection is recorded in the database" "zz-aardvark:1" "$got"
  if [ -n "${RANK_DEBUG:-}" ]; then
    "$REAL_SQLITE" -readonly "$DB" "SELECT * FROM selections;" >&2
    tail -5 "$SQL_LOG" >&2
  fi
fi

stop_qs

# --- 8: an unwritable database leaves the launcher working -------------------
BADDB="$RUNTIME/nope/launcher.db"
mkdir -p "$RUNTIME/nope"
chmod 500 "$RUNTIME/nope"
start_qs "$BADDB" || die "quickshell never loaded with an unwritable database — see $RUNTIME/qs.log"
sleep 1.5
ipc_quiet launcher show drun
sleep 1.0
got="$(labels app | head -5 | paste -sd, -)"
check "unwritable database: the launcher works, unranked" \
  "Aardvark,Arcade,Barnacle,Cormorant,Dromedary" "$got"
ipc_quiet launcher hide
chmod 700 "$RUNTIME/nope"
stop_qs

# --- 9: files mode keeps directories above files -----------------------------
# A directory can never carry a score — navigation is not a selection — so ranking the folder
# listing as ONE group would hoist any file with history above every folder in it. This runs its
# own qs with HOME pointed at a fixture directory, because files mode opens at $HOME.
FHOME="$RUNTIME/home"
mkdir -p "$FHOME/Documents" "$FHOME/Downloads"
: > "$FHOME/notes.md"
: > "$FHOME/zzz.txt"
FDB="$RUNTIME/files.db"
"$REAL_SQLITE" "$FDB" "
CREATE TABLE selections (
  kind TEXT NOT NULL, key TEXT NOT NULL, label TEXT,
  hits INTEGER NOT NULL DEFAULT 0, score REAL NOT NULL DEFAULT 0,
  first_used_at INTEGER NOT NULL, last_used_at INTEGER NOT NULL,
  PRIMARY KEY (kind, key));
INSERT INTO selections VALUES ('file','$FHOME/notes.md','notes.md',9,9.0,$NOW,$NOW);"
start_qs "$FDB" "$RUNTIME/bin:$PATH" "$FHOME" || die "quickshell never loaded for the files check"
sleep 1.5
ipc_quiet launcher show files
sleep 1.2
got="$(labels file | paste -sd, -)"
# Directories first in FolderListModel's own order, then the files with notes.md hoisted over
# zzz.txt by its score. Ranked as one group, notes.md would lead the whole list.
check "files mode: a scored file never outranks a directory" \
  ".,..,Documents,Downloads,notes.md,zzz.txt" "$got"
ipc_quiet launcher hide
stop_qs

# --- 10: no sqlite3 at all ----------------------------------------------------
# The implicitly fail-open route, and the one worth testing precisely because it never reaches
# fail(): with no binary to spawn, `ready` and `loaded` stay false while `healthy` stays true, so
# nothing is ever recorded and nothing is ever ranked. PATH is cut down to a directory holding
# links to everything the shell spawns EXCEPT sqlite3.
NOSQL="$RUNTIME/bin-nosqlite"
mkdir -p "$NOSQL"
# `qs` itself has to be here too: a PATH assignment in front of a command changes the lookup for
# that command as well, so the launcher would simply never start.
for t in qs quickshell mkdir bash sh env cat; do
  src="$(command -v "$t" 2> /dev/null)" && ln -sf "$src" "$NOSQL/$t"
done
start_qs "$DB" "$NOSQL" || die "quickshell never loaded without sqlite3 — see $RUNTIME/qs.log"
sleep 2.0
ipc_quiet launcher show drun
sleep 1.0
got="$(labels app | head -5 | paste -sd, -)"
check "no sqlite3 binary: the launcher works, unranked" \
  "Aardvark,Arcade,Barnacle,Cormorant,Dromedary" "$got"
ipc_quiet launcher hide
stop_qs

# --- 11: a corrupt database ---------------------------------------------------
CORRUPT="$RUNTIME/corrupt.db"
head -c 512 /dev/urandom > "$CORRUPT"
start_qs "$CORRUPT" || die "quickshell never loaded with a corrupt database — see $RUNTIME/qs.log"
sleep 2.0
ipc_quiet launcher show drun
sleep 1.0
got="$(labels app | head -5 | paste -sd, -)"
check "corrupt database: the launcher works, unranked" \
  "Aardvark,Arcade,Barnacle,Cormorant,Dromedary" "$got"
ipc_quiet launcher hide
stop_qs

# --- 12: an unreadable table must disable the store, not empty it -------------
# The load is `sqlite3 -json`, and its output is parsed. If that parse fails and the store simply
# marks itself loaded with an empty map, `healthy` stays true and the NEXT selection of a
# previously hot row upserts `score * 0 + 1.0` — a real history flattened to a single hit,
# silently. Unreadable has to mean off.
#
# The ordering alone cannot tell the two apart (both come out unranked), so this asserts the
# score in the file afterwards. Cormorant goes in at 50 and must still be at 50.
if [ -n "$KBD_PID" ]; then
  BADJSON="$RUNTIME/bin-badjson"
  mkdir -p "$BADJSON"
  cat > "$BADJSON/sqlite3" << EOF
#!/bin/sh
# Everything works except the -json read the store loads through, which returns garbage.
case " \$* " in
  *" -json "*)
    printf '{{{not json'
    exit 0
    ;;
esac
exec "$REAL_SQLITE" "\$@"
EOF
  chmod +x "$BADJSON/sqlite3"
  before="$("$REAL_SQLITE" -readonly -noheader "$DB" \
    "SELECT round(score,1) FROM selections WHERE kind='app' AND key='zz-cormorant';")"
  start_qs "$DB" "$BADJSON:$PATH" || die "quickshell never loaded — see $RUNTIME/qs.log"
  sleep 2.0
  ipc_quiet launcher show drun
  sleep 0.8
  focus_ready
  # unranked, so alphabetical: Aardvark, Arcade, Barnacle, Cormorant, ... — walk to Cormorant
  wtype -k Down -k Down -k Down -k Return > /dev/null 2>&1
  sleep 2.0
  got="$("$REAL_SQLITE" -readonly -noheader "$DB" \
    "SELECT round(score,1) FROM selections WHERE kind='app' AND key='zz-cormorant';")"
  check "an unreadable table disables the store, it does not flatten it" "$before" "$got"
  stop_qs
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  log "$checks checks, all passed"
  exit 0
fi
die "$checks checks, $failures failed"
