export XDG_CONFIG_HOME="$HOME/.config"

# include .profile if it exists
[[ -f ~/.profile ]] && . ~/.profile

# include .bashrc if it exists
[[ -f ~/.bashrc ]] && . ~/.bashrc

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
