set -x OS_KERN (uname -s)
set -x EDITOR 'nvim'
set -gx  --prepend PATH /opt/homebrew/bin
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
fzf --fish | source
# TODO catch for OS
# set -gx --prepend PATH /Users/btilford/.rd/bin
