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
| `.gitconfig` | Entry point. Contains `[include]` directives for all fragments, plus global LFS config, global credential fallback chain, and Azure DevOps `useHttpPath`. |
| `core.gitconfig` | Editor (`nvim`), pager (`delta`), global excludesfile, `autocrlf`, and per-host credential helper entries for GitHub and the private GitLab instance. Also sets `credential.helper = store` as the second fallback. |
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

Git Credential Manager stores its configuration by operating system (macOS Keychain, Windows Credential Manager, etc.) and its install path varies by machine and package manager. Hardcoding it here would break on any machine where GCM is not installed at the expected path, or on Linux where it may not be present at all.

GCM belongs in `~/.gitconfig.local`, which is never stowed:

```ini
[credential]
    helper =
    helper = /opt/homebrew/bin/git-credential-manager
```

The empty `helper =` line is load-bearing on Git ≥ 2.38. Without it, the new helper appends to the inherited chain rather than replacing it, causing git to try every helper in sequence and potentially prompting multiple times or using stale credentials.

### Global fallback credential chain

`.gitconfig` sets `credential.helper = cache` (in-memory, session-scoped). `core.gitconfig` appends `credential.helper = store` (plaintext `~/.git-credentials`). Because git tries helpers in order and stops at the first that returns credentials, the per-host entries in `core.gitconfig` take priority for GitHub and the private GitLab host, while `cache` → `store` handles everything else.

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
