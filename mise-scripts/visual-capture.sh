#!/usr/bin/env bash
# Headless visual capture of the quickshell desktop surfaces.
#
# Usage:
#   mise-scripts/visual-capture.sh [--scene NAME]... [--out DIR] [--size WxH]
#                             [--shell FILE] [--list] [--keep] [--no-motion]
#
#   --scene NAME  capture only this surface; repeatable. Default: every scene
#                 that can run (see --list).
#   --out DIR     where captures land. Default: build/visuals/ in this repo.
#   --size WxH    headless output resolution. Default: 1920x1080.
#   --shell FILE  quickshell entry point. Default: the copy in this repo, so a
#                 capture reflects the working tree, not what is stowed.
#   --list        print the scene table and exit.
#   --keep        leave the nested session running afterwards (debugging).
#   --no-motion   stills only; skip the GIF clips.
#
# Boots a private headless wlroots compositor (sway, WLR_BACKENDS=headless) on
# its own session bus and its own $XDG_RUNTIME_DIR, runs `qs` inside it, drives
# each surface through quickshell IPC, and captures:
#
#   stills  grim -> <surface>-<timestamp>.png
#   motion  grim frame loop -> ffmpeg -> <surface>-motion-<timestamp>.gif
#
# Nothing here touches the live session: no physical display, no logged-in
# graphical session, and no seat are required, so this runs unattended over ssh
# or from a background agent. Feed the results to mise-scripts/visual-archive.sh.
#
# Why sway and not Hyprland: Hyprland 0.56 (aquamarine) cannot start headless —
# with no DRM session and no host compositor it dies with "no allocator
# available", and nesting it inside sway fails because aquamarine binds
# xdg_wm_base v6 while wlroots 0.19 offers v5. See Projects/hyprland-dotfiles/
# decisions.md in the vault.
#
# DANGER, learned the hard way: a bare `Hyprland -c ...` on a machine with a
# live session picks the DRM backend, takes DRM master, and kills the running
# session and every app in it. Never start a compositor from this harness
# without BOTH an isolated $XDG_RUNTIME_DIR and a forced headless backend
# (sway: WLR_BACKENDS=headless; Hyprland, if it ever becomes viable:
# AQ_HEADLESS_ONLY=1).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT="$REPO/build/visuals"
SHELL_QML="$REPO/quickshell/.config/quickshell/shell.qml"
SIZE="1920x1080"
KEEP=0
MOTION=1
scenes=()

# Motion tuning. grim -t ppm sustains ~60 fps on this hardware, so a plain frame
# loop is fast enough for UI animation and needs no extra tooling; the GIF is
# downscaled and frame-capped to stay phone-browsable.
FRAME_INTERVAL="0.06"
GIF_FPS=15
GIF_WIDTH=960

ALL_SCENES=(bar drawer modal popup submap keymap clipboard tmux)

log() { printf '\033[1;36m[capture]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[capture]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[capture]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,30p' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scene)
      scenes+=("${2:-}")
      shift 2
      ;;
    --out)
      OUT="${2:-}"
      shift 2
      ;;
    --size)
      SIZE="${2:-}"
      shift 2
      ;;
    --shell)
      SHELL_QML="${2:-}"
      shift 2
      ;;
    --keep)
      KEEP=1
      shift
      ;;
    --no-motion)
      MOTION=0
      shift
      ;;
    --list)
      printf '%-8s %s\n' \
        bar "top bar (always available)" \
        drawer "launcher drawer — quickshell IPC" \
        modal "session/power overlay — quickshell IPC" \
        popup "notification popups — both anchor presets, dwell + overflow" \
        submap "which-key submap hints — real maps, plus layout sizes" \
        clipboard "clipborg dialog — list, filter, tree, actions" \
        tmux "terminal surface — vhs tape if installed, else foot + grim"
      exit 0
      ;;
    -h | --help) usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ ${#scenes[@]} -eq 0 ] && scenes=("${ALL_SCENES[@]}")
[ -f "$SHELL_QML" ] || die "no quickshell entry point at $SHELL_QML"

for tool in sway qs grim ffmpeg swaymsg; do
  command -v "$tool" > /dev/null 2>&1 || die "missing required tool: $tool"
done

WIDTH="${SIZE%x*}"
HEIGHT="${SIZE#*x}"
case "$WIDTH$HEIGHT" in *[!0-9]*) die "bad --size: $SIZE (want WxH)" ;; esac

TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || die "cannot write to $OUT"

# Short path on purpose: a wayland socket path over 108 bytes is rejected by
# libwayland, and the scratch dirs agents run under are long.
RUNTIME="/tmp/qs-visuals.$$"

# Private tmux server for the terminal scene — see scene_tmux for why this must
# never be the default socket. The config comes from the working tree, matching
# --shell: a capture reflects what is in the repo, not what happens to be stowed.
TMUX_SOCKET="qs-visuals-$$"
TMUX_CONF="$REPO/tmux/.tmux.conf"

SWAY_PID=""
QS_PID=""
DBUS_PID=""
KBD_PID=""

cleanup() {
  [ "$KEEP" = "1" ] && {
    log "--keep: session left at XDG_RUNTIME_DIR=$RUNTIME WAYLAND_DISPLAY=$WL"
    return
  }
  tmux -L "$TMUX_SOCKET" kill-server 2> /dev/null
  [ -n "$KBD_PID" ] && kill "$KBD_PID" 2> /dev/null
  [ -n "$QS_PID" ] && kill "$QS_PID" 2> /dev/null
  [ -n "$SWAY_PID" ] && kill "$SWAY_PID" 2> /dev/null
  [ -n "$DBUS_PID" ] && kill "$DBUS_PID" 2> /dev/null
  sleep 0.3
  rm -rf "$RUNTIME"
}
trap cleanup EXIT INT TERM

rm -rf "$RUNTIME"
mkdir -p "$RUNTIME" || die "cannot create $RUNTIME"
chmod 700 "$RUNTIME"

# --- private session bus -----------------------------------------------------
# Synthetic notifications must reach the shell under test, never the real
# desktop's notification daemon, so the nested session gets its own bus.
if command -v dbus-daemon > /dev/null 2>&1; then
  DBUS_ADDR="$(dbus-daemon --session --fork --print-address --print-pid=3 3> "$RUNTIME/dbus.pid")"
  DBUS_PID="$(cat "$RUNTIME/dbus.pid" 2> /dev/null)"
  export DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR"
else
  warn "dbus-daemon not found — the popup scene cannot fire synthetic notifications"
fi

# --- headless compositor -----------------------------------------------------
cat > "$RUNTIME/sway.conf" << EOF
# Generated by mise-scripts/visual-capture.sh — the resolution comes from --size.
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
# WLR_LIBINPUT_NO_DEVICES=1 is what keeps this session off the real input devices,
# and it leaves the seat with NO keyboard at all. A seat with no keyboard never
# advertises the keyboard capability, so no client ever binds wl_keyboard and no
# surface is ever told it has keyboard focus — every `wtype` press is discarded,
# silently, including the ones aimed at an exclusive layer surface.
#
# wtype's virtual keyboard lives only as long as the wtype process, so one is
# parked here for the whole run: `-s` is the delay BETWEEN keystrokes, so this
# presses nothing for the next hour and holds the capability open. Started before
# quickshell so the capability exists before any surface takes focus.
if command -v wtype > /dev/null 2>&1; then
  wtype -s 3600000 -- " " " " > /dev/null 2>&1 &
  KBD_PID=$!
  sleep 0.3
else
  warn "wtype not installed — keyboard scenes will be skipped"
fi

# --- the shell under test ----------------------------------------------------
# HYPR_NOTIFY is pinned rather than inherited. config/Shell.qml reads the backend
# selection from ~/.config/hypr/shell.local.env — per-machine state that is not
# stowed — and the nested session shares $HOME with the live one. Without this
# the popup scene would capture on a host opted in to quickshell and silently
# skip on one left at the swaync default, i.e. the harness output would depend on
# the machine. The env wins over the file (see the comment in Shell.qml), and
# nothing outside this script exports it, so the live desktop is unaffected.
#
# QS_NOTIFY_CONFIG points the notification placement/motion config at a file this
# script owns, for the same reason: the shell reads
# ~/.config/quickshell/notifications.json, which is the user's live preference.
# Capturing has to be able to switch anchor presets without editing it.
NOTIFY_CONFIG="$RUNTIME/notifications.json"
notify_cfg() {
  printf '%s\n' "$1" > "$NOTIFY_CONFIG"
}
notify_preset() {
  notify_cfg "$(printf '{ "preset": "%s" }' "$1")"
}
notify_preset right-center

