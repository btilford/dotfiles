#!/usr/bin/env bash
# Keyboard-grab tests for the notification popup surfaces.
#
# Usage:
#   mise-scripts/notif-grab-test.sh [--shell FILE] [--keep]
#
#   --shell FILE  quickshell entry point. Default: the copy in this repo, so a run tests the
#                 working tree rather than what happens to be stowed.
#   --keep        leave the nested session running afterwards (debugging).
#
# Boots a private headless wlroots compositor (sway, WLR_BACKENDS=headless) on its own session
# bus and its own $XDG_RUNTIME_DIR, runs `qs` inside it beside a plain terminal acting as a
# keyboard SINK, and asserts where each keystroke lands.
#
# What it proves, in order:
#
#   1. A popup on screen takes no grab. Text typed with a card visible reaches the sink whole.
#   2. A prompt opened with focus mode OFF — the state a mouse click produces — receives what is
#      typed into it, and "25m" resolves through parseDelay into a snoozed row. This is the
#      regression: `entry.prompting` was absent from the window's keyboardFocus condition, so the
#      field rendered, took Qt focus, and every key went to the sink instead.
#   3. The grab is released when the prompt resolves.
#   4. Focus mode still takes the grab, still acts on keys, and still releases it. The grab owner
#      moved to `scope.grabKey`, so the path that already worked is re-proved rather than assumed.
#
# The sink is the whole method: asking the shell whether it has the keyboard only ever returns
# what the shell believes. A second client that receives the keys the shell did not is the only
# check that can fail in the direction this bug failed in.
#
# DANGER, the same one visual-capture.sh carries: a compositor started without a forced headless
# backend takes DRM master and kills the live session and every app in it. Never start one from
# here without BOTH an isolated $XDG_RUNTIME_DIR and WLR_BACKENDS=headless.
#
# A private display is NOT a private bus. quickshell runs a notification server, so a rig on the
# live session bus claims org.freedesktop.Notifications away from the running daemon. This starts
# its own dbus-daemon and refuses to run without one.
#
# Nor is a private bus a private DATABASE. NotifyStore defaults to
# ${XDG_DATA_HOME:-~/.local/share}/quickshell/notifications.db, which the nested session shares
# with the live desktop — an early version of this rig wrote real snooze rows into the user's own
# history, and they would have fired hours later. QS_NOTIFY_DB is not optional here.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="$REPO/quickshell/.config/quickshell/shell.qml"
KEEP=0
SIZE="1280x800"

