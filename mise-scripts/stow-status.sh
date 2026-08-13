#!/usr/bin/env bash
# Report the stow state of every package in this repo.
#
#   mise run status            summary: one line per package
#   mise run status -- -v      also list every unstowed / conflicting file
#   mise-scripts/stow-status.sh --json     machine-readable
#   mise-scripts/stow-status.sh --strict   exit non-zero if anything is PARTIAL
#
# The gap this fills: `stow -n` tells you what WOULD change for one package, and
# nothing tells you what is already half-done. A package is "partially stowed"
# when some of its files are linked and others are not — which happens after a
# package gains files and nobody re-stows, and it is silent: the shell that never
# loads a new drop-in behaves normally, it just lacks the feature.
#
# That is not hypothetical. `fish` sat with three unlinked conf.d drop-ins,
# including the one that reads local.env, and the only symptom was a feature
# quietly not existing.
#
# Per file, the target in $HOME is classified as:
#
#   linked      symlink resolving into THIS package          — correct
#   foreign     symlink into another repo (the private half) — fine, reported
#   folded      resolves into the package through a SYMLINKED PARENT DIRECTORY
#   shadowed    a real file sits where the link should be    — stow refuses here
#   missing     nothing at the target path                   — not stowed
#
# `folded` is the dangerous one, and it used to be reported as `shadowed`.
# `stow` without --no-folding links a whole DIRECTORY when every file under it
# belongs to one package, so the file at the target is not a symlink — its parent
# is. The old check asked only "is this path a symlink?", answered no, and called
# it shadowed. Acting on that label ("move the real file aside and re-stow")
# deletes the file THROUGH the directory link, i.e. out of the repo. That is not
# hypothetical either: it removed 20 tracked files from kmonad/fastfetch/gh on
# 2026-08-12 before `git checkout` brought them back.
#
# Two exclusions, neither counted, because counting them makes a correct package
# look broken:
#
#   - .stow-local-ignore, read from BOTH the repo root and the package itself.
#     stow reads the per-package file only; this script used to read only the
#     root one, so every package-level exclusion (fish_variables, gh's hosts.yml,
#     the wallust outputs) was reported as a conflict forever.
#   - anything git ignores, e.g. pi-agent's machine-provisioned models.json. It
#     is not repo content, so it cannot be "unstowed".

set -uo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
target="${STOW_TARGET:-$HOME}"

# Stow links resolve into the DEPLOY checkout, which for this repo is the primary
# worktree — run from a feature worktree, every link would otherwise look
# "foreign" because it points at ~/dotfiles rather than at this copy. `git
# worktree list` puts the main worktree first.
deploy_root=$(git -C "$repo_root" worktree list 2> /dev/null | head -1 | awk '{print $1}')
[ -n "$deploy_root" ] || deploy_root="$repo_root"
verbose=0
as_json=0
# Reporting a problem is not the same as failing. Plain `mise run status` should
# print its findings and exit 0 — a non-zero exit renders as "task failed", which
# reads like the tool broke rather than like the tree needs attention. --strict
# is there for a hook or CI that wants to gate on it.
strict=0

# Directories that are NOT stow packages: repo infrastructure, build output.
# Everything else with at least one dot-entry is treated as a package.
not_packages=" mise-scripts scripts build graphify-out .git .github .claude node_modules "

while [ $# -gt 0 ]; do
  case "$1" in
    -v | --verbose) verbose=1 ;;
    --json) as_json=1 ;;
    --strict) strict=1 ;;
    -h | --help)
      sed -n '2,7p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

# .stow-local-ignore holds one Perl regex per line. stow matches them against the
# basename and against the package-relative path; do both, or entries like
# `nushell/.config/nushell/history.txt` never match.
#
# BOTH files are read. stow itself only reads the package's own copy, so the
# per-package file is the authoritative one and the root file is this repo's
# convention for rules that apply everywhere.
ignored() {
  local rel="$1" base="$2" pkg="$3" pat file
  # stow's own control files are never stowed, and they are not listed in
  # .stow-local-ignore because stow handles them implicitly.
  case "$base" in .stow-local-ignore | .stow-global-ignore) return 0 ;; esac
  for file in "$repo_root/.stow-local-ignore" "$repo_root/$pkg/.stow-local-ignore"; do
    [ -r "$file" ] || continue
    while IFS= read -r pat; do
      case "$pat" in '' | '#'*) continue ;; esac
      if printf '%s' "$base" | grep -qE "^${pat}$" 2> /dev/null; then return 0; fi
      if printf '%s' "$rel" | grep -qE "^${pat}$" 2> /dev/null; then return 0; fi
    done < "$file"
  done
  return 1
}

