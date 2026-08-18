# bun — global JS CLIs live in ~/.bun/bin (bun is the sole owner of global JS
# tools; npm globals are deliberately unused). Same path on Linux and macOS.
# No-op on machines without bun.

if test -d "$HOME/.bun/bin"
    set --export BUN_INSTALL "$HOME/.bun"
    fish_add_path --global "$BUN_INSTALL/bin"
end

# `bun pm ls -g` colorizes even when piped and ignores NO_COLOR, so metapac's bun
# backend captures ANSI escapes into package names. They then never match the
# declared names, and `metapac clean` offers to uninstall every bun package.
# FORCE_COLOR=0 is the only switch bun honors.
#
# /usr/bin prepended: this repo's own mise.toml declares python (a dev-toolchain
# pin for lint/CI tasks) and mise activates it project-wide, so a sync run from
# inside ~/dotfiles shadows /usr/bin/python3 for every AUR build paru spawns —
# breaking any PKGBUILD that assumes the system Python (e.g. python-setuptools
# is only installed there). Putting /usr/bin first restores it for this
# subprocess tree without touching the interactive shell's own PATH.
if command -q metapac
    function metapac --wraps metapac --description "metapac: bun color workaround + hardware-derived --hostname"
        set -lx PATH /usr/bin $PATH
        set -lx FORCE_COLOR 0
        command metapac --hostname (metapac-hostname-key) $argv
    end
end
