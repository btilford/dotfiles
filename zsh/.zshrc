# Load modular configuration
for f in ~/.config/zshrc/*; do
    if [ ! -d "$f" ]; then
        c=$(echo "$f" | sed -e "s=.config/zshrc=.config/zshrc/custom=")
        [[ -f "$c" ]] && source "$c" || source "$f"
    fi
done

# Load single customization file (if exists)
[[ -f ~/.zshrc_custom ]] && source ~/.zshrc_custom

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

fpath+=~/.zfunc
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
