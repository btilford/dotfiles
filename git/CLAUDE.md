# git package

Context for AI agents working on this stow package. This file is not stowed (excluded by `.stow-local-ignore`).

## What this package manages

The `git` stow package provides the complete git configuration for all machines. It installs:

- `~/.gitconfig` — the root entry point that includes all config fragments
- `~/.config/git/` — modular config fragments and profiles
- `~/.local/bin/gh-git-credential` and `~/.local/bin/glab-git-credential` — credential helper wrapper scripts

## Config file map

| File | Purpose |
|------|---------|
| `.gitconfig` | Entry point. Contains `[include]` directives for all fragments plus LFS config. Includes `~/.gitconfig.local` last so machine-local settings (GCM, etc.) take effect after all shared config. |
| `core.gitconfig` | Editor (`nvim`), pager (`delta`), global excludesfile, `autocrlf`, and per-host credential helper entries for GitHub and the private GitLab instance. |
| `aliases.gitconfig` | Short-form and descriptive aliases. Aliases that shell out use the `!sh -c '...'` pattern. |
| `commands.gitconfig` | Push/pull/fetch/merge/diff behavior. Configures merge and diff tools (nvimdiff, IntelliJ, meld). Note: IntelliJ tool paths are macOS-specific absolute paths and should not be changed to relative. |
| `flow.gitconfig` | Branch prefix conventions for git-flow (`feature-`, `release-`, `hotfix-`, `bug-`, `poc-`, `spike-`). |
| `shell.gitconfig` | Color output, rebase sequence editor (`interactive-rebase-tool`), and notes refs config. |
| `web.gitconfig` | Browser (`brave-browser`) and instaweb httpd. |
| `dirs.gitconfig` | `includeIf "gitdir:..."` rules that route each working directory to the correct identity profile. |
| `profiles/default.gitconfig` | Personal identity: name `btilford`, noreply GitHub email, GPG signing key, GPG sign enabled. |
| `profiles/REDACTED.gitconfig` | Work identity: name `REDACTED`, noreply GitHub email for work account, GPG signing key, commit template. |
| `profiles/anon.gitconfig` | Anonymous identity: name `nil`, placeholder email, GPG signing disabled. |
| `profiles/REDACTED-commit.txt` | Commit message template applied when committing in work repos. |

## Credential helper design

### Why wrapper scripts instead of inline shell commands

The credential helpers are separate files in `.local/bin/` rather than inline `!exec glab auth git-credential "$@"` values in the config. This keeps the gitconfig readable and makes each helper independently testable and version-controlled. The scripts are intentionally minimal — a single `exec` call — so there is no logic to maintain.

### Why the `!` prefix is required

Git's `credential.helper` is normally interpreted as a path to a binary, prefixed with `git-credential-`. The `!` prefix changes this: git passes the entire value to the shell for evaluation. This is necessary for two reasons:

1. Tilde (`~`) in the path must be expanded by the shell. Git does not expand `~` itself in credential helper values.
2. The wrapper scripts are not on `PATH` under a `git-credential-*` name, so the normal lookup mechanism does not apply.

Removing the `!` prefix will silently break the per-host helpers.

### Why GCM is excluded from dotfiles

Git Credential Manager stores its configuration by operating system (macOS Keychain, libsecret on Linux, etc.) and its install path varies by machine and package manager. Hardcoding it here would break on any machine where GCM is not installed at the expected path.

GCM belongs in `~/.gitconfig.local`, which is never stowed. `.gitconfig` includes this file last so it can override any shared config.

