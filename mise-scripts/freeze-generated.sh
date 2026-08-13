#!/usr/bin/env bash
# Apply (or audit) the skip-worktree bits listed in .stow-frozen.
#
#   mise run setup:frozen             set the bit on every listed path
#   mise run setup:frozen -- --check  report unset bits, exit 1 if any
#
# Why this exists: skip-worktree lives in .git/index, which is not committed, so
# a fresh clone of this repo has none of them and every wallpaper rotation dirties
# the tree. The manifest is the committed half; this script is what applies it.
#
# --check is the half worth running from a hook or CI: a bit that quietly went
# missing shows up as noise in `git status` rather than as an error, so nobody
# investigates — they just start ignoring the noise, which is how a real change to
# one of these files gets lost in it.
set -uo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
manifest="$repo_root/.stow-frozen"
check=0

case "${1:-}" in
  --check) check=1 ;;
  '') ;;
  *)
    echo "unknown option: $1" >&2
    exit 2
    ;;
esac

[ -r "$manifest" ] || {
  echo "no manifest at $manifest" >&2
  exit 2
}

applied=0 already=0 unset_count=0 missing=0

while IFS= read -r path; do
  case "$path" in '' | '#'*) continue ;; esac

  if ! git -C "$repo_root" ls-files --error-unmatch "$path" > /dev/null 2>&1; then
    # A path in the manifest that git does not track is a stale entry, not a
    # no-op: it means the file was untracked or renamed and the manifest was not
    # updated, so nothing is being frozen and nothing said so.
    printf '  ! %s — not tracked (stale manifest entry?)\n' "$path" >&2
    missing=$((missing + 1))
    continue
  fi

  # `git ls-files -v` tags a skip-worktree entry with an uppercase S. Do not test
  # for a lowercase letter: that is the assume-unchanged tag, a different bit, and
  # the mistake makes every frozen file look unfrozen.
  tag=$(git -C "$repo_root" ls-files -v "$path" | cut -c1)
  if [ "$tag" = "S" ]; then
    already=$((already + 1))
    continue
  fi

  if [ "$check" -eq 1 ]; then
    printf '  ✗ %s — skip-worktree NOT set\n' "$path"
    unset_count=$((unset_count + 1))
  else
    git -C "$repo_root" update-index --skip-worktree "$path" && applied=$((applied + 1))
  fi
done < "$manifest"

if [ "$check" -eq 1 ]; then
  if [ "$unset_count" -eq 0 ] && [ "$missing" -eq 0 ]; then
    printf 'frozen: %d/%d paths have skip-worktree set\n' "$already" "$already"
    exit 0
  fi
  printf '\n%d path(s) unfrozen, %d stale — run: mise run setup:frozen\n' "$unset_count" "$missing"
  exit 1
fi

printf 'frozen: %d newly set, %d already set' "$applied" "$already"
[ "$missing" -gt 0 ] && printf ', %d stale entries (see above)' "$missing"
printf '\n'
[ "$missing" -eq 0 ]
