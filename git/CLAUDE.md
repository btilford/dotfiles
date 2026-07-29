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
| `shell.gitconfig` | Color output, rebase sequence editor (`interactive-rebase-tool`), and notes refs config (`+refs/notes/*:refs/notes/*` on fetch and push — do not remove). |
| `spice.gitconfig` | git-spice: `spice.log.*`, `spice.submit.navigationComment`, `spice.branchDelete.restack`. Forge URLs are machine-specific and live in `~/.gitconfig.local`. |
| `templates/hooks/post-checkout`, `templates/hooks/pre-commit` | Identical shims installed into new repos by `init.templateDir`. They derive the hook name from `$0` and delegate to `hooks/<name>`. |
| `hooks/post-checkout` | Real logic: auto-init + auto-track branches with git-spice. Exits 0 on every path. |
| `hooks/pre-commit` | Real logic: `gitleaks protect --staged`, using the repo's own `.gitleaks.toml` when present. Must be able to fail. |
| `.local/bin/git-template-sync` | Dereferences `templates/` into `~/.local/share/git-template` (real files — see below). |
| `.local/bin/git-spice-hook-install` | Retrofits hooks into already-cloned repos; chains an incumbent `post-checkout` instead of clobbering it. |
| `web.gitconfig` | Browser (`brave-browser`) and instaweb httpd. |
| `dirs.gitconfig` | `includeIf "gitdir:..."` rules that route each working directory to the correct identity profile. |
| `profiles/default.gitconfig` | Personal identity: name `btilford`, noreply GitHub email, GPG signing key, GPG sign enabled. |
| `profiles/anon.gitconfig` | Anonymous identity: name `nil`, placeholder email, GPG signing disabled. |

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
| `~/Projects/ttp/`, `~/work/anon/` | `anon.gitconfig` | nil | no |
| All others (explicit entries) | `default.gitconfig` | btilford | yes |

There is no catch-all `includeIf` — every directory that should use a non-default identity needs an explicit entry. Repos in unlisted directories will not have a user identity set from this file (git will fall back to any system-level config or error on commit).

The `dirs.gitconfig` file contains some legacy entries under the `# Old layout` comment. These are kept for backward compatibility with machines that still use the old directory layout.

## Hooks and `init.templateDir`

`core.gitconfig` sets `init.templateDir = ~/.local/share/git-template`, so every
new clone or `git init` gets a `post-checkout` hook (git-spice auto-tracking) and
a `pre-commit` hook (gitleaks). Hooks live in `$GIT_COMMON_DIR/hooks`, shared by
all worktrees of a repo, so one install covers every worktree whatever created it.

### Why the template dir is generated instead of stowed

**`init.templateDir` must never point at `~/.config/git/templates`.** Git copies
template entries **as symlinks, preserving the relative link target** — it does
not dereference them. stow makes every file in a package a relative symlink, so
that path would give each new repo a *dangling* `.git/hooks/post-checkout` (plus
dangling `.git/description` and `.git/info/exclude`): hooks that silently never
run, with no error anywhere. Verified behaviour, and the reason the old
`#templatedir = ~/.config/git/default-template` line stayed commented out.

`git-template-sync` therefore does a `cp -RL` of the stowed tree into
`~/.local/share/git-template` and **fails loudly if any symlink survives**. Run it
once per machine (`mise run setup:git-template`) and again after changing anything
under `templates/`.

The two template hooks are deliberately trivial and byte-identical: they resolve
`$0`'s basename and exec `~/.config/git/hooks/<name>`. Real logic therefore lives
in the stowed tree and reaches every repo immediately — no re-sync, no per-repo
reinstall. Keep them that way; putting logic in a template hook means every repo
carries a stale copy of it.

### Why `templateDir` and not global `core.hooksPath`

`core.hooksPath` is not additive and not per-hook: it replaces the hooks directory
wholesale, so any hook name absent from it stops existing in *every* repo on the
machine (verified — a repo's `pre-commit` was ignored entirely and a
secret-carrying commit went through). Keeping repo hooks alive would mean putting
our own chaining script in the path of every git operation. `templateDir` never
intercepts, and its collision case is benign: git keeps the repo's existing hook
and skips ours. `git-spice-hook-install` handles that case explicitly, per repo.

**Chaining moves the incumbent aside, it does not append to it.** Hooks commonly
use guard-clause `exit 0`s — `~/dotfiles`' own graphify `post-checkout` has three
— so appended code would be unreachable on exactly the paths that matter. The
installer renames the incumbent to `post-checkout.chained` and writes a wrapper
that runs ours first, then it. A tool that reinstalls its own hook will clobber
the wrapper and orphan the `.chained` file; re-running the installer restores it.

**`pre-commit` is never chained.** lefthook and the pre-commit framework already
run gitleaks in repos configured for them (this repo does, via `lefthook.yml`), so
chaining would scan twice. The installer reports and skips.

## Rules and constraints

**No absolute paths in wrapper scripts.** The `.local/bin/` scripts call `gh` and `glab` by name. PATH must resolve them at runtime. This is intentional — absolute paths would break across machines and package managers.

**Do not remove the `!` prefix from per-host credential helpers.** The entries in `core.gitconfig` for `https://github.com` (here) and the self-hosted GitLab (in `~/.gitconfig.local`) use `helper = !~/.local/bin/...`. The `!` is required for shell invocation and tilde expansion. Removing it breaks authentication for those hosts silently.

**GCM belongs in `~/.gitconfig.local`, not here.** Never add a `git-credential-manager` helper to any file in this package. It is machine-specific and must remain outside the dotfiles.

**`config.yml` in glab-cli must never contain tokens.** The `glab-cli` stow package stows `aliases.yml` only. `config.yml` is excluded via `.stow-local-ignore` because `glab auth login` writes auth tokens into it. The dotfiles repo carries a token-free template of `config.yml` for reference only. Never commit a `config.yml` that contains a real token.

**IntelliJ tool paths in `commands.gitconfig` are macOS-specific.** The `difftool "intellij"` and `mergetool "intellij"` entries reference `/Applications/IntelliJ IDEA.app/...`. These are left as-is because they are not active on Linux (the active diff tool is `nvimdiff`). Do not change them to relative paths — the format is required by the application launcher.

## Work identity is out of tree

The work profile and its `includeIf` are deliberately absent — they name an
employer, a work GitHub account and a ticket tracker, and this repo is published
publicly. Both live in `~/.gitconfig.local`, which `.gitconfig` includes last.

There is no catch-all `includeIf` in `dirs.gitconfig`, so a work machine without
that block gives repos under the work directory **no** user identity and commits
fail outright. Same for the self-hosted GitLab credential helper: the wrapper
script ships here, the `[credential "https://<host>"]` block does not.
