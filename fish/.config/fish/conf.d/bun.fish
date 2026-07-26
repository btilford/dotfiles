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
if command -q metapac
    function metapac --wraps metapac --description "metapac (bun color workaround)"
        FORCE_COLOR=0 command metapac $argv
    end
end
