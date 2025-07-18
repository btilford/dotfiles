#!/usr/bin/env bash

brew isntall --cask ghostty
brew install --cask nikitabobko/tap/aerospace
brew tap lambdalisue/neovim-qt
brew install --cask karabiner-elements
brew tap sdkman/tap
brew install --cask google-cloud-sdk
brew install --cask speedcrunch

brew install zoxide \
    fd \
    fzf \
    bat \
    exa \
    starship \
    git-delta \
    gh \
    ghq \
    git-credential-manager \
    git-lfs \
    git-open \
    git-sizer \
    git-town \
    glab \
    neovim-qt \
    lazygit \
    lazydocker \
    lua \
    lua-language-server \
    ruby \
    asdf \
    sdkman-cli \
    fish \
    nushell \
    kmonad \
    yazi \
    stow \
    visidata \
    ripgrep-all \
    glow \
    carapace \
    kubectl \
    tmux \
    caffinated

declare -a shells=("/usr/local/bin/fish" "/usr/local/bin/nushell")
for shell in "${shells[@]}"; do
    if ! grep -q "$shell" /etc/shells; then
        echo "Adding $shell to /etc/shells"
        echo "$shell" | sudo tee -a /etc/shells
    fi
done

stow --adopt starship/
stow --adopt macos/
stow --adopt ghostty/
stow --adopt commands/
stow --adopt fish/
stow --adopt bash/
stow --adopt zsh/
stow --adopt nushell/
stow --adopt nvim/
stow --adopt git/
stow --adopt glab-cli/
stow --adopt flow/
stow --adopt dict/
stow --adopt fastfetch/
stow --adopt tmux/
stow --adopt yazi/

git reset --hard

source ~/.zshrc

asdf plugin add nodejs
asdf plugin add python
asdf install nodejs latest
asdf install python latest

echo "Completed"

echo "# Don't forget to logout and then install:

- [ ] Jetbrains Toolbox
- [ ] Configure keyboard in settings
- [ ] Configure KMonad
- [ ] Install Raycast
- [ ] Install Java and Kotlin SDKs
- [ ] Install Slack


" | tee ~/POST_INSTALL.md | glow