# QS_NOTIFY_DB likewise: the notification history is a real database under
# ~/.local/share, and a capture run firing synthetic "Build finished" notifications
# has no business writing rows into the user's own history.
NOTIFY_DB="$RUNTIME/notifications.db"

# QS_NOTIFY_RULES for the same reason again: the popup-rules scene writes a rules file, and
# it must be this session's, never ~/.config/quickshell/notifications.lua.
NOTIFY_RULES="$RUNTIME/rules.lua"
: > "$NOTIFY_RULES"

# QS_BINDS_CMD feeds the which-key overlay REAL keybindings. Keymap.qml normally
# shells out to `hyprctl binds -j`, and there is no Hyprland in this session, so
# without it the submap scene can only ever photograph synthetic entries — which is
# fine for exercising the layout and useless as documentation. The fixture is a
# committed dump of this repo's own binds; regenerate it with
# mise-scripts/visuals/fixtures/gen-binds.sh from a live session.
BINDS_FIXTURE="$REPO/mise-scripts/visuals/fixtures/binds.json"

# CLIPBORG_CONFIG scopes the clipboard dialog to a throwaway database. Without it
# the dialog opens the user's REAL clipboard history — every password-manager copy
# and every token pasted between terminals — and photographs it. Exported for the
# whole session, not just the scene, so no ordering mistake can leave it unset.
CLIPBORG_CONFIG="$RUNTIME/clipborg.toml"
cat > "$CLIPBORG_CONFIG" << CLIPBORG_EOF
[storage]
db_path = "$RUNTIME/clipborg.sqlite3"
image_dir = "$RUNTIME/clipborg-images"

[capture]
# Nothing should be ingested from the nested seat; the scene seeds explicitly.
text = false
images = false
files = false
CLIPBORG_EOF
export CLIPBORG_CONFIG
export QML_IMPORT_PATH="${CLIPBORG_QML_PATH:-$HOME/Projects/public/clipborg/examples/quickshell}${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"

HYPR_NOTIFY=quickshell QS_NOTIFY_CONFIG="$NOTIFY_CONFIG" QS_NOTIFY_DB="$NOTIFY_DB" \
  QS_NOTIFY_RULES="$NOTIFY_RULES" \
  QS_BINDS_CMD="cat '$BINDS_FIXTURE'" \
  qs -p "$SHELL_QML" > "$RUNTIME/qs.log" 2>&1 &
QS_PID=$!

ready=0
for _ in $(seq 1 100); do
  grep -q "Configuration Loaded" "$RUNTIME/qs.log" 2> /dev/null && {
    ready=1
    break
  }
  kill -0 "$QS_PID" 2> /dev/null || break
  sleep 0.2
done
[ "$ready" = "1" ] || die "quickshell never loaded — see $RUNTIME/qs.log"
sleep 1.5 # first frame + entry animations of whatever is visible at startup
log "quickshell up ($SHELL_QML)"

# `--` is load-bearing: `show` is also a name of an `ipc` subcommand, so without
# it CLI11 swallows `call <target> show` and prints the handler listing instead
# of calling anything. --pid pins the call to the instance this script started.
ipc() { qs ipc --pid "$QS_PID" call -- "$@" > /dev/null 2>&1; }
settle() { sleep "${1:-0.8}"; }

captured=0

# The pill docks in the bar — 40px of a 1080p frame, so a full-frame still of it is
# almost entirely empty desktop. This crops to the bar strip so it is readable at the
# size a README renders it.
still_bar() {
  local name="$1" dest="$OUT/$1-$TS.png"
  if grim - 2> /dev/null | magick - -crop 1920x60+0+0 +repage "$dest" 2> /dev/null; then
    command -v oxipng > /dev/null 2>&1 && oxipng -q -o2 --strip safe "$dest" > /dev/null 2>&1
    log "still  $name -> $dest"
    captured=$((captured + 1))
  else
    warn "still $name failed"
  fi
}

