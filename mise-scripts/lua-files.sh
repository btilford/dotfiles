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
set -eu

cd "$(cd "$(dirname "$0")/.." && pwd)"

git ls-files '*.lua' |
  grep -v -e '^hyprland/\.config/hypr/lua/colors\.lua$' \
    -e '^wallust/\.config/wallust/templates/colors-hyprland\.lua$'
