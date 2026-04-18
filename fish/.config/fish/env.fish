set -x OS_KERN (uname -s)
set -gx XDG_CONFIG_HOME $HOME/.config
set -x EDITOR 'nvim'
# Homebrew on macOS (Apple Silicon)
if test "$OS_KERN" = Darwin
    set -gx --prepend PATH /opt/homebrew/bin
end
set -x VISUAL 'nvim-qt'


set -x M2_HOME $HOME/.m2
# ASDF configuration code
if test -z $ASDF_DATA_DIR
    set _asdf_shims "$HOME/.asdf/shims"
else
    set _asdf_shims "$ASDF_DATA_DIR/shims"
end

# Do not use fish_add_path (added in Fish 3.2) because it
# potentially changes the order of items in PATH
if not contains $_asdf_shims $PATH
    set -gx --prepend PATH $_asdf_shims
end
set --erase _asdf_shims

set -gx --prepend PATH $HOME/.cargo/bin
set -gx --prepend PATH $HOME/.local/bin
# fzf key bindings are interactive-only; guard so Claude/scripts don't error
if status is-interactive
    fzf --fish | source
end