still() {
  local name="$1" dest="$OUT/$1-$TS.png"
  if grim "$dest" 2> /dev/null; then
    command -v oxipng > /dev/null 2>&1 && oxipng -q -o2 --strip safe "$dest" > /dev/null 2>&1
    log "still  $name -> $dest"
    captured=$((captured + 1))
  else
    warn "still $name failed"
  fi
}

# clip <name> <seconds> <trigger command...>
# Records the screen while the trigger runs, then encodes a GIF. Recording
# starts first so the frame before the animation is in the clip.
clip() {
  local name="$1" secs="$2"
  shift 2
  [ "$MOTION" = "1" ] || return 0
  local frames="$RUNTIME/frames-$name" dest="$OUT/$name-$TS.gif"
  mkdir -p "$frames"

  (
    i=0
    deadline=$(($(date +%s%N) + $(awk -v s="$secs" 'BEGIN{printf "%d", s*1e9}')))
    while [ "$(date +%s%N)" -lt "$deadline" ]; do
      grim -t ppm "$frames/$(printf '%05d' "$i").ppm" 2> /dev/null || break
      i=$((i + 1))
      sleep "$FRAME_INTERVAL"
    done
  ) &
  local rec=$!

  sleep 0.2
  "$@"
  wait "$rec"

  local n
  n="$(find "$frames" -name '*.ppm' | wc -l)"
  if [ "$n" -lt 2 ]; then
    warn "clip $name captured $n frame(s) — skipped"
    rm -rf "$frames"
    return 0
  fi

  if ffmpeg -y -loglevel error -framerate "$GIF_FPS" -i "$frames/%05d.ppm" \
    -vf "fps=$GIF_FPS,scale=$GIF_WIDTH:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
    -loop 0 "$dest" 2> "$RUNTIME/ffmpeg-$name.log"; then
    log "motion $name -> $dest ($n frames, $(du -h "$dest" | cut -f1))"
    captured=$((captured + 1))
  else
    warn "clip $name: ffmpeg failed — see $RUNTIME/ffmpeg-$name.log"
  fi
  rm -rf "$frames"
}

# --- scenes ------------------------------------------------------------------

scene_bar() {
  settle
  still bar
}

scene_drawer() {
  ipc launcher show drun
  settle
  still drawer
  ipc launcher hide
  settle 0.6
  clip drawer-motion 2.2 ipc launcher show drun
  ipc launcher hide
  settle 0.6
}

scene_modal() {
  ipc session show
  settle
  still modal
  ipc session hide
  settle 0.6
  clip modal-motion 2.2 ipc session show
  ipc session hide
  settle 0.6
}

# Fires a synthetic notification on the nested bus. Until the notification
# server (epic story 1) exists nothing owns org.freedesktop.Notifications there,
# so the scene reports why it skipped instead of archiving an empty desktop.
scene_popup() {
  command -v notify-send > /dev/null 2>&1 || {
    warn "popup: notify-send not installed — skipped"
    return 0
  }
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || {
    warn "popup: no private session bus — skipped"
    return 0
  }
  # --acquired only: without it the list includes activatable names from the
  # system's service files, which would make this check always pass.
  if command -v busctl > /dev/null 2>&1 &&
    ! busctl --user list --acquired --no-legend 2> /dev/null | grep -q 'org.freedesktop.Notifications'; then
    warn "popup: nothing owns org.freedesktop.Notifications in the nested session — skipped (needs the notification server)"
    return 0
  fi
  # Both anchor presets are captured on purpose: choosing between right-center and
  # bottom-center is the point of the placement story, and it is meant to be settled
  # from real captures rather than taste. The preset is switched through the config
  # file the shell hot-reloads, which also exercises that reload path.
  popup_anchor right-center popup
  popup_dwell
  popup_overflow
  popup_countdown
  popup_collapse
  popup_keyboard
  popup_rules
  popup_drawer
  popup_anchor bottom-center popup-bottom
  notify_preset right-center
  settle 0.8
}

