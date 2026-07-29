#!/usr/bin/env sh
# Print every shell script in the repo, one path per line.
#
# The single source of truth for "what does shellcheck run against", called by
# BOTH `mise run lint:shell` and the lint:shellcheck CI job. Those two surfaces
# are required to stay aligned (see CLAUDE.md, "Linting & CI"); sharing the
# selector makes that structural instead of a thing to remember.
#
# POSIX sh with only find/grep/sed, because the CI image (koalaman/shellcheck-
# alpine) ships no git — `git ls-files` is unavailable there. That also rules out
# selecting by tracked-ness, so the exclusions below are path-based.
#
# Selection is by shebang, not by extension. Commands in commands/.local/bin and
# git/.local/bin are on PATH and therefore deliberately extensionless — an
# extension glob silently skipped all eight of them, including scripts both
# worktree tools depend on.

set -eu

cd "$(cd "$(dirname "$0")/.." && pwd)"

find . -type f \
  -not -path './.git/*' \
  -not -path './git/.config/git/templates/*' \
  -not -name '__sdkman-noexport-init.sh' \
  -not -name 'RofiEmoji.sh' \
  -print \
  | while IFS= read -r f; do
    case "$f" in
      # Extension is sufficient on its own; no need to read the file.
      *.sh | *.bash)
        printf '%s\n' "$f"
        continue
        ;;
    esac

    # Otherwise take the shebang's word for it. Matches sh/bash/dash/ksh, the
    # dialects shellcheck actually supports, and skips perl/python/fish/etc.
    # (`grep -q` on a single line is cheap enough across a repo this size.)
    if head -n 1 "$f" 2>/dev/null \
      | grep -qE '^#![[:space:]]*(/usr/bin/env[[:space:]]+)?(/[^[:space:]]*/)?(ba|da|k)?sh([[:space:]]|$)'; then
      printf '%s\n' "$f"
    fi
  done \
  | sort