# Files git ignores are machine-provisioned, not repo content — they exist in the
# working tree only because the tool that owns them writes there. One `git` call,
# not one per file: this loop runs over every file in every package.
git_ignored=$(git -C "$repo_root" ls-files --others --ignored --exclude-standard 2> /dev/null)
git_ignores() {
  case "$git_ignored" in
    *"$1"*)
      # substring match would also hit a longer path with this one as a prefix
      printf '%s\n' "$git_ignored" | grep -qxF "$1"
      ;;
    *) return 1 ;;
  esac
}

# Walk rel's ancestors looking for a symlinked directory that resolves into this
# package. Returns the deepest one, which is the directory stow folded.
folded_via() {
  local rel="$1" pkg="$2" d hit=""
  d=$(dirname "$rel")
  while [ "$d" != "." ] && [ "$d" != "/" ]; do
    if [ -L "$target/$d" ] && [ "$(readlink -f "$target/$d" 2> /dev/null)" = "$deploy_root/$pkg/$d" ]; then
      hit="$d"
    fi
    d=$(dirname "$d")
  done
  [ -n "$hit" ] && printf '%s' "$hit"
}

is_package() {
  local d="$1"
  case "$not_packages" in *" $d "*) return 1 ;; esac
  [ -d "$repo_root/$d" ] || return 1
  # A package mirrors $HOME, so it contains at least one dot-entry.
  find "$repo_root/$d" -maxdepth 1 -name '.*' -print -quit 2> /dev/null | grep -q . || return 1
  return 0
}

total_pkgs=0 full=0 partial=0 none=0 pkgs_with_shadow=0
json_rows=""