# The remaining-time indicator: a long-running card caught partway through its
# dwell, so the bar under it is visibly part-drained rather than full or empty.
popup_countdown() {
  notify-send -a "visual-capture" -t 9000 "Syncing vault" "1 of 4 repositories"
  settle 2.5
  still popup-countdown
  ipc notifications dismissAll
  settle 0.5
}

# Shrink-to-icon: a sticky critical folds into a pill instead of owning the
# screen forever. criticalCollapseMs is cut to ~1s so the fold fits in a clip —
# the shipped default is 15s, which no reviewer is going to sit through.
popup_collapse() {
  notify_cfg '{ "preset": "right-center", "timing": { "criticalCollapseMs": 1200 } }'
  settle 0.8
  clip popup-collapse-motion 4.0 \
    notify-send -a "visual-capture" -u critical "Disk almost full" "/ has 2% free"
  ipc notifications dismissAll
  settle 0.5
  # Fired outside the clip on purpose: clip() is a no-op under --no-motion, so a still that
  # depended on the clip's notification would capture an empty desktop in that mode.
  notify-send -a "visual-capture" -u critical "Disk almost full" "/ has 2% free"
  # 16s, not 2.2s. The 1200ms override above is written to QS_NOTIFY_CONFIG and does
  # NOT take effect — verified by probing a --keep session: with `critical: 3000` the
  # card still outlived 5s, and with `preset: bottom-center` the stack stayed at
  # right-center, so the whole file is ignored even though QS_NOTIFY_CONFIG is set
  # correctly in the qs environment. Until that is fixed, wait past the BUILT-IN
  # criticalCollapseMs (15000), which does fire — the pill docks in the bar as designed.
  settle 16.5
  still popup-collapsed
  still_bar popup-collapsed-pill

  # No hover still: this session's only pointer would be `swaymsg seat <name> cursor
  # set`, and that call does not take here — get_seats comes back empty (the seat has
  # no devices under WLR_LIBINPUT_NO_DEVICES=1) and the command fails against a
  # literal seat0 too. Tried three ways; left out rather than shipped as a path that
  # never fires. A hover capture needs a working pointer in the rig first.
  ipc notifications dismissAll
  notify_preset right-center
  settle 0.8
}

# Keyboard control: the stack takes the keyboard on an explicit call, the selection
# moves with j/k, and the legend under the stack says what the keys do. Keys are typed
# into the nested compositor with wtype — the whole point of the story is that these
# keystrokes reach a layer surface, so pressing them for real is the only honest test.
popup_keyboard() {
  command -v wtype > /dev/null 2>&1 || {
    warn "popup-keyboard: wtype not installed — skipped"
    return 0
  }
  local i
  for i in 1 2 3 4 5 6 7; do
    notify-send -a "visual-capture" "Job $i finished" "worker-$i reported in"
  done
  settle 1.2
  ipc notifications focus
  settle 0.8
  still popup-keyboard-focus # newest card selected, legend showing 1/7
  wtype -k j
  wtype -k j
  settle 0.6
  still popup-keyboard-select # selection two down, countdown bars frozen
  clip popup-keyboard-motion 4.5 \
    sh -c 'sleep 0.3; wtype -k j; sleep 0.6; wtype -k j; sleep 0.6; wtype -k d; sleep 0.8; wtype -k Escape'
  ipc notifications unfocus
  ipc notifications dismissAll
  settle 0.5
}

