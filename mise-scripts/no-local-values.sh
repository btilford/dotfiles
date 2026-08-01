#!/usr/bin/env sh
# Fail if tracked content contains a machine-local VALUE, or a generic private
# pattern. Guards the public mirror against re-introducing what was scrubbed.
#
#   mise-scripts/no-local-values.sh              # staged changes (pre-commit)
#   mise-scripts/no-local-values.sh --all        # whole tree (mise run lint:private, CI)
#
# Two halves, on purpose:
#
# 1. VALUES from ~/.config/dotfiles/local.env. A denylist of the actual hostnames
#    cannot live in this repo — committing it would publish the very strings it
#    protects. So the values are read from the untracked file at run time, and
#    only the VARIABLE NAME is ever printed. Side effect worth having: this also
#    blocks committing local.env itself.
#    Skipped when local.env is absent, e.g. in CI. That is why half 2 exists.
#    `SCRUB_*` vars are matched with looser rules — see the case block below.
#
# 2. GENERIC patterns that are private by shape rather than by value, so they are
#    safe to write down and work everywhere including CI.
#
# POSIX sh with only git/grep/sed: the GitLab CI image ships no extra tooling, the
# same constraint mise-scripts/shell-files.sh works under.

set -u

env_file="${DOTFILES_LOCAL_ENV:-$HOME/.config/dotfiles/local.env}"
mode="${1:-staged}"
status=0

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

# Content under test. Staged mode looks at the diff so unrelated pre-existing
# debt in other files never blocks a commit.
if [ "$mode" = "--all" ]; then
  content=$(git ls-files -z | xargs -0 grep -nIH '' 2> /dev/null)
else
  content=$(git diff --cached --unified=0 --no-color | grep -E '^\+' | grep -v '^+++')
fi

[ -n "$content" ] || exit 0

# ---------------------------------------------------------------------------
# 1. Values from local.env
# ---------------------------------------------------------------------------
if [ -r "$env_file" ]; then
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac

    var=$(printf '%s' "$line" | sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\1/p')
    val=$(printf '%s' "$line" | sed -nE 's/^[^=]*=[[:space:]]*(.*)$/\1/p')

    [ -n "$var" ] || continue

    # SCRUB_* are identifiers — an employer name, a client, an internal project
    # directory. They are short and get written in whatever case the author felt
    # like, so the host/URL rules below would miss them: a 7-letter company name
    # never clears an 8-character floor, and a case-sensitive match misses the
    # lowercased directory form of the same word. Both were real misses.
    case "$var" in
      SCRUB_*)
        [ ${#val} -ge 4 ] || continue
        if printf '%s' "$content" | grep -qiF -- "$val"; then
          echo "  ✗ content contains the value of \$$var" >&2
          status=1
        fi
        ;;
      *)
        # Short values produce false positives (a bare port, "true", an empty var).
        [ ${#val} -ge 8 ] || continue
        if printf '%s' "$content" | grep -qF -- "$val"; then
          echo "  ✗ content contains the value of \$$var" >&2
          status=1
        fi
        ;;
    esac
  done < "$env_file"
else
  echo "  · $env_file not readable — value check skipped (pattern check still runs)" >&2
fi

# ---------------------------------------------------------------------------
# 2. Generic patterns
# ---------------------------------------------------------------------------
# RFC1918 addresses. 127.0.0.1 and 0.0.0.0 are fine; so is a bare 10.0.0.0/8 in
# prose about ranges, which is why the pattern requires all four octets.
check_pattern() {
  label="$1"
  pattern="$2"
  hits=$(printf '%s' "$content" | grep -nE "$pattern" | grep -vE 'example|placeholder|<[a-z-]+>|0\.0\.0\.0|127\.0\.0\.1|/(Users|home)/(me|user|username|you|youruser)/|SERIAL|MODEL|VENDOR|Vendor Inc' | head -5)
  if [ -n "$hits" ]; then
    echo "  ✗ $label:" >&2
    printf '%s\n' "$hits" | sed 's/^/      /' >&2
    status=1
  fi
}

check_pattern "RFC1918 address" '(^|[^0-9])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}'
check_pattern "absolute home path" '/home/[a-z][a-z0-9_-]+/|/Users/[a-z][a-z0-9_-]+/'
check_pattern "hardware serial in a monitor descriptor" 'desc:[^"]*[A-Z0-9]{6,}'

if [ "$status" -ne 0 ]; then
  cat >&2 << 'MSG'

  Machine-local content must not be committed. Options:
    - move the value into ~/.config/dotfiles/local.env and read it from the
      environment (see commands/.local/share/dotfiles/required-env)
    - use $HOME instead of an absolute path
    - for a monitor table, use ~/.config/hypr/lua/monitors.local.lua

  This gate also runs in CI, where --no-verify cannot skip it.
MSG
fi

exit "$status"