log() { printf '\033[1;36m[grab]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[grab]\033[0m %s\n' "$*" >&2
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
for tool in sway qs grim wtype foot notify-send dbus-daemon; do
  command -v "$tool" > /dev/null 2>&1 || die "missing required tool: $tool"
done

WIDTH="${SIZE%x*}"
HEIGHT="${SIZE#*x}"

# Short path on purpose: a wayland socket path over 108 bytes is rejected by libwayland, and the
# scratch directories agents run under are long.
RUNTIME="$(mktemp -d /tmp/qs-grab.XXXXXX)" || die "cannot create a scratch directory"
SWAY_PID=""
QS_PID=""
DBUS_PID=""
KBD_PID=""
SINK_PID=""

cleanup() {
  [ "$KEEP" = "1" ] && {
    log "--keep: session left at XDG_RUNTIME_DIR=$RUNTIME"
    return
  }
  [ -n "$SINK_PID" ] && kill "$SINK_PID" 2> /dev/null
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

# --- private session bus -----------------------------------------------------
DBUS_ADDR="$(dbus-daemon --session --fork --print-address --print-pid=3 3> "$RUNTIME/dbus.pid")"
DBUS_PID="$(cat "$RUNTIME/dbus.pid" 2> /dev/null)"
[ -n "$DBUS_ADDR" ] || die "no private session bus — refusing to touch the live one"
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

# --- a keyboard for the seat --------------------------------------------------
# WLR_LIBINPUT_NO_DEVICES=1 leaves the seat with NO keyboard, and a seat with no keyboard never
# advertises the capability, so every wtype press is discarded — including the ones aimed at an
# exclusive layer surface. wtype's virtual keyboard lives only as long as its process, so one is
# parked here for the whole run (`-s` is the delay BETWEEN keystrokes: this presses nothing).
wtype -s 3600000 -- " " " " > /dev/null 2>&1 &
KBD_PID=$!
sleep 0.5

# --- the sink ----------------------------------------------------------------
# `cat` reads a TTY in canonical mode, so a line only arrives on Enter — type_at_sink sends one.
SINK="$RUNTIME/typed.txt"
: > "$SINK"
foot sh -c "stdbuf -o0 -i0 cat > $SINK" > "$RUNTIME/foot.log" 2>&1 &
SINK_PID=$!
sleep 2

# --- the shell under test ----------------------------------------------------
# HYPR_NOTIFY is pinned rather than inherited: config/Shell.qml reads the backend selection from
# ~/.config/hypr/shell.local.env, per-machine state the nested session shares with the live one,
# so without this the result would depend on the machine.
NOTIFY_DB="$RUNTIME/notifications.db"
export QS_NOTIFY_DB="$NOTIFY_DB"
HYPR_NOTIFY=quickshell qs -p "$SHELL_QML" > "$RUNTIME/qs.log" 2>&1 &
QS_PID=$!
sleep 7
kill -0 "$QS_PID" 2> /dev/null || die "quickshell never loaded — see $RUNTIME/qs.log"

ipc() { qs -p "$SHELL_QML" ipc call "$@" 2> /dev/null | tr -d '\n'; }
sink_text() { tr '\n' '|' < "$SINK" 2> /dev/null; }
type_at_sink() {
  wtype "$1" > /dev/null 2>&1
  wtype -k Return > /dev/null 2>&1
  sleep 1
}

# --- 1. a popup on screen takes no grab --------------------------------------
notify-send "grabrig" "resting popup"
sleep 2
check "no prompt is open at rest" "closed" "$(ipc notifications promptState)"
type_at_sink alpha
check "typing reaches the sink while a popup is up" "alpha|" "$(sink_text)"

# --- 2. a prompt opened with focus mode OFF (the mouse path) -----------------
check "focus mode is off" "false" "$(ipc notifications focused)"
check "the prompt opens" "true" "$(ipc notifications prompt 0 true)"
sleep 1
check "the prompt is open in time mode" "time 1" "$(ipc notifications promptState)"
wtype "25m" > /dev/null 2>&1
sleep 1
# Not sufficient alone: the sink is line-buffered, so an un-Entered "25m" has not flushed yet
# either way. The "grab is released" check below is what actually catches the leak.
check "the prompt swallows what is typed into it" "alpha|" "$(sink_text)"
wtype -M ctrl -k Return -m ctrl > /dev/null 2>&1
sleep 2
check "Ctrl+Enter resolves the prompt" "closed" "$(ipc notifications promptState)"
snoozed="$(ipc notifications snoozed)"
case "$snoozed" in
  *grabrig*) check "25m parsed into a snoozed row" "yes" "yes" ;;
  *) check "25m parsed into a snoozed row" "a row mentioning grabrig" "${snoozed:-<none>}" ;;
esac

# --- 3. the grab is released again -------------------------------------------
type_at_sink omega
check "the grab is released when the prompt resolves" "alpha|omega|" "$(sink_text)"

# --- 4. focus mode still holds and releases the grab -------------------------
notify-send "grabrig" "focus mode card"
sleep 2
before="$(ipc notifications count)"
ipc notifications focus > /dev/null
sleep 1
check "focus mode is on" "true" "$(ipc notifications focused)"
type_at_sink beta
check "focus mode swallows the keyboard" "alpha|omega|" "$(sink_text)"
wtype "d" > /dev/null 2>&1
sleep 1
check "d dismisses the selected card" "$((before - 1))" "$(ipc notifications count)"
ipc notifications unfocus > /dev/null
sleep 1
type_at_sink gamma
check "leaving focus mode releases the grab" "alpha|omega|gamma|" "$(sink_text)"

grim -o HEADLESS-1 "$RUNTIME/final.png" > /dev/null 2>&1

printf '\n'
if [ "$failures" -eq 0 ]; then
  log "$checks checks, all passed"
  exit 0
fi
die "$checks checks, $failures failed"
