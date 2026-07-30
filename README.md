# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/manual/stow.html).

## Structure

Each top-level directory is a **stow package** whose contents mirror `$HOME`. Stow creates symlinks from `$HOME` into the package directory.

```text
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

## Git

The `git` package uses a fragmented config structure. `~/.gitconfig` is the entry point; it includes all fragments via `[include]` directives. All fragments live under `~/.config/git/`.

```text
git/
  .gitconfig                        # entry point — includes all fragments
  .config/git/
    core.gitconfig                  # editor, pager (delta), credential helpers
    aliases.gitconfig               # git aliases
    commands.gitconfig              # push/pull/merge/diff tool settings
    flow.gitconfig                  # gitflow branch prefixes
    shell.gitconfig                 # color, rebase editor, notes refs
    web.gitconfig                   # browser, instaweb
    dirs.gitconfig                  # includeIf profile routing by directory
    ignore                          # global gitignore
    default.gitignore               # additional global ignore patterns
    profiles/
      default.gitconfig             # personal identity (btilford)
      anon.gitconfig                # anonymous commits (no name, no GPG)
  .local/bin/
    gh-git-credential               # wrapper: exec gh auth git-credential "$@"
    glab-git-credential             # wrapper: exec glab auth git-credential "$@"
```

### Profile switching

`dirs.gitconfig` uses `includeIf "gitdir:..."` to select the right identity automatically based on the working directory:

| Directory | Profile | Identity |
|-----------|---------|----------|
| `~/work/anon/` (+ client dirs, local-only) | `anon.gitconfig` | no name, no GPG |
| Everything else | `default.gitconfig` | btilford, GPG signed |

A work identity is **not** in this repo — it would name an employer, a work
account and a ticket tracker. Add both the profile and its `includeIf` to
`~/.gitconfig.local` on the machine that needs it. There is no catch-all
`includeIf`, so until you do, repos under that directory get no identity and
commits fail.

No manual profile switching is needed — git picks the right identity when you `cd` into a repo.

### Credential helpers

Per-host credential helpers are configured in `core.gitconfig`:

```ini
[credential "https://github.com"]
    helper = !~/.local/bin/gh-git-credential

```

A self-hosted GitLab gets the same treatment, but its host name identifies
private infrastructure, so that block lives in `~/.gitconfig.local`:

```ini
[credential "https://gitlab.example.com"]
    helper = !~/.local/bin/glab-git-credential
```

The `!` prefix tells git to invoke the value as a shell command, which is required for tilde expansion and PATH resolution. Each wrapper script calls the CLI tool by name (`gh` or `glab`) rather than by absolute path, keeping the helpers cross-platform.

The global fallback chain in `.gitconfig` is `cache` (in-memory) → `store` (plaintext `~/.git-credentials`). The per-host helpers override this for GitHub and the private GitLab instance.

Git Credential Manager (GCM) is intentionally **not** in the dotfiles — it is machine-specific. On macOS, add it to `~/.gitconfig.local` after stowing:

```ini
[credential]
    helper =
    helper = /opt/homebrew/bin/git-credential-manager
```

The empty `helper =` line resets the inherited chain before setting GCM. This is required behavior for Git ≥ 2.38.

### Git setup on a new machine

```sh
stow --no-folding git

# Authenticate CLIs so the credential wrappers work
gh auth login
glab auth login --hostname <your-gitlab-host>

# macOS only: configure GCM in a local override (not tracked in dotfiles)
# Create ~/.gitconfig.local with the [credential] block shown above
```

## Local Config

Machine-specific config (local env vars, overrides, secrets) should **not** be committed to this repo. Place those files directly in their target locations outside of stow. Since `--no-folding` is always used, unmanaged files in the same directories as stowed files are left untouched.

## Ignored Files

`.stow-local-ignore` prevents certain files inside packages from being symlinked (uses Perl regex):

- `history.txt` — shell history files
- `lazy-lock.json` — Neovim plugin lockfile
- `\.gitignore`, `README.*`, `CLAUDE\.md` — repo meta files

## Setup on a New Machine

## Development Tools

Some tools in this repo require [mise](https://mise.jdx.dev/) to be installed and activated:

```sh
# Install mise
brew install mise              # macOS
curl https://mise.run | sh     # Linux

# Activate mise in your shell
# Fish: add to ~/.config/fish/config.fish
eval (mise activate fish)

# Bash/Zsh: add to ~/.bashrc or ~/.zshrc
eval "$(mise activate bash)"

# Install tools from .mise.toml (if present)
mise install
```

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
