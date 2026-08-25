# git package

Context for AI agents working on this stow package. This file is not stowed (excluded by `.stow-local-ignore`).

## What this package manages

The `git` stow package provides the complete git configuration for all machines. It installs:

- `~/.gitconfig` — the root entry point that includes all config fragments
- `~/.config/git/` — modular config fragments and profiles
- `~/.local/bin/gh-git-credential` and `~/.local/bin/glab-git-credential` — credential helper wrapper scripts

## Config file map

| File | Purpose |
| ------ | --------- |
| `.gitconfig` | Entry point. Contains `[include]` directives for all fragments plus LFS config. Includes `~/.gitconfig.local` last so machine-local settings (GCM, etc.) take effect after all shared config. |
| `core.gitconfig` | Editor (`nvim`), pager (`delta`), global excludesfile, `autocrlf`, and per-host credential helper entries for GitHub and the private GitLab instance. |
| `aliases.gitconfig` | Short-form and descriptive aliases. Aliases that shell out use the `!sh -c '...'` pattern. |
| `commands.gitconfig` | Push/pull/fetch/merge/diff behavior. Configures merge and diff tools (nvimdiff, IntelliJ, meld). Note: IntelliJ tool paths are macOS-specific absolute paths and should not be changed to relative. |
| `flow.gitconfig` | Branch prefix conventions for git-flow (`feature-`, `release-`, `hotfix-`, `bug-`, `poc-`, `spike-`). |
| `shell.gitconfig` | Color output, rebase sequence editor (`interactive-rebase-tool`), and notes refs config (`+refs/notes/*:refs/notes/*` on fetch and push — do not remove). **`push = HEAD` must stay alongside the notes push refspec** — see below. |
| `spice.gitconfig` | git-spice: `spice.log.*`, `spice.submit.navigationComment`, `spice.branchDelete.restack`. Forge URLs are machine-specific and live in `~/.gitconfig.local`. |
| `hk.gitconfig` | Registers hk as config-based hooks (`hook.hk-pre-commit`, `hook.hk-commit-msg`; git 2.54+), so every repo with an `hk.pkl` runs its hooks with no per-clone install. Hand-written, not generated — see below. |
| `templates/hooks/post-checkout`, `templates/hooks/pre-commit` | Identical shims installed into new repos by `init.templateDir`. They derive the hook name from `$0` and delegate to `hooks/<name>`. |
| `hooks/post-checkout` | Real logic: auto-init + auto-track branches with git-spice. Exits 0 on every path. |
| `hooks/pre-commit` | Real logic: `betterleaks git --staged`, using the repo's own `.betterleaks.toml` (or `.gitleaks.toml`) when present. Stands down in a repo whose `hk.pkl` runs betterleaks. Must be able to fail. |
| `.local/bin/git-template-sync` | Dereferences `templates/` into `~/.local/share/git-template` (real files — see below). |
| `.local/bin/git-spice-hook-install` | Retrofits hooks into already-cloned repos; chains an incumbent `post-checkout` instead of clobbering it. |
| `.local/bin/hk-git-hook` | Shim the `hook.hk-*.command` entries point at. Resolves `hk` at run time (PATH, then the mise shim) and no-ops when it is absent. |
| `web.gitconfig` | Browser (`brave-browser`) and instaweb httpd. |
| `dirs.gitconfig` | `includeIf "gitdir:..."` rules that route each working directory to the correct identity profile. |
| `profiles/default.gitconfig` | **Not in this repo** — owned by the private dotfiles repo (real name, email, signing key). `default.example.gitconfig` here shows the shape. |
| `profiles/anon.gitconfig` | Anonymous identity: name `nil`, placeholder email, GPG signing disabled. Stays public — nothing personal in it. |

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

| Directory pattern                          | Profile             | Name     | GPG signing   |
| ------------------------------------------ | ------------------- | -------- | ------------- |
| `~/work/anon/` (+ client dirs, local-only) | `anon.gitconfig`    | nil      | no            |
| All others (explicit entries)              | `default.gitconfig` | btilford | yes           |

There is no catch-all `includeIf` — every directory that should use a non-default identity needs an explicit entry. Repos in unlisted directories will not have a user identity set from this file (git will fall back to any system-level config or error on commit).

The `dirs.gitconfig` file contains some legacy entries under the `# Old layout` comment. These are kept for backward compatibility with machines that still use the old directory layout.

## Hooks and `init.templateDir`

`core.gitconfig` sets `init.templateDir = ~/.local/share/git-template`, so every
new clone or `git init` gets a `post-checkout` hook (git-spice auto-tracking) and
a `pre-commit` hook (betterleaks). Hooks live in `$GIT_COMMON_DIR/hooks`, shared by
all worktrees of a repo, so one install covers every worktree whatever created it.

### hk runs from git config, alongside these — not instead of them

`hk.gitconfig` registers hk with git's own multi-hook mechanism,
`hook.<friendly-name>.command` + `.event` (git 2.54+). Unlike `core.hooksPath`
it replaces nothing: traditional `.git/hooks/*` still run, so the template hooks
above are unaffected. A repo without an `hk.pkl` is a silent no-op, which is what
makes it safe to register globally.

Three rules:

- **The friendly-name must not be a hook event name.** `[hook "pre-commit"]` is a
  fatal ambiguity with `hook.<event>.enabled` — every git command in the repo
  fails. Hence `hk-pre-commit` / `hk-commit-msg`.
