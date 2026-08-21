#!/usr/bin/env sh
# Print every tracked .lua file that stylua must format/check, one path per line.
#
# The single source of truth for "what does stylua run against", called by
# `mise run fmt:lua` and `mise run lint:stylua`. Those two surfaces are
# required to stay aligned (see CLAUDE.md, "Linting & CI"); sharing the
# selector makes that structural instead of a thing to remember.
#
# Two deliberate exclusions, kept in step with .styluaignore and lefthook's
# stylua command:
#
#   hyprland/.config/hypr/lua/colors.lua
#     A frozen seed (.stow-frozen, skip-worktree in every clone). wallust
#     rewrites it through the stow symlink on every wallpaper rotation, so a
#     commit that reflows it silently keeps the pre-rotation content — the
#     working tree already disagrees with what git would record.
#
#   wallust/.config/wallust/templates/colors-hyprland.lua
#     A wallust render TEMPLATE, not source. wallust substitutes
#     `{{color0 | strip}}` placeholders into it; its indentation is wallust's
#     template syntax, not this repo's Lua code style.
#
# Uses `git ls-files`, unlike shell-files.sh/yaml-files.sh which use `find`
# because their CI images ship no git. stylua is NOT in the GitLab subset
# (that runner can't reach GitHub/sigstore for mise's stylua install — see
# CLAUDE.md), so this script only ever runs somewhere git is available: local
# and GitHub Actions (full checkout). Do not copy this selector as a template
# for a future gate that DOES need to run git-less.
set -eu

cd "$(cd "$(dirname "$0")/.." && pwd)"

git ls-files '*.lua' |
  grep -v -e '^hyprland/\.config/hypr/lua/colors\.lua$' \
    -e '^wallust/\.config/wallust/templates/colors-hyprland\.lua$'
