#!/bin/sh
# Take a screenshot, then copy+save it or open it in an annotator.
#
# Bound from the Print family and the `shot-cmd` submap in lua/keybindings.lua.
#
# Capture is grimblast (grim + slurp), not flameshot. On this machine's four mixed-scale
# outputs, flameshot 14 captures through the portal and came back with ONE monitor
# (1440x2560 of an 8160x4770 desktop, verified 2026-10-26). slurp selects across every
# output at the right scale, so capture stays here and only annotation is pluggable.
#
# The annotator is satty (flameshot-style arrows, text, blur, highlight, crop), with
# swappy as the fallback when satty is absent. `flameshot` remains as its own action
# for comparison — it does its own capture.
#
#   Screenshot.sh <target> <action> [delay-seconds]
#     target: area | active | output | screen
#     action: copy      copy to clipboard and save to the screenshot dir
#             edit      open the capture in satty (Enter = copy + save + close)
#             flameshot flameshot gui (ignores target)
#   Screenshot.sh last          re-open the newest saved screenshot in the annotator

set -u

usage() {
  echo "usage: Screenshot.sh <area|active|output|screen> <copy|edit|flameshot> [delay]" >&2
  echo "       Screenshot.sh last" >&2
}

pictures=$(xdg-user-dir PICTURES 2> /dev/null) || pictures=$HOME/Pictures
dir=${XDG_SCREENSHOTS_DIR:-$pictures/Screenshots}
mkdir -p "$dir"

notify() {
  notify-send -a Screenshot -i camera-photo "$@" 2> /dev/null || true
}

# satty reads the chrono format itself, so the name is stamped at SAVE time, not at
# capture time — a long annotation session does not reuse a stale stamp.
annotate() {
  if command -v satty > /dev/null 2>&1; then
    satty --filename "$1" \
      --output-filename "$dir/%Y-%m-%d_%H-%M-%S.png" \
      --copy-command wl-copy \
      --actions-on-enter save-to-clipboard,save-to-file,exit \
      --initial-tool arrow
  elif command -v swappy > /dev/null 2>&1; then
    swappy -f "$1" -o "$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
  else
    notify "No annotator" "Install satty (or swappy) to edit screenshots."
    return 1
  fi
}

if [ "${1:-}" = last ]; then
  newest=$(find "$dir" -maxdepth 1 -name '*.png' -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)
  [ -n "$newest" ] || {
    notify "No screenshots" "Nothing in $dir yet."
    exit 1
  }
  annotate "$newest"
  exit
fi

[ $# -ge 2 ] || {
  usage
  exit 2
}
target=$1 action=$2 delay=${3:-0}

case $target in
  area | active | output | screen) ;;
  *)
    usage
    exit 2
    ;;
esac

# --freeze stills the screen while slurp is up, so a tooltip or menu survives the drag.
# grimblast implements it with hyprpicker and fails outright without it.
freeze=
if [ "$target" = area ] && command -v hyprpicker > /dev/null 2>&1; then
  freeze=--freeze
fi

case $action in
  copy)
    sleep "$delay"
    # Unquoted $freeze on purpose: empty must vanish, not become a "" argument.
    # shellcheck disable=SC2086
    exec grimblast --notify $freeze copysave "$target" "$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
    ;;
  edit)
    sleep "$delay"
    tmp=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/screenshot.XXXXXX.png") || exit 1
    trap 'rm -f "$tmp"' EXIT
    # A cancelled slurp (Escape) exits non-zero and writes nothing — not an error.
    # shellcheck disable=SC2086
    grimblast $freeze save "$target" "$tmp" > /dev/null 2>&1 || exit 0
    [ -s "$tmp" ] || exit 0
    annotate "$tmp"
    ;;
  flameshot)
    exec flameshot gui --delay "$((delay * 1000))" --path "$dir"
    ;;
  *)
    usage
    exit 2
    ;;
esac