- **Both surfaces fire, so they must not overlap.** `hooks/pre-commit` exits early
  when the repo's `hk.pkl` names betterleaks; otherwise staged content would be
  scanned twice. It greps for the scanner rather than just testing for the file,
  so a repo that adopts hk *without* a scanner step keeps the gate.
- **Not written by `hk install --global`.** That command bakes an absolute,
  version-pinned mise path into `~/.gitconfig`, which is a stow symlink into this
  repo — the path would be committed and would break on the next `mise upgrade`
  and on every other machine. `.local/bin/hk-git-hook` resolves hk at run time.

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

**`pre-commit` is never chained.** hk and the pre-commit framework already run a
secret scan in repos configured for them (this repo does, via the betterleaks
step in `hk.pkl`), so chaining would scan twice. The installer reports and skips.

## `remote.origin.push` replaces the default — it does not add to it

`shell.gitconfig` syncs git notes to every origin. The push half of that has a
trap that cost a silent no-op push, and both halves of the fix must stay:

```ini
[remote "origin"]
    fetch = +refs/notes/*:refs/notes/*
    push = HEAD
    push = +refs/notes/*:refs/notes/*
```

**`push = HEAD` is not optional.** Setting `remote.<name>.push` at all replaces
git's default push refspec, so with only the notes line present `git push` pushed
notes and *nothing else* — reporting `Everything up-to-date` on a branch a commit
ahead of its upstream. It does not fail and it does not warn, and
`push.default = current` from `commands.gitconfig` is ignored outright, because an
explicit refspec always beats `push.default`. `HEAD` restores that behaviour
explicitly. This is global config under `[remote "origin"]`, so it applied to every
repo on the machine.

**Never single-quote a config value.** git config is not shell: double quotes are
syntax git strips, single quotes are literal characters that end up *inside* the
value. Both entries here were single-quoted, so the configured refspec was
literally `'+refs/notes/*:refs/notes/*'` — leading quote included, matching no ref
ever. `notes.displayRef` had the same defect, so `git log` never displayed a note.
The `fetch` line was unquoted and correct throughout, which is exactly why the
breakage was lopsided and survived so long.

Verify after touching either:

```console
$ git config --get-all remote.origin.push   # no quote characters in the output
HEAD
+refs/notes/*:refs/notes/*
$ git push --dry-run                        # must name the current branch
```

## Machine-local git config

`~/.gitconfig.local` is the only local seam for git, because **git has no
directory include** — `include.path` takes one path per line and there is no
`.d/` mechanism to drop a file into. `.gitconfig` includes it last, so it wins.

What belongs there, never in this package:

- the self-hosted GitLab `[credential]` block
- `[spice "forge.gitlab"] url = …` for git-spice. Note the subsection form: dots
  are illegal in a variable name, and `[spice "forge"]` with `gitlab.url = …`
  makes **every** git command fail with `bad config line`.
- the work identity profile and its `includeIf`. `dirs.gitconfig` has no
  catch-all, so a machine missing that block gets no identity for those repos and
  commits fail outright.

Order matters for git-spice: set the forge URL *before* `git-spice auth login`.
The token is keyed to the resolved forge URL, so logging in first stores it
against gitlab.com and a self-hosted remote then reports `gitlab: not logged in`.

## Rules and constraints

**No absolute paths in wrapper scripts.** The `.local/bin/` scripts call `gh` and `glab` by name. PATH must resolve them at runtime. This is intentional — absolute paths would break across machines and package managers.

**Do not remove the `!` prefix from per-host credential helpers.** The entries in `core.gitconfig` for `https://github.com` (here) and the self-hosted GitLab (in `~/.gitconfig.local`) use `helper = !~/.local/bin/...`. The `!` is required for shell invocation and tilde expansion. Removing it breaks authentication for those hosts silently.

**GCM belongs in `~/.gitconfig.local`, not here.** Never add a `git-credential-manager` helper to any file in this package. It is machine-specific and must remain outside the dotfiles.

**`config.yml` in glab-cli must never contain tokens.** The `glab-cli` stow package stows `aliases.yml` only. `config.yml` is excluded via `.stow-local-ignore` because `glab auth login` writes auth tokens into it. There is deliberately **no tracked template** of it — `glab auth login` writes the file itself, and `mise run glab:config` applies every setting worth version-controlling. `config.yml` is also gitignored and allowlisted in `.betterleaks.toml`, since `betterleaks dir` walks the working directory without honouring `.gitignore` and would otherwise fail the local scan on a real token forever. Never commit a `config.yml` that contains a real token.

**IntelliJ tool paths in `commands.gitconfig` are macOS-specific.** The `difftool "intellij"` and `mergetool "intellij"` entries reference `/Applications/IntelliJ IDEA.app/...`. These are left as-is because they are not active on Linux (the active diff tool is `nvimdiff`). Do not change them to relative paths — the format is required by the application launcher.

## Work identity is out of tree

The work profile and its `includeIf` are deliberately absent — they name an
employer, a work GitHub account and a ticket tracker, and this repo is published
publicly. Both live in `~/.gitconfig.local`, which `.gitconfig` includes last.

There is no catch-all `includeIf` in `dirs.gitconfig`, so a work machine without
that block gives repos under the work directory **no** user identity and commits
fail outright. Same for the self-hosted GitLab credential helper: the wrapper
script ships here, the `[credential "https://<host>"]` block does not.
