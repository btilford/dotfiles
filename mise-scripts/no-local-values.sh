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
#
# 2. GENERIC patterns that are private by shape rather than by value, so they are
#    safe to write down and work everywhere including CI.
#
# 3. LOCAL patterns from ~/.config/dotfiles/scrub.patterns — an untracked list of
#    regexes for things private by *identity* rather than by shape or by being
#    config: an employer name, a client, an internal project directory. No pattern
#    can distinguish a company name from any other word, and such a name is not a
#    value any config consumes, so halves 1 and 2 are both blind to it. Same
#    discipline as half 1: the file is untracked and only its LINE NUMBER is ever
#    printed, never the pattern.
#
# POSIX sh with only git/grep/sed: the GitLab CI image ships no extra tooling, the
# same constraint mise-scripts/shell-files.sh works under.

set -u

env_file="${DOTFILES_LOCAL_ENV:-$HOME/.config/dotfiles/local.env}"
patterns_file="${DOTFILES_SCRUB_PATTERNS:-$HOME/.config/dotfiles/scrub.patterns}"
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
    # Short values produce false positives (a bare port, "true", an empty var).
    [ ${#val} -ge 8 ] || continue

    if printf '%s' "$content" | grep -qF -- "$val"; then
      echo "  ✗ content contains the value of \$$var" >&2
      status=1
    fi
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
    if [ "$mode" = "--all" ]; then
      # Tree mode is the one CI runs, and CI job logs are a published surface once
      # the mirror is public. Printing the offending line there would disclose the
      # exact value this gate exists to keep out — the failure would leak what the
      # commit was blocked for. Location only. Fields are
      # <stream-index>:<path>:<line>:<text> — the index comes from the grep -n in
      # check_pattern, the path and line from the grep -nIH that built `content`.
      printf '%s\n' "$hits" | cut -d: -f2,3 | sed 's/^/      /' >&2
      echo "      (content withheld — run: mise-scripts/no-local-values.sh --all locally)" >&2
    else
      # Staged mode runs in the author's own terminal, on lines they just wrote.
      printf '%s\n' "$hits" | sed 's/^/      /' >&2
    fi
    status=1
  fi
}

check_pattern "RFC1918 address" '(^|[^0-9])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}'
check_pattern "absolute home path" '/home/[a-z][a-z0-9_-]+/|/Users/[a-z][a-z0-9_-]+/'
check_pattern "hardware serial in a monitor descriptor" 'desc:[^"]*[A-Z0-9]{6,}'

# ---------------------------------------------------------------------------
# 3. Local patterns
# ---------------------------------------------------------------------------
if [ -r "$patterns_file" ]; then
  pat_line=0
  while IFS= read -r pattern; do
    pat_line=$((pat_line + 1))
    case "$pattern" in '' | '#'*) continue ;; esac

    # A pattern that does not compile makes grep exit 2, which is neither "found"
    # nor "clean". Left unchecked it would read as a pass and silently disable
    # that line for good, so it is reported as a failure instead.
    printf '' | grep -Eiq -- "$pattern" 2> /dev/null
    if [ $? -gt 1 ]; then
      echo "  ✗ $patterns_file:$pat_line is not a valid regex — gate cannot run it" >&2
      status=1
      continue
    fi

    hits=$(printf '%s' "$content" | grep -nEi -- "$pattern" | head -5)
    [ -n "$hits" ] || continue

    # The pattern itself is private — it spells out the thing being kept out of
    # the mirror — so only its line number is named, never its text.
    echo "  ✗ matches $patterns_file:$pat_line" >&2
    if [ "$mode" = "--all" ]; then
      printf '%s\n' "$hits" | cut -d: -f2,3 | sed 's/^/      /' >&2
      echo "      (content withheld — run: mise-scripts/no-local-values.sh --all locally)" >&2
    else
      printf '%s\n' "$hits" | sed 's/^/      /' >&2
    fi
    status=1
  done < "$patterns_file"
fi

if [ "$status" -ne 0 ]; then
  cat >&2 << 'MSG'

  Machine-local content must not be committed. Options:
    - move the value into ~/.config/dotfiles/local.env and read it from the
      environment (see commands/.local/share/dotfiles/required-env)
    - use $HOME instead of an absolute path
    - for a monitor table, use ~/.config/hypr/lua/monitors.local.lua
    - for a name that is private by identity (employer, client, internal
      project), add a regex to ~/.config/dotfiles/scrub.patterns

  This gate also runs in CI, where --no-verify cannot skip it.
MSG
fi

exit "$status"
