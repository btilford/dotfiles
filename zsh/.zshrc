# Load modular configuration
for f in ~/.config/zshrc/*; do
    if [ ! -d "$f" ]; then
        c=$(echo "$f" | sed -e "s=.config/zshrc=.config/zshrc/custom=")
        [[ -f "$c" ]] && source "$c" || source "$f"
    fi
done

# Load local-only overrides (if exists)
[[ -f ~/.zshrc_local ]] && source ~/.zshrc_local

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

fpath+=~/.zfunc
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select

# git-spice completion must come AFTER compinit: what `git-spice shell completion
# zsh` emits is imperative code needing bashcompinit, not an fpath function, so it
# cannot live in a ~/.config/zshrc drop-in (those are sourced above, before
# compinit) nor in ~/.zfunc. It is eval'd rather than committed like _grype and
# _workmux because the generated output hardcodes the absolute path of the binary,
# which differs between Arch (/usr/bin) and macOS (brew).
if command -v git-spice > /dev/null 2>&1; then
    eval "$(git-spice shell completion zsh)"
fi
