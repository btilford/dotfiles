set -x OS_KERN (uname -s)
set -gx XDG_CONFIG_HOME $HOME/.config
set -x EDITOR 'nvim'
set -x YARN_ENABLE_SCRIPTS false
set -x VISUAL 'nvim'
# Homebrew on macOS (Apple Silicon)
if test "$OS_KERN" = Darwin
    set -gx --prepend PATH /opt/homebrew/bin
end


set -x M2_HOME $HOME/.m2

# $VOL_SCREENSHOT_ARCHIVE / $DOTFILES_SCREENSHOT_ARCHIVE are machine-local (they
# point into a notes vault that only exists on some hosts) — set them in
# ~/.config/fish/conf.d/local.fish, which is untracked. See scripts/visuals/README.md.

set -gx --prepend PATH $HOME/.cargo/bin
set -gx --prepend PATH $HOME/.local/bin
# mise shims last so they win over homebrew and other system tools
if not contains $HOME/.local/share/mise/shims $PATH
    set -gx --prepend PATH $HOME/.local/share/mise/shims
end
# fzf key bindings are interactive-only; guard so Claude/scripts don't error
if status is-interactive
    fzf --fish | source
end
