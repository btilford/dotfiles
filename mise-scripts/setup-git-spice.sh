#!/usr/bin/env bash
# Per-machine git-spice bootstrap. Idempotent — safe to re-run any time.
#
#   mise run setup:git-spice          # or: ./mise-scripts/setup-git-spice.sh
#   ./mise-scripts/setup-git-spice.sh --repos ~/src/a ~/src/b
#
# What it cannot do for you, and why:
#   - install the package   -> needs sudo (metapac/paru); it tells you the command
#   - `auth login`          -> interactive by design; it tells you the command
#   - the forge URL         -> belongs in ~/.gitconfig.local, which is machine-local
#                              and deliberately outside this repo (public mirror)
#
# Everything else it does directly, then verifies.

set -uo pipefail

repos=()
if [ "${1:-}" = "--repos" ]; then
  shift
  repos=("$@")
fi

ok=0
warn=0
fail=0

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
pass() {
  printf '  ✓ %s\n' "$1"
  ok=$((ok + 1))
}
note() {
  printf '  ⚠ %s\n' "$1"
  warn=$((warn + 1))
}
bad() {
  printf '  ✗ %s\n' "$1"
  fail=$((fail + 1))
}

say "1. git-spice installed"
if command -v git-spice > /dev/null 2>&1; then
  pass "$(git-spice --version 2> /dev/null | head -1)"
else
  bad "git-spice not found. Declared in metapac; install with:"
  printf '      Arch:  paru -S --needed git-spice-bin\n'
  printf '      macOS: brew install git-spice\n'
  printf '      (or: metapac sync)\n'
fi

say "2. betterleaks installed (the pre-commit hook is inert without it)"
if command -v betterleaks > /dev/null 2>&1; then
  pass "$(betterleaks version 2> /dev/null | head -1)"
else
  note "betterleaks not found — the global pre-commit hook will no-op."
  # No Arch package: it is in no official repo, and aur/betterleaks builds from
  # the git HEAD with a pkgver() that queries the GitHub API at build time. mise
  # pins a release instead. brew has it, and the metapac macos group declares it.
  printf '      Arch:  mise use -g betterleaks@latest\n'
  printf '      macOS: brew install betterleaks   (or: metapac sync)\n'
fi

say "3. template directory (init.templateDir)"
# The template must hold REAL files: git copies template entries as symlinks,
# preserving the relative target, and stow makes every file a symlink — so a
# stowed template dir yields dangling hooks that silently never run.
if command -v git-template-sync > /dev/null 2>&1; then
  if git-template-sync > /dev/null 2>&1; then
    dest="${GIT_TEMPLATE_DEST:-$HOME/.local/share/git-template}"
    pass "generated $dest"
    if [ -n "$(find "$dest" -type l -print -quit 2> /dev/null)" ]; then
      bad "symlinks present in $dest — hooks would dangle"
    else
      pass "no symlinks (hooks will actually run)"
    fi
  else
    bad "git-template-sync failed — is the git stow package stowed?"
  fi
else
  bad "git-template-sync not on PATH — stow the git package first"
fi

configured=$(git config --get init.templateDir 2> /dev/null || true)
case "$configured" in
  *git-template) pass "init.templateDir = $configured" ;;
  "") bad "init.templateDir unset — is the git stow package stowed?" ;;
  *) note "init.templateDir = $configured (expected …/git-template)" ;;
esac

say "4. forge URL for the self-hosted GitLab"
# Machine-local on purpose: this repo is publicly mirrored, so no private
# hostnames in the tree.
if git config --get spice.forge.gitlab.url > /dev/null 2>&1; then
  pass "spice.forge.gitlab.url is set"
else
  note "spice.forge.gitlab.url unset — self-hosted remotes will fail with"
  printf '      "no forge found". Add to ~/.gitconfig.local (NOT this repo):\n\n'
  printf '        [spice "forge.gitlab"]\n'
  printf '            url = https://<your-gitlab-host>\n\n'
  printf '      Note the subsection form: dots are not legal in a variable name,\n'
  printf '      and `[spice "forge"] gitlab.url = …` makes every git command fail.\n'
fi

say "5. authentication"
if command -v git-spice > /dev/null 2>&1; then
  if git-spice auth status --forge gitlab > /dev/null 2>&1; then
    pass "gitlab: logged in"
  else
    note "gitlab: not logged in. Run:  git-spice auth login --forge gitlab"
    printf '      Choose "CLI" to reuse the glab token (no second credential to manage).\n'
    printf '      Log in AFTER setting the forge URL above — a token stored without it\n'
    printf '      is keyed to gitlab.com and will not satisfy a self-hosted remote.\n'
  fi
  if command -v gh > /dev/null 2>&1; then
    if git-spice auth status --forge github > /dev/null 2>&1; then
      pass "github: logged in"
    else
      note "github: not logged in (only needed for GitHub repos). Run:  git-spice auth login --forge github"
    fi
  fi
fi

say "6. hooks in existing repos"
# init.templateDir only fires at clone/init, so anything cloned earlier has no
# hooks until it is retrofitted.
if [ "${#repos[@]}" -gt 0 ]; then
  if command -v git-spice-hook-install > /dev/null 2>&1; then
    git-spice-hook-install "${repos[@]}" || note "some repos were skipped (see above)"
  else
    bad "git-spice-hook-install not on PATH"
  fi
else
  note "no --repos given; new clones are covered automatically. For existing ones:"
  printf '        git-spice-hook-install ~/src/repo-a ~/src/repo-b\n'
fi

say "7. this repo's own hooks (hk)"
# hk replaced lefthook on 2026-08-24, and with it the per-clone install: the
# stowed ~/.config/git/hk.gitconfig registers hk as a config-based hook
# (`hook.hk-pre-commit.command`, git 2.54+), which fires in EVERY repo that
# carries an hk.pkl. The per-clone `hk install` is only the fallback for a git
# too old for that, or a machine whose user gitconfig is not ours.
if [ -f hk.pkl ]; then
  if [ -n "$(git config --get hook.hk-pre-commit.command 2> /dev/null)" ]; then
    pass "hk registered as a global config hook (no per-clone install needed)"
  elif [ -f "$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)/hooks/pre-commit" ] &&
    grep -q hk "$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)/hooks/pre-commit" 2> /dev/null; then
    pass "hk hooks installed in this clone"
  else
    note "hk config present but neither the global hook nor a per-clone install is."
    printf '      Global (git 2.54+): stow the git package, then re-check.\n'
    printf '      Per clone:          mise run hooks\n'
    printf '      Without one, the formatters (shfmt/stylua/taplo/markdownlint) and\n'
    printf '      the betterleaks step never run on a commit.\n'
  fi
else
  pass "no hk config here; nothing to install"
fi

say "Summary"
printf '  %d ok, %d to do, %d broken\n' "$ok" "$warn" "$fail"
[ "$fail" -eq 0 ] || exit 1