# Lua rules: three notifications, one config. One is routed to the opposite anchor, one is
# made sticky, one is silenced to drawer-only — so the still shows a rule file deciding
# placement and lifetime per notification rather than one setting applying to all of them.
popup_rules() {
  command -v lua > /dev/null 2>&1 || command -v luajit > /dev/null 2>&1 || {
    warn "popup-rules: no lua interpreter — skipped"
    return 0
  }
  cat > "$RUNTIME/rules.lua" << 'LUA'
return {
  { name = "route deploys top-left",
    when = function(n) return n.category == "deploy" end,
    set  = { anchorH = "left", anchorV = "top" } },
  { name = "alerts stay until dismissed",
    when = function(n) return n.appName == "alertmanager" end,
    set  = { durationMs = 0 } },
  { name = "build noise is drawer-only",
    when = function(n) return n.appName == "cargo" end,
    set  = { durationMs = -1 } },
}
LUA
  settle 0.8 # FileView.watchChanges + the engine restart
  notify-send -a "alertmanager" -u critical "Disk pressure" "node-02 at 91%"
  notify-send -a "visual-capture" -c deploy "Deploy complete" "staging is on 1.4.2"
  notify-send -a "cargo" "Compiling 214 crates" "this one never pops"
  settle 1.6
  still popup-rules
  ipc notifications dismissAll
  # Back to no rules: later scenes must not inherit this file's routing.
  : > "$RUNTIME/rules.lua"
  settle 1.0
}

# The history drawer, in both shapes it ships with. Notifications are fired and left to
# expire first: the drawer's whole claim is that a popup you already lost is still there.
popup_drawer() {
  local i
  for i in 1 2 3; do
    notify-send -a "cargo" -t 1200 "Compiled crate $i" "target/release"
  done
  notify-send -a "alertmanager" -u critical -t 1200 "Disk pressure" "node-02 at 91%"
  notify-send -a "ci" -t 1200 "Build failed" "3 tests red on main"
  settle 2.5 # let them all expire off screen — the drawer is what remains

  ipc notifications drawerShow
  settle 1.2
  still popup-drawer
  ipc notifications drawerHide
  settle 0.6

  notify_cfg '{ "preset": "right-center", "drawer": { "mode": "modal" } }'
  settle 0.8
  ipc notifications drawerShow
  settle 1.2
  still popup-drawer-modal
  ipc notifications drawerHide
  notify_preset right-center
  settle 0.8
}

# popup_anchor <preset> <capture name>: arrival motion + a still at one anchor.
popup_anchor() {
  local preset="$1" name="$2"
  notify_preset "$preset"
  settle 0.8 # FileView.watchChanges reload + the stack re-anchoring
  clip "$name-motion" 3.0 notify-send -a "visual-capture" "Build finished" "3 packages rebuilt in 41s"
  # The clip's notification is still on screen and has not expired. Without this
  # the still catches both it and the one fired below, stacked — two identical
  # cards, which reads as a bug in the shell rather than a duplicate in the rig.
  ipc notifications dismissAll
  settle 0.8
  notify-send -a "visual-capture" "Build finished" "3 packages rebuilt in 41s"
  settle 1.0
  still "$name"
  ipc notifications dismissAll
  settle 0.5
}

# The signature motion: on timeout the card flies up into the bar's bell widget
# instead of fading out. -t is short so the whole dwell fits in one clip.
popup_dwell() {
  clip popup-dwell-motion 4.0 notify-send -a "visual-capture" -t 1200 \
    "Deploy complete" "staging is on 1.4.2"
  ipc notifications dismissAll
  settle 0.5
}

# More notifications than placement.maxVisible: the stack caps and the rest queue
# behind a "+N more" line instead of covering the screen.
popup_overflow() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    notify-send -a "visual-capture" "Job $i finished" "worker-$i reported in"
  done
  settle 1.2
  still popup-overflow
  ipc notifications dismissAll
  settle 0.5
}

# Terminal surface. vhs renders a scripted GIF from a committed tape; without it
# the harness falls back to a real terminal inside the nested compositor, which
# still gives the tmux status line a visual record.
#
# Both paths run tmux on a PRIVATE server (-L "$TMUX_SOCKET") loaded from the
# working tree's .tmux.conf, never the default socket. Attaching to the user's
# live tmux server would (a) put whatever they are actually working on into a
# capture destined for the vault, and (b) let this harness kill sessions out
# from under them — a background agent lives in that server.
# The overlay is driven by real Hyprland submap state, which sway cannot produce,
# so it is fed through the preview IPC instead — see the header of SubmapHints.qml.
# Three entry counts because the layout is width-driven: the interesting cases are a
# map too sparse to fill one row, one that fills it, and one that has to wrap.
scene_submap() {
  # Real maps first — these are the ones worth showing anyone. previewMap sets only
  # the submap name, so the entries come from the binds fixture rather than the
  # synthetic generator: real chords, real descriptions, real nested-group markers.
  for map in window-cmd open-cmd; do
    ipc submapHints previewMap "$map"
    settle
    still "submap-$map"
  done

  # Then the synthetic sizes, which exist to exercise the width-driven layout: too
  # sparse to fill a row, exactly one row, and enough to wrap. Deliberately
  # over-long labels, so these show the elide rather than a tidy best case.
  for n in 4 12 28; do
    ipc submapHints preview resize "$n"
    settle
    still "submap-$n"
  done
  ipc submapHints hide
  settle 0.6
}

