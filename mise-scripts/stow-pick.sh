#!/usr/bin/env bash
# Pick packages with fzf and stow them.
#
#   mise run stow                 multi-select, then re-stow the chosen packages
#   mise-scripts/stow-pick.sh -D  ... unstow them instead
#   mise-scripts/stow-pick.sh -n  ... dry run (stow -n), nothing is touched
#
# The list is stow-status.sh's report, so the state is visible while choosing:
# ✓ stowed, ✗ PARTIAL, · not stowed. The preview shows that package's files with
# their individual state, which is the part `stow -n` cannot tell you — a PARTIAL
# package looks identical to a stowed one until you see which files are missing.
#
# Tab multi-selects. Nothing runs until you press Enter, and the exact stow
# command for each package is echoed before it runs.

set -uo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
status_script="$repo_root/mise-scripts/stow-status.sh"
target="${STOW_TARGET:-$HOME}"
mode=restow
stow_flags=(-R --no-folding)

while [ $# -gt 0 ]; do
  case "$1" in
    -D | --delete)
      mode=unstow
      stow_flags=(-D)
      ;;
    -n | --dry-run)
      mode=dryrun
      stow_flags=(-n -v -R --no-folding)
      ;;
    -h | --help)
      sed -n '2,6p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

command -v fzf > /dev/null 2>&1 || {
  echo "fzf is not installed — use: mise run status, then stow -R --no-folding -t ~ <pkg>" >&2
  exit 1
}
[ -x "$status_script" ] || {
  echo "not found: $status_script" >&2
  exit 1
}

# --preview re-runs the status script filtered to one package. Running the real
# thing keeps the preview honest: there is no second implementation to drift.
selected=$(
  "$status_script" | grep -E '^[✓✗·] ' | fzf \
    --multi \
    --header="Tab to select, Enter to $mode  ·  ✓ stowed  ✗ PARTIAL  · not stowed" \
    --preview="$status_script -v | awk -v p={2} '\$2==p{f=1;print;next} /^[✓✗·] /{f=0} f'" \
    --preview-window=right,60%,wrap |
    awk '{print $2}'
)

[ -n "$selected" ] || {
  echo "nothing selected"
  exit 0
}

echo
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  echo "\$ stow ${stow_flags[*]} -t $target $pkg"
  (cd "$repo_root" && stow "${stow_flags[@]}" -t "$target" "$pkg" 2>&1 | sed 's/^/    /')
done <<< "$selected"

if [ "$mode" != dryrun ]; then
  echo
  echo "re-checking:"
  "$status_script" | grep -E "^[✓✗·] ($(echo "$selected" | tr '\n' '|' | sed 's/|$//')) " || true
fi