The empty `helper =` line is load-bearing on Git ≥ 2.38. It resets any previously-accumulated helpers (including `osxkeychain` from Xcode's system gitconfig) so GCM is the sole fallback for unmatched hosts.

### macOS setup (`~/.gitconfig.local`)

GCM 2.8.0 is installed via Homebrew Cask (`brew install git-credential-manager`). Binary at `/usr/local/bin/git-credential-manager`. Uses macOS Keychain as the backing store.

```ini
# ~/.gitconfig.local
[credential]
    helper = 
    helper = /usr/local/bin/git-credential-manager

[credential "https://dev.azure.com"]
    useHttpPath = true
```

### Linux setup (`~/.gitconfig.local`)

GCM on Linux uses `libsecret` (GNOME Keyring / KWallet) or a headless store. Install via:

```bash
# Debian/Ubuntu — download .deb from GitHub releases
wget https://github.com/git-ecosystem/git-credential-manager/releases/latest/download/gcm-linux_amd64.deb
sudo dpkg -i gcm-linux_amd64.deb
git-credential-manager configure   # writes to ~/.gitconfig, move entry to .gitconfig.local

# Arch
yay -S git-credential-manager-core-bin

# After installing, find the binary path:
which git-credential-manager
```

Then create `~/.gitconfig.local`:

```ini
# ~/.gitconfig.local
[credential]
    helper = 
    helper = /usr/lib/git-core/git-credential-manager   # adjust path per distro

[credential "https://dev.azure.com"]
    useHttpPath = true
```

For headless/SSH Linux machines without a keyring daemon, set the backing store before first use:

```bash
export GCM_CREDENTIAL_STORE=secretservice   # if GNOME Keyring is running
# or
export GCM_CREDENTIAL_STORE=gpg            # GPG-encrypted file store (no daemon needed)
# or
export GCM_CREDENTIAL_STORE=cache          # in-memory, lost on reboot
```

Add the chosen `GCM_CREDENTIAL_STORE` export to `~/.config/fish/conf.d/local.fish` (or shell equiv) — do not commit it.

Run `git credential-manager configure` once after setup to verify. Then authenticate by performing a `git fetch` or `git push` against a protected repo; GCM will prompt once and store the credential in the keyring.

### Global fallback credential chain

The per-host helpers in `core.gitconfig` (GitHub → `gh` CLI, GitLab → `glab` CLI) fire first for those hosts. For all other hosts, `~/.gitconfig.local` provides GCM as the sole fallback. `~/.git-credentials` (plaintext store) is no longer used and should be removed once GCM is set up on each machine.

## Profile system

`dirs.gitconfig` uses `includeIf "gitdir:<path>"` to select an identity profile. Git evaluates these conditionally at read time — the matching include wins and its `[user]` and `[commit]` settings override the previous values.

| Directory pattern | Profile | Name | GPG signing |
|-------------------|---------|------|-------------|
| `~/Projects/REDACTED/` | `REDACTED.gitconfig` | REDACTED | yes |
| `~/Projects/ttp/`, `~/work/anon/` | `anon.gitconfig` | nil | no |
| All others (explicit entries) | `default.gitconfig` | btilford | yes |

There is no catch-all `includeIf` — every directory that should use a non-default identity needs an explicit entry. Repos in unlisted directories will not have a user identity set from this file (git will fall back to any system-level config or error on commit).

The `dirs.gitconfig` file contains some legacy entries under the `# Old layout` comment. These are kept for backward compatibility with machines that still use the old directory layout.

## Rules and constraints

**No absolute paths in wrapper scripts.** The `.local/bin/` scripts call `gh` and `glab` by name. PATH must resolve them at runtime. This is intentional — absolute paths would break across machines and package managers.

**Do not remove the `!` prefix from per-host credential helpers.** The entries in `core.gitconfig` for `https://github.com` and `https://gitlab.example.com` use `helper = !~/.local/bin/...`. The `!` is required for shell invocation and tilde expansion. Removing it breaks authentication for those hosts silently.

**GCM belongs in `~/.gitconfig.local`, not here.** Never add a `git-credential-manager` helper to any file in this package. It is machine-specific and must remain outside the dotfiles.

**`config.yml` in glab-cli must never contain tokens.** The `glab-cli` stow package stows `aliases.yml` only. `config.yml` is excluded via `.stow-local-ignore` because `glab auth login` writes auth tokens into it. The dotfiles repo carries a token-free template of `config.yml` for reference only. Never commit a `config.yml` that contains a real token.

**IntelliJ tool paths in `commands.gitconfig` are macOS-specific.** The `difftool "intellij"` and `mergetool "intellij"` entries reference `/Applications/IntelliJ IDEA.app/...`. These are left as-is because they are not active on Linux (the active diff tool is `nvimdiff`). Do not change them to relative paths — the format is required by the application launcher.