# The clipboard dialog is NOT ours: `import Clipborg` resolves to the module shipped
# by the clipborg repo (examples/quickshell/Clipborg), and the wrapper in this repo is
# host glue only. So this scene needs three things the other scenes do not:
#
#   1. the module on QML_IMPORT_PATH — CLIPBORG_QML_PATH points at the clone
#   2. a clipborg daemon on THIS session's socket, because the dialog is a client
#   3. entries to show, since a filter and a tree over an empty list are blank boxes
#
# All three are scoped to the rig. CLIPBORG_CONFIG points at a config written here
# whose db_path is under $RUNTIME, so the user's real clipboard history is never
# opened, never queried, and never photographed. That history is the single most
# sensitive thing on this machine — it is every password manager copy, every token
# pasted between terminals — and it must not be one env var away from a capture
# destined for a notes vault.
#
# The seeded entries are therefore FABRICATED, and the README says so. They are
# chosen to exercise the views rather than to look plausible: several apps so the
# tree has more than one node, a URL and a code block so the action list is
# non-trivial, and enough rows that filtering visibly removes some.
CLIPBORG_QML="${CLIPBORG_QML_PATH:-$HOME/Projects/public/clipborg/examples/quickshell}"

# --source sets the attributing app, which is what the tree view groups by. Without
# a spread of sources the tree is one node and shows nothing the flat list does not.
seed_one() {
  printf '%s' "$2" | clipborg insert --source "$1" > /dev/null 2>&1
  # `--source` records HOW an entry arrived (cli, clipboard, editor hook); the tree
  # groups by app_class, which the daemon normally fills from the focused window at
  # capture time. There is no focused window here and no CLI flag for it, so the
  # attributing app is stamped directly into the throwaway database. Synthetic data
  # in a rig-scoped file — never the real history, which this scene never opens.
  sqlite3 "$RUNTIME/clipborg.sqlite3" \
    "UPDATE entries SET app_class = '$1' WHERE app_class = '' ;" 2> /dev/null || true
}

seed_clipborg() {
  # Deliberately synthetic. Nothing here is real clipboard content.
  seed_one ghostty 'https://quickshell.org/docs/'
  seed_one ghostty 'git-spice branch submit --fill --no-prompt'
  seed_one ghostty 'stow --no-folding -R quickshell'
  seed_one nvim 'SELECT path, title FROM notes WHERE type = ?'
  seed_one nvim 'local ok, err = pcall(require, "lua.colors")'
  seed_one brave 'https://github.com/btilford/dotfiles'
  seed_one brave 'https://wiki.archlinux.org/title/Hyprland'
  seed_one obsidian 'the quick brown fox jumps over the lazy dog'
}

# The fullscreen cheatsheet, as distinct from the transient which-key strip. Same
# binds fixture feeds it (QS_BINDS_CMD), so the tree sidebar and the entries are the
# repo's real keybindings rather than anything invented.
scene_keymap() {
  ipc keymap show
  settle 1.0
  still keymap-overlay

  # Live search, typed into the box the way a person reaches it: "/" from NAV mode.
  if command -v wtype > /dev/null 2>&1; then
    wtype -k slash
    settle 0.4
    wtype 'window'
    settle 0.8
    still keymap-search
    wtype -k Escape
    settle 0.3
  fi

  ipc keymap hide
  settle 0.6
}

