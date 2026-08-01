#!/usr/bin/env bash
# Generate ~/.config/dotfiles/local.env with placeholder values.
#
#   mise-scripts/gen-local-env.sh              write ~/.config/dotfiles/local.env (mode 600)
#   mise-scripts/gen-local-env.sh --print      write to stdout instead
#   mise-scripts/gen-local-env.sh --out PATH   write somewhere else
#   mise-scripts/gen-local-env.sh --force      overwrite an existing file
#
# Runs from a plain checkout, before anything is stowed — which is the difference
# from `dotfiles-local-env --template`. That one copies the example out of
# ~/.local/share/dotfiles, so it only works once the `commands` package is stowed,
# and stowing is the step that needs these values.
#
# The variable list comes from the manifest (required-env), not from the example
# file, so a var added to the manifest cannot be missing here. Placeholder values
# are lifted from the example when it has one, so they stay realistic in shape;
# anything the example does not cover is emitted empty with its manifest note as
# the comment. A mismatch between the two files is reported on stderr.

set -uo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
manifest="$repo_root/commands/.local/share/dotfiles/required-env"
example="$repo_root/commands/.local/share/dotfiles/local.example.env"
out="${DOTFILES_LOCAL_ENV:-$HOME/.config/dotfiles/local.env}"
print=0
force=0

die() {
  echo "[gen-local-env] $1" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --print) print=1 ;;
    --force) force=1 ;;
    --out)
      shift
      [ $# -gt 0 ] || die "--out needs a path"
      out=$1
      ;;
    -h | --help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ -r "$manifest" ] || die "manifest not found: $manifest"

# Placeholder for VAR, taken from the example file. Values here are already
# fictional (example.com, zeroed UUID); the example is tracked, so nothing real
# can be in it.
placeholder_of() {
  [ -r "$example" ] || return 1
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=(.*)$/\1/p" "$example" | head -1
}

manifest_vars() {
  while IFS=$'\t' read -r var _rest; do
    case "$var" in '' | '#'*) continue ;; esac
    echo "$var"
  done < "$manifest"
}

# Drift report: the manifest is authoritative, so an example-only var is a
# leftover and a manifest-only var is a placeholder someone forgot to add.
report_drift() {
  [ -r "$example" ] || return 0
  local example_vars manifest_only example_only
  example_vars=$(sed -nE 's/^[[:space:]]*([A-Z_][A-Z0-9_]*)=.*$/\1/p' "$example" | sort -u)
  manifest_only=$(comm -23 <(manifest_vars | sort -u) <(echo "$example_vars"))
  example_only=$(comm -13 <(manifest_vars | sort -u) <(echo "$example_vars"))
  [ -n "$manifest_only" ] && printf '[gen-local-env] in manifest, missing from %s: %s\n' \
    "${example#"$repo_root"/}" "$(echo "$manifest_only" | tr '\n' ' ')" >&2
  [ -n "$example_only" ] && printf '[gen-local-env] in example, missing from the manifest: %s\n' \
    "$(echo "$example_only" | tr '\n' ' ')" >&2
  return 0
}

generate() {
  cat << 'EOF'
# Machine-local values — generated placeholders, fill these in.
#
# Plain KEY=VALUE. No quotes, no shell expansion: systemd's environment.d reads
# this same file verbatim, and it supports neither.
#
# chmod 600 — NEOVIM_API_KEY is a real credential.
#
# Never commit it. `local.env`, `*.local` and `[0-9][0-9]-local*` are reserved in
# .gitignore and .stow-local-ignore, and mise-scripts/no-local-values.sh fails a commit
# whose content contains any value from this file.
#
# Wire it up outside a shell too (nvim from a desktop entry, systemd user
# services, the Wayland session):
#
#   ln -s ~/.config/dotfiles/local.env ~/.config/environment.d/50-local.conf
#
# Then: dotfiles-local-env --check
EOF

  while IFS=$'\t' read -r var req consumer note; do
    case "$var" in '' | '#'*) continue ;; esac
    local value
    value=$(placeholder_of "$var" || true)
    printf '\n# %s — %s\n' "${req:-optional}" "${consumer:-unknown consumer}"
    [ -n "${note:-}" ] && printf '#   %s\n' "$note"
    printf '%s=%s\n' "$var" "$value"
  done < "$manifest"
}

report_drift

if [ "$print" -eq 1 ]; then
  generate
  exit 0
fi

if [ -e "$out" ] && [ "$force" -ne 1 ]; then
  die "$out already exists — edit it, or pass --force to overwrite"
fi

mkdir -p -- "$(dirname -- "$out")" || die "could not create $(dirname -- "$out")"
umask 077
generate > "$out" || die "could not write $out"
chmod 600 "$out"

count=$(manifest_vars | wc -l | tr -d ' ')
echo "[gen-local-env] wrote $out (mode 600, $count vars) — fill in the values, then: dotfiles-local-env --check"
