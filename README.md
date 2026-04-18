# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/manual/stow.html).

## Structure

Each top-level directory is a **stow package** whose contents mirror `$HOME`. Stow creates symlinks from `$HOME` into the package directory.

```
dotfiles/
  fish/
    .config/
      fish/
        config.fish   →  ~/.config/fish/config.fish
  git/
    .gitconfig        →  ~/.gitconfig
```

Platform-specific packages:

| Platform | Packages |
|----------|----------|
| Both     | `bash`, `fish`, `zsh`, `nvim`, `tmux`, `git`, `starship`, `yazi`, `lazygit`, `helix`, `zellij`, `wezterm` |
| macOS    | `ghostty`, `macos` |
| Linux    | `hyprland`, `rofi`, `konsole`, `kmonad`, `terminator`, `yakuake`, `brave-linux` |

## Usage

Always run stow **one package at a time** from the dotfiles directory. Always use `--no-folding` so stow creates real directories rather than symlinking them — this ensures local-only files in those directories are never affected.

```sh
# Stow a package
stow --no-folding fish

# Unstow a package
stow -D fish

# Restow (useful after adding/removing files in a package)
stow --no-folding -R fish

# Dry run — preview what would happen
stow --no-folding -n -v fish
```

## Local Config

Machine-specific config (local env vars, overrides, secrets) should **not** be committed to this repo. Place those files directly in their target locations outside of stow. Since `--no-folding` is always used, unmanaged files in the same directories as stowed files are left untouched.

## Ignored Files

`.stow-local-ignore` prevents certain files inside packages from being symlinked (uses Perl regex):

- `history.txt` — shell history files
- `lazy-lock.json` — Neovim plugin lockfile
- `\.gitignore`, `README.*`, `CLAUDE\.md` — repo meta files

## Setup on a New Machine

```sh
git clone <repo> ~/dotfiles
cd ~/dotfiles

# Install stow (if needed)
brew install stow          # macOS
sudo apt install stow      # Debian/Ubuntu
sudo pacman -S stow        # Arch

# Stow desired packages one at a time
stow --no-folding fish
stow --no-folding nvim
stow --no-folding tmux
stow --no-folding git
stow --no-folding starship

# macOS extras
stow --no-folding ghostty
stow --no-folding macos
```