scene_clipboard() {
  command -v clipborg > /dev/null 2>&1 || {
    warn "clipboard: clipborg not installed — skipped"
    return
  }
  [ -d "$CLIPBORG_QML/Clipborg" ] || {
    warn "clipboard: no Clipborg QML module at $CLIPBORG_QML — set CLIPBORG_QML_PATH; skipped"
    return
  }
  command -v wtype > /dev/null 2>&1 || {
    warn "clipboard: wtype not installed — skipped"
    return
  }

  # The dialog is a CLIENT: it queries the daemon over
  # $XDG_RUNTIME_DIR/clipborg.sock, it does not read the database itself. With no
  # daemon on this session's socket the dialog opens perfectly and reports
  # "0 results" — which looks like a seeding bug and is not one. The nested session
  # has its own XDG_RUNTIME_DIR, so this socket cannot collide with the real one.
  clipborg daemon > "$RUNTIME/clipborg.log" 2>&1 &
  CLIPBORG_PID=$!
  for _ in $(seq 1 40); do
    [ -S "$RUNTIME/clipborg.sock" ] && break
    sleep 0.1
  done
  [ -S "$RUNTIME/clipborg.sock" ] || {
    warn "clipboard: daemon never bound a socket — skipped"
    kill "$CLIPBORG_PID" 2> /dev/null
    return
  }

  seed_clipborg
  settle 0.8

  ipc clipboard toggle
  settle 1.0
  still clipborg-list

  # Filter. Typed, not injected: the search field is the real entry point and a
  # capture of it should go through the same path a person does.
  wtype 'http'
  settle 0.8
  still clipborg-filter

  # Clear the filter before the tree, or the tree is a tree of one match.
  wtype -k BackSpace -k BackSpace -k BackSpace -k BackSpace
  settle 0.6

  # Ctrl+T groups by app; Ctrl+A opens the action list for the selected entry.
  wtype -M ctrl -k t -m ctrl
  settle 0.8
  still clipborg-tree

  wtype -M ctrl -k t -m ctrl
  settle 0.5
  wtype -M ctrl -k a -m ctrl
  settle 0.8
  still clipborg-actions

  wtype -k Escape
  settle 0.4
  ipc clipboard close
  settle 0.6

  kill "$CLIPBORG_PID" 2> /dev/null
}

scene_tmux() {
  if command -v vhs > /dev/null 2>&1; then
    local dest="$OUT/tmux-motion-$TS.gif"
    if (cd "$OUT" && VHS_NO_SANDBOX=1 \
      QS_VISUALS_TMUX_SOCKET="$TMUX_SOCKET" QS_VISUALS_TMUX_CONF="$TMUX_CONF" \
      vhs "$REPO/mise-scripts/visuals/tmux.tape" -o "$dest" > "$RUNTIME/vhs.log" 2>&1); then
      log "motion tmux -> $dest"
      captured=$((captured + 1))
    else
      warn "tmux: vhs failed — see $RUNTIME/vhs.log"
    fi
  fi

  local term=""
  for t in foot kitty wezterm alacritty; do
    command -v "$t" > /dev/null 2>&1 && {
      term="$t"
      break
    }
  done
  [ -n "$term" ] || {
    warn "tmux: no terminal emulator installed — skipped"
    return 0
  }
  command -v tmux > /dev/null 2>&1 || {
    warn "tmux: tmux not installed — skipped"
    return 0
  }

  "$term" -e tmux -L "$TMUX_SOCKET" -f "$TMUX_CONF" new-session -A -s visuals \
    > /dev/null 2>&1 &
  local termpid=$!
  settle 3.0
  still tmux
  kill "$termpid" 2> /dev/null
  tmux -L "$TMUX_SOCKET" kill-server 2> /dev/null
  settle 0.5
}

for scene in "${scenes[@]}"; do
  case " ${ALL_SCENES[*]} " in
    *" $scene "*) ;;
    *)
      warn "unknown scene: $scene (try --list)"
      continue
      ;;
  esac
  log "scene: $scene"
  "scene_$scene"
done

[ "$captured" -eq 0 ] && die "nothing captured"
log "$captured capture(s) in $OUT"
log "archive them with: mise run screenshots:archive -- --ref <ref> --note '<what changed>'"