for pkg_path in "$repo_root"/*/; do
  pkg=$(basename "$pkg_path")
  is_package "$pkg" || continue
  total_pkgs=$((total_pkgs + 1))

  n_linked=0 n_missing=0 n_shadowed=0 n_foreign=0 n_folded=0 n_total=0
  missing_list="" shadow_list="" foreign_list="" folded_list=""

  while IFS= read -r f; do
    rel=${f#"$repo_root/$pkg/"}
    base=$(basename "$f")
    ignored "$rel" "$base" "$pkg" && continue
    git_ignores "$pkg/$rel" && continue
    n_total=$((n_total + 1))

    t="$target/$rel"
    if [ -L "$t" ]; then
      dest=$(readlink -f "$t" 2> /dev/null || true)
      if [ "$dest" = "$deploy_root/$pkg/$rel" ]; then
        n_linked=$((n_linked + 1))
      else
        n_foreign=$((n_foreign + 1))
        foreign_list="$foreign_list  $rel -> ${dest:-<dangling>}"$'\n'
      fi
    elif [ -e "$t" ] && [ -n "$(folded_via "$rel" "$pkg")" ]; then
      # Deployed, but through a directory link — the file IS the repo's, so it
      # must never be "moved aside". Re-stow the package with --no-folding.
      n_folded=$((n_folded + 1))
      folded_list="$folded_list  $rel  (via ~/$(folded_via "$rel" "$pkg")/)"$'\n'
    elif [ -e "$t" ]; then
      n_shadowed=$((n_shadowed + 1))
      shadow_list="$shadow_list  $rel"$'\n'
    else
      n_missing=$((n_missing + 1))
      missing_list="$missing_list  $rel"$'\n'
    fi
  done < <(find "$repo_root/$pkg" -type f -o -type l | sort)

  # A package whose every file is ignored still exists — say so rather than
  # silently dropping the row, or the package count and the rows disagree and it
  # looks like the tool lost one.
  if [ "$n_total" -eq 0 ]; then
    [ "$as_json" -eq 1 ] || printf '· %-14s %-9s  (every file excluded by .stow-local-ignore)\n' "$pkg" "ignored"
    continue
  fi

  # A folded package is deployed and working, so it is not "unstowed" — but it
  # is not right either, and the repair (re-stow with --no-folding) is the same
  # one PARTIAL asks for. FOLDED is called out separately because the wrong fix
  # for it destroys repo files.
  if [ "$n_folded" -gt 0 ]; then
    state=FOLDED
    partial=$((partial + 1))
  elif [ "$n_linked" -eq "$n_total" ]; then
    state=stowed
    full=$((full + 1))
  elif [ "$n_linked" -eq 0 ] && [ "$n_foreign" -eq 0 ]; then
    state=unstowed
    none=$((none + 1))
  else
    state=PARTIAL
    partial=$((partial + 1))
  fi
  [ "$n_shadowed" -gt 0 ] && pkgs_with_shadow=$((pkgs_with_shadow + 1))

  if [ "$as_json" -eq 1 ]; then
    json_rows="$json_rows{\"package\":\"$pkg\",\"state\":\"$state\",\"total\":$n_total,\"linked\":$n_linked,\"missing\":$n_missing,\"shadowed\":$n_shadowed,\"foreign\":$n_foreign,\"folded\":$n_folded},"
    continue
  fi

  case "$state" in
    stowed) mark="✓" ;;
    PARTIAL | FOLDED) mark="✗" ;;
    *) mark="·" ;;
  esac
  printf '%s %-14s %-9s %3d/%-3d linked' "$mark" "$pkg" "$state" "$n_linked" "$n_total"
  [ "$n_missing" -gt 0 ] && printf '  %d missing' "$n_missing"
  [ "$n_shadowed" -gt 0 ] && printf '  %d shadowed' "$n_shadowed"
  [ "$n_folded" -gt 0 ] && printf '  %d folded' "$n_folded"
  [ "$n_foreign" -gt 0 ] && printf '  %d foreign' "$n_foreign"
  printf '\n'

  if [ "$verbose" -eq 1 ]; then
    [ -n "$missing_list" ] && {
      printf '    not stowed:\n'
      printf '%s' "$missing_list" | sed 's/^/  /'
    }
    [ -n "$shadow_list" ] && {
      printf '    shadowed by a real file (stow will refuse):\n'
      printf '%s' "$shadow_list" | sed 's/^/  /'
    }
    [ -n "$folded_list" ] && {
      printf '    folded — deployed via a directory link, do NOT move these aside:\n'
      printf '%s' "$folded_list" | sed 's/^/  /'
    }
    [ -n "$foreign_list" ] && {
      printf '    owned elsewhere:\n'
      printf '%s' "$foreign_list" | sed 's/^/  /'
    }
  fi
done

if [ "$as_json" -eq 1 ]; then
  printf '{"packages":[%s]}\n' "${json_rows%,}"
  exit 0
fi

echo
[ "$deploy_root" != "$repo_root" ] && printf 'deploy checkout: %s (this copy: %s)\n' "$deploy_root" "$repo_root"
printf '%d packages: %d stowed, %d PARTIAL, %d not stowed' "$total_pkgs" "$full" "$partial" "$none"
[ "$pkgs_with_shadow" -gt 0 ] && printf ', %d with shadowed files' "$pkgs_with_shadow"
printf '\n'

if [ "$partial" -gt 0 ]; then
  cat << 'MSG'

A PARTIAL or FOLDED package needs re-stowing:

    stow -R --no-folding -t ~ <package>

FOLDED means stow linked a whole directory rather than each file. The files are
the repo's own, reached through that link: deleting one at its $HOME path deletes
it from the repo. Re-stow, never move a folded file aside.

If a re-stow reports a conflict, a genuinely foreign real file is sitting where a
link belongs. Move THAT aside and re-stow — never use --adopt, which pulls the
local file's contents INTO the repo.

If the file is written by the program that owns it (wallust output, an app's own
preferences, a tool-installed completion), it does not belong to a package at
all: add it to that package's .stow-local-ignore and .gitignore instead.
MSG
fi

# A machine legitimately does not stow every package (macOS-only, Linux-only), so
# "not stowed" is never an error. PARTIAL is the state worth acting on, and only
# --strict turns it into a non-zero exit.
[ "$strict" -eq 0 ] || [ "$partial" -eq 0 ]
