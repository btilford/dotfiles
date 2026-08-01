# Dotfiles

Stow-managed dotfiles for btilford. Each top-level directory is a stow package mirroring `$HOME`.

## Rules

- No absolute paths in configs — use `~`, `$HOME`, or `$XDG_*` vars
- Local machine-specific config lives outside the repo, not in stow packages
- Cross-platform: macOS + Linux. Platform-specific packages are isolated
- Always stow one package at a time with `--no-folding` to prevent directory symlinking and protect local-only files
- `hyprland/.config/hypr/wallpaper_effects/.wallpaper_current` is a committed seed (fresh installs need it to exist), but wallpaper rotation rewrites it through the stow symlink every ~30 min. After cloning, run `git update-index --skip-worktree hyprland/.config/hypr/wallpaper_effects/.wallpaper_current` once per machine so the churn never lands in git. Never commit content updates to it.

## This repo is published publicly — nothing private in tree

The repo is mirrored to a public GitHub. **No private infrastructure names, no
employer identity, no credentials.** That is not just a secrets rule: host names,
LAN IPs and internal project names are infrastructure disclosure, and they are
just as permanent once pushed.

Anything machine-specific resolves from the environment with a public fallback,
or lives in an untracked file. The single provisioning surface is
**`~/.config/dotfiles/local.env`** — see "Machine-local config: the `.d/` pattern"
below for how each shell and the systemd session read it. (It replaced
`local.fish`, which only fish read, so on macOS and in nushell none of these were
ever set.)

| Variable | Consumed by | Unset behaviour |
| --- | --- | --- |
| `DOTFILES_GITLAB_HOST` | `mise.toml` → `glab:config` | skips per-host `git_protocol` |
| `INFISICAL_PROJECT` / `INFISICAL_DOMAIN` | `sync-litellm-models` | **exits** with a message |
| `LITELLM_GATEWAY` | `sync-litellm-models` | **exits** with a message |
| `LITELLM_GATEWAY` | `nvim` `plugins/ai.lua` | `http://localhost:4000` |
| `LEMONADE_URL` / `OLLAMA_URL` | `sync-litellm-models` | `localhost:13305` / `:11434` |
| `OLLAMA_HOST` | `nvim` `plugins/ai.lua` (gen.nvim) | `localhost` |
| `HERMES_TUI_GATEWAY_URL` | `fish/conf.d/hermes.fish` | `http://localhost:8642` |
| `NAS_HOST` / `NAS_SHARE_ROOT` | `mount-library.sh` | **exits** via `${VAR:?}` |
| `NAS_MOUNT_ROOT` / `NAS_SHARES` / `HOME_NET_PREFIXES` | `mount-library.sh` | `~/nas` / three shares / `10.(33\|101\|148\|104)` |

The authoritative list is `commands/.local/share/dotfiles/required-env`, which
`dotfiles-local-env --check` reads — so this table cannot silently drift from what
the code actually needs.

Untracked, provision from the `.example` beside it: `docker/.docker/mcp/config.yaml`
(holds a Google app password), `gh/.config/gh/hosts.yml` (gh writes `oauth_token:`
into it whenever no OS keyring is available).

Out of tree entirely, in `~/.gitconfig.local` — `.gitconfig` includes it last:
the self-hosted GitLab `[credential]` block, and the work identity profile plus
its `includeIf`. `dirs.gitconfig` has **no catch-all `includeIf`**, so on a work
machine missing that block, repos under the work directory get no identity and
commits fail outright.

Three secrets were committed here before this rule existed and `gitleaks` scanned
past all of them across the full history. `.gitleaks.toml` now carries a custom
rule for each shape — `npmrc-authtoken`, `google-app-password`,
`bare-secret-export`. Don't remove one without a replacement.

## Worktrees, and why config needs a path seam

`~/dotfiles` on `master` is the **single deploy checkout** — every stow symlink
resolves there. Work happens in worktrees (`~/worktrees/dotfiles/<branch>`),
including background agent sessions, so that a half-finished edit is never live
on the running desktop. For a repo that *is* the running system, that insulation
is the point.

The consequence: a worktree edit is invisible to the running system until it is
merged and `~/dotfiles` pulls. Whether that blocks testing depends entirely on
whether the tool accepts a path override.

**Config we own resolves env first, fixed path as fallback.** Anything that can
only be read from a hardcoded `$HOME` path is a testability bug in our config,
not a reason to work in the live checkout — it means the component cannot be
exercised in isolation by a harness, a nested session, or CI.

Tools that already have a seam, and the flag to use:

| Tool | Test a worktree copy with |
| ------ | --------------------------- |
| quickshell | `qs -p <worktree>/quickshell/.config/quickshell/shell.qml` |
| tmux | `tmux -L <private-socket> -f <worktree>/tmux/.tmux.conf` |
| metapac | `metapac --config-dir <worktree>/metapac/.config/metapac` |
| nvim | `nvim -u <worktree>/nvim/.config/nvim/init.lua` |
| worktrunk | `wt --config <worktree>/worktrunk/.config/worktrunk/config.toml …` |
| workmux | `workmux add <name> --dry-run --config <worktree>/workmux/.config/workmux/config.yaml` |

`workmux --config` *merges with* the global config rather than replacing it, so a
worktree check reflects the merge, not the branch alone. `--dry-run` prints the
resolved worktree path, base, tmux target and hooks without touching anything —
use it to verify a layout change before merging.

No seam, so merge first and verify live: shell rc files (sourced from fixed `~`
paths at login) and Hyprland's own config discovery (`-c` applies at launch
only, `hyprctl reload` always re-reads `~/.config/hypr`).

`mise-scripts/visual-capture.sh` is the worked example — it defaults to the working
tree for both the shell entry point and the tmux config, so a capture shows what
is in the branch rather than what happens to be stowed.

### worktrunk and workmux share one layout

Both tools create worktrees, and both are configured to produce **the same path**:
`~/worktrees/<repo>/<branch>` (slashes in the branch become dashes). worktrunk gets
there via `worktree-path = "~/worktrees/{{ repo }}/{{ branch | sanitize }}"`,
workmux via `worktree_dir: ~/worktrees/{project}`.

The layout is repo-first because that is the only shape **both** can express:
workmux builds `<worktree_dir>/<handle>` and `worktree_dir` accepts just `~` and
`{project}`, so branch-first nesting is impossible there (upstream #148 shipped
only `{project}`; #161, which is exactly this, is open). worktrunk was the one
that moved. Keep the two templates in sync — changing one silently splits the
tree, and `wt list` / `wt-prune-branch-dir` only understand paths worktrunk made.

Differences that remain, deliberately:

- **Fetch before create.** worktrunk's `[pre-switch]` hook runs before the branch
  and worktree exist, so it refreshes `origin/*` first; pair with `-b origin/master`
  to branch from the fresh tip. workmux has no pre-create hook and never fetches —
  `base_branch: auto` resolves a *local* ref. Use the `wm` wrapper
  (`commands/.local/bin/wm`) instead of bare `workmux`: it intercepts `add` only,
  fetches, and passes `--base origin/<default>`. Everything else execs straight
  through. Opt out with `--base <ref>` or `WM_NO_FETCH=1`.
- **tmux naming.** worktrunk names sessions `<branch>-<repo>`; workmux uses its own
  `wm-<handle>`. Left divergent so it stays obvious which tool made a session.

## Stacked branches (git-spice)

Stacking is managed by **git-spice**. State lives in `refs/spice/data`, a ref in
the repo's common dir, so a stack is visible from every worktree of that repo.

**The binary is `git-spice`, never `gs`.** `/usr/bin/gs` is ghostscript —
required by okular, cups-pdf and texlive, and invoked as a bare `gs` by
imagemagick and matplotlib. `gs` exists only as an interactive shell alias
(`fish/conf.d/git-spice.fish`, `{bash,zsh}rc/18-git-spice`). **Scripts, hooks and
agents must spell it `git-spice`** — a shell alias does not exist in a
non-interactive shell, so `gs` in a script silently runs ghostscript.

### Agents: use git-spice instead of raw git/glab/gh

Raw `git` branch and push commands, `glab mr create`, and `gh pr create` leave
the stack metadata wrong: bases go stale, upstack branches are not restacked, and
MRs lose their navigation comments. Prefer:

| Instead of | Use | Note |
| ------ | ------ | ------ |
| `git checkout -b X` | `git-spice branch create X` | creates *and* tracks |
| `git commit` | `git-spice commit create` | commits, then restacks upstack |
| `git commit --amend` | `git-spice commit amend` | same, after amending |
| `git rebase <base>` | `git-spice upstack restack` / `stack restack` | never hand-rebase a tracked branch |
| `git checkout <branch>` | `git-spice branch checkout`, `up`, `down`, `top`, `bottom`, `trunk` | |
| `git push` | `git-spice branch submit` | pushes with lease and opens/updates the MR |
| `glab mr create`, `gh pr create` | `git-spice branch submit` / `stack submit` | idempotent: updates an existing MR rather than duplicating |
| `git pull` on trunk, deleting merged branches | `git-spice repo sync` | add `--restack` to rebase survivors |
| `git branch -d X` | `git-spice branch delete X` | retargets upstack branches |
| changing a branch's base | `git-spice upstack onto` / `branch onto` | |

Rules that matter for non-interactive use:

- **Always pass `--no-prompt`** in a script or an unattended agent session.
  git-spice prompts by default and will otherwise hang with no TTY. For submits,
  `--fill` derives title/body from commits; `--title`/`--body` set them
  explicitly.
- **Read-only stays raw.** `git status`, `git diff`, `git log`, `glab mr view`,
  `gh pr view` are all fine. Use `git-spice log short` (`ls`) for the stack.
- **Do not use the `merge` commands** — they are behind
  `spice.experiment.merge` and off here. Merge through the forge (or
  worktrunk/workmux), then `git-spice repo sync --restack` from the primary
  checkout to delete merged branches and retarget what is left.
- **Never `git push --force`** a tracked branch by hand; `branch submit` already
  force-pushes with a lease.
- **In a repo with no git-spice state and no `origin`**, the hook does not
  auto-init and plain git is correct. Do not force `repo init` on someone else's
  repo.

### Tracking is automatic, via a git hook

`init.templateDir` installs a `post-checkout` hook that auto-inits git-spice and
tracks the branch (`git/.config/git/hooks/post-checkout`, reached through a shim).
Hooks live in `$GIT_COMMON_DIR/hooks`, shared by every worktree of a repo, so
**any** worktree is stackable regardless of which tool created it — worktrunk,
workmux, or bare `git worktree add`. See `git/CLAUDE.md` for why the template dir
must be generated rather than pointed at the stowed path.

### One worktree per *stack*, not per branch

`up`/`down`/`branch checkout` do a real `git checkout`, and restack does a real
rebase — neither can touch a branch that is checked out in another worktree.
Verified on 0.31.2, and the failure mode is quiet rather than loud:

```console
$ git-spice upstack restack
WRN feat-c: checked out in another worktree (/…/work-wt), skipping
INF feat-b: restacked on feat-a
```

It **skips and carries on**, so that branch silently keeps a stale base and stays
`(needs restack)` in `git-spice ls` — which also annotates it `[wt: <path>]`. A
restack that reports success has not necessarily restacked the whole stack.
Upstream worktree-scoped filtering (abhinav/git-spice#1247) is still open.

So: cut one worktree for the stack, add branches inside it with
`git-spice branch create`, and navigate with `up`/`down`. If a stack branch does
end up in its own worktree, restack from *that* worktree to catch it.

When you *do* want a worktree for a branch that stacks on another, pass the
parent explicitly — `wm add foo --base parent-branch`. The default (`wm`'s
fetch-and-use-`origin/<default>`) is right for a stack *root* and wrong for
anything above it, which would otherwise be tracked as trunk-based.

## Machine-local config: the `.d/` pattern

Anything machine-specific — hostnames, gateway URLs, monitor serials, one API key
— lives **outside** the repo, and the repo carries only readers and examples.

This works because stow always runs with `--no-folding`: directories are real and
only files are symlinks, so an **untracked real file can sit inside a stowed
directory** and survives `stow -R` / `stow -D` (verified — stow only manages links
it owns).

**One canonical file:** `~/.config/dotfiles/local.env`, plain `KEY=VALUE`, no
quotes and no expansion, `chmod 600` (it holds `NEOVIM_API_KEY`). Three ways to
provision it per machine, in the order they apply:

| Command | Use when |
| ------ | ------ |
| `mise run setup:local-env` (`mise-scripts/gen-local-env.sh`) | fresh clone, nothing stowed yet |
| `dotfiles-local-env --template` | `commands` already stowed |
| `dotfiles-local-env --pull` | machine can reach Infisical |

`gen-local-env.sh` exists because of an ordering trap: `--template` copies the
example out of `~/.local/share/dotfiles`, which only exists **after** `commands` is
stowed — and stowing is the step that wants these values. The generator reads the
repo directly, so it works on a bare checkout. It builds the file from the
**manifest** rather than the example, so a variable added to `required-env` cannot
go missing, and it reports any drift between the two on stderr. It refuses to
overwrite an existing `local.env` without `--force`, and writes mode 600.

| Context | Reader (tracked, holds no values) |
| ------ | ------ |
| fish | `fish/.config/fish/conf.d/05-local-env.fish` |
| bash | `bash/.config/bashrc/05-local-env` |
| zsh | `zsh/.config/zshrc/05-local-env` |
| nushell | `nushell/.config/nushell/local-env.nu` |
| systemd user + Wayland session | `~/.config/environment.d/50-local.conf` → **symlink to `local.env`** |

The `environment.d` symlink is not optional cosmetics: **nvim reads
`OLLAMA_HOST` and `NEOVIM_API_KEY` via `vim.env`**, i.e. the environment of
whatever launched it. Started from a desktop entry or a systemd service with only
shell readers in place, the API key silently becomes the literal string
`"missing-NEOVIM_API_KEY"`. `dotfiles-local-env --check` warns when it is unwired.

**Two reserved slots, ordered opposite ways:**

- `05-local-env` — *values*, must load **early**. Configs that self-default use
  "set only if unset" (`fish/conf.d/hermes.fish`), so a reader running after them
  would never apply.
- `99-local` — *behaviour* overrides, must load **last** to win.

**Reserved names**, in both `.gitignore` and `.stow-local-ignore`: `local.env`,
`*.local`, `*.local.{lua,toml,fish}`, `NN-local*`. A local file therefore cannot be
committed by accident, and `mise-scripts/no-local-values.sh` is the second barrier.

`commands/.local/share/dotfiles/required-env` is the manifest — variable, whether
it is required, which consumer needs it. `dotfiles-local-env --check` reads it, so
the audit and the code cannot drift.

**Where no `.d` exists:** git has no directory include (keep `~/.gitconfig.local`),
and Hyprland's Lua config uses a guarded `dofile` of `monitors.local.lua` — that is
where monitor serials live, since `desc:` needs a serial to tell two identical
panels apart. `monitors.lua` publishes a `MON` alias table so the workspace layout
stays tracked and portable.

**Escape hatch:** bash and zsh both support
`~/.config/{bash,zsh}rc/custom/<same-filename>`, which *replaces* a stowed drop-in
outright (`[[ -f $c ]] && source $c || source $f`). Neither `custom/` dir exists
yet. That is the clean way to neutralise one stowed file on one machine — e.g. a
Linux-only drop-in on the Mac — with no repo change and no unstowing.

## Structure

- **Cross-platform**: `bash`, `fish`, `zsh`, `nvim`, `tmux`, `git`, `starship`, `yazi`, `lazygit`, `helix`, `zellij`, `wezterm`, `metapac`, `workmux`, `tuicr`, `gh`, `gh-dash`
- **macOS-only**: `ghostty`, `macos`
- **Linux-only**: `hyprland`, `rofi`, `konsole`, `kmonad`, `terminator`, `yakuake`, `brave-linux`, `xdg`
- **Shared base**: `base`

## Branches

- `master` — the single deploy checkout and only long-lived branch. Feature work
  happens in worktrees off `master` (see "Worktrees" above).

Platform divergence lives in per-host `metapac` tables and local-override files,
not a platform branch — the `macos` branch was retired.

## Hyprland Lua API

- Authoritative API stubs: `/usr/share/hypr/stubs/hl.meta.lua` (installed by `hyprland` package)
- Example config: `/usr/share/hypr/hyprland.lua`
- Consult stubs before guessing `hl.*` signatures or field names

## System packages (metapac)

The `metapac` package declares installed packages across machines. Replaced
`pug`, whose gist-syncing pacman hook had been broken since 2024. Config lives
at `~/.config/metapac/`; group files are the source of truth.

- **One config for every host.** Per-machine divergence lives in the
  `[hostname_enabled_backends]` / `[hostname_groups]` tables in `config.toml`,
  not in separate stow packages.
- **Backends:** `arch`, `brew`, `bun`, `cargo`, `flatpak`, `mise`, `uv` — enabled
  per host. Arch (`cachyos-fwd`): `arch`, `bun`, `cargo`, `flatpak`, `mise`, `uv`
  - groups `core`, `desktop-arch`. macOS (`example-macos-host.local`): `brew`,
  `cargo`, `mise`, `uv`, `bun` + groups `core`, `macos`.
  `[arch] package_manager = "paru"` is required so AUR installs stay behind the
  aur-policy gate. `npm` and `pipx` are deliberately disabled.
- **Group files:** `core.toml` (cross-platform), `desktop-arch.toml` (Arch),
  `macos.toml` (macOS). Moving a package `core` → `desktop-arch` is Arch-neutral
  (Arch enables both) and only drops it from the Mac's set — the safe way to make
  a `core` entry Arch-only.
- **One owner per tool class.** bun owns global JS CLIs, uv owns global Python
  CLIs, mise owns runtimes. Never enable `npm`/`pipx` alongside them — two
  backends claiming the same tool breaks sync/clean semantics.
- **`metapac clean` uninstalls everything not declared.** Always read its
  confirmation list; never script it with `--no-confirm` unless you have just
  read `metapac unmanaged` and the list is what you intend to remove.
- `desktop-arch.toml` was bootstrapped by declaring the full explicit package
  set as-is, so `unmanaged` reports clean. Pruning cruft is deliberate: delete
  the entry, then let `clean` uninstall it.
- Orphaned *dependencies* are invisible to metapac — it only tracks explicitly
  installed packages. Use `pacman -Qdtq` for those.
- **bun quirk:** `bun pm ls -g` colorizes even when piped and ignores
  `NO_COLOR`, so metapac's bun backend captures ANSI escapes into package names
  and then treats every bun package as unmanaged. Each shell defines a `metapac`
  wrapper setting `FORCE_COLOR=0` (see the `bun` drop-ins in `fish`/`bash`/`zsh`
  and `nushell/config.nu`). Drop those and `clean` will offer to remove your bun
  packages.

- **mise is per-host, not in `core`.** The two hosts share no mise tools, so each
  declares its own set (`desktop-arch.toml`: android-sdk, bun, zig; `macos.toml`:
  node, terraform, yarn, ktlint, tmux, bun). bun is declared under mise on both so
  the shared bun backend (hunkdiff, markdownlint-cli2 in `core`) has an interpreter.
- **metapac's mise backend can't manage `npm:`/`vfox:`-prefixed tools** (e.g.
  `npm:cavemen`, `vfox:…-gcloud`). `unmanaged` lists them but `sync` aborts with
  "invalid packages" if they're declared — a catch-22 with no ignore option in
  0.10.0. Keep mise blocks to plain registry tools; relocate the rest (gcloud →
  brew's `gcloud-cli`/`google-cloud-sdk`; cavemen → the bun backend).
- **macOS `brew`:** one merged list of formulae + casks (metapac installs/removes
  either by name). metapac itself is cargo-installed on macOS (declared in
  `macos.toml` `cargo`) since brew has no formula for it; on Arch it comes from AUR.
- **macOS config path (gotcha).** metapac reads its config from the OS-native dir,
  not XDG: on macOS that's `~/Library/Application Support/metapac/`, and it ignores
  `XDG_CONFIG_HOME`. The cross-platform stow package lands at `~/.config/metapac/`,
  so a no-flag `metapac` on macOS silently loads an *empty default* config (no
  backends → everything reads "clean"/"nothing to install" — a false pass). Per
  machine, bridge it once: `ln -s ~/.config/metapac ~/"Library/Application Support/metapac"`.
  (Linux uses XDG, so `~/.config/metapac/` is already correct there.)

- **Per-OS entries, not `core.toml`, when the backends differ.** `git-spice` is
  the worked example: AUR `git-spice-bin` in `desktop-arch.toml`, homebrew-core
  `git-spice` in `macos.toml`. No cargo crate exists (it is Go) and mise's
  registry has no entry. `gitleaks` is the same shape — brew on macOS, `extra/`
  on Arch — and is *also* pinned in `mise.toml` for the lint suite and CI. That
  duplication is deliberate: a system-wide git hook cannot depend on a project's
  mise toolchain.

Not managed by metapac, by design: nvim plugins (lazy.nvim + `lazy-lock.json`)
and Mason's LSP/formatter tools (declared via `mason-tool-installer`); and
**gh-dash**, which ships only as a `gh` extension (no brew formula, no
crates.io/npm, and metapac has no gh-extension backend). Bootstrap it per
machine with `gh extension install dlvhdr/gh-dash` — the `gh-dash/` stow package
supplies its `~/.config/gh-dash/config.yml` regardless. (`tuicr` *is* metapac-
managed via the cargo backend in `core.toml`.)

### Per-machine bootstrap, not committable

Steps that must be run once on each machine, since they write outside the repo or
need interactive auth:

```bash
gh extension install dlvhdr/gh-dash        # gh-dash (no package backend)
mise run hooks                             # lefthook -> .git/hooks, PER CLONE
mise run setup:git-spice                   # git-spice: template, forge URL, auth, hooks
```

**`mise run hooks` is per clone and nothing runs it for you.** This repo went a
long time without it, so `lefthook.yml`'s formatters (shfmt, stylua, taplo,
markdownlint) and its gitleaks command never fired on a commit — which is where
the formatting backlog came from. `setup:git-spice` step 7 now flags a clone that
is missing them.

One interaction to know (verified on lefthook 2.1.10): `lefthook install`
**renames an existing `pre-commit` to `pre-commit.old` and does not run it**, so
it displaces the global gitleaks hook installed via `init.templateDir`. Harmless
here because `lefthook.yml` runs the same gitleaks command itself; in a lefthook
repo that does *not*, installing lefthook silently drops the secret gate.

`mise-scripts/setup-git-spice.sh` (that task) is idempotent and does the checkable work
itself — regenerating `~/.local/share/git-template`, verifying no symlink survived
into it, and confirming `init.templateDir`, the forge URL and auth. For the three
things it cannot do it prints the exact command: the package install (needs sudo),
`git-spice auth login` (interactive), and the forge URL (belongs in
`~/.gitconfig.local`, never in this repo). Pass repos to retrofit hooks into:

```bash
mise run setup:git-spice -- --repos ~/src/a ~/src/b
```

**Order matters for auth:** set `spice.forge.gitlab.url` in `~/.gitconfig.local`
*before* `git-spice auth login`. Log in first and the token is keyed to
gitlab.com, and a self-hosted remote then reports `gitlab: not logged in`. The
config form is `[spice "forge.gitlab"]` + `url = …` — dots are illegal in a
variable name, and `[spice "forge"]` with `gitlab.url = …` makes **every** git
command fail with `bad config line`.

On macOS also `ln -s ~/.config/metapac ~/"Library/Application Support/metapac"`
(see the config-path gotcha above).

## Code review TUIs (tuicr + gh-dash)

- **tuicr** (`tuicr/`, cargo) — review TUI over local diffs and remote PRs/MRs;
  forge is auto-detected from the git remote, so one config serves GitHub and
  GitLab. Config sets `diff_view = "side-by-side"`.
- **gh-dash** (`gh-dash/`, gh extension) — GitHub PR/issue dashboard. Its
  `keybindings.prs` defines **`R`** = open the selected PR in tuicr
  (`tuicr pr {{.PrNumber}} --repo-url https://github.com/{{.RepoName}}` — builds
  the URL from `RepoName`, so no local checkout is needed).
- **tmux popups** (`.tmux.conf`, cwd-pinned via `-d '#{pane_current_path}'`):
  `prefix + P` → tuicr, `prefix + G` → `gh dash`. Both guarded by `command -v`.
  This reshuffle also moved: sidebar `A`→`b`, workmux diff `E`→`D`, nvim output
  `C-e`→`E`.

## Linting & CI

### `mise-scripts/` holds the repo's task scripts

Anything a `mise.toml` task shells out to lives in **`mise-scripts/`** (renamed
from `scripts/`), so a top-level directory of shell files cannot be mistaken for
config that gets stowed — every *other* top-level directory in this repo is a stow
package. Nothing in it is stowed, and no stow package should reach into it.

Three of them have a second caller by design — `no-local-values.sh` (lefthook +
CI), `shell-files.sh` and `yaml-files.sh` (both CI jobs). The directory name says
who *owns* them, not who may run them; when moving or renaming one, grep
`lefthook.yml` and `.gitlab-ci.yml` as well as `mise.toml`.

**Three** surfaces run the same class of checks and must be kept as close as
possible:

- **`mise.toml`** — the local toolchain + `mise run lint` tasks (shell, secrets,
  yaml, json, nu, fish, lua) and `mise run fmt` formatters. The full suite.
- **`.github/workflows/lint.yml`** — runs `mise run lint`, i.e. the same full
  suite. GitHub runners have no egress restriction, so mise installs the real
  toolchain. It additionally `apt install`s fish and lua-check, because
  `lint:fish` and `lint:lua` **self-skip when their tool is missing** and would
  otherwise report success while checking nothing.
- **`.gitlab-ci.yml`** — a deliberate *subset*: shellcheck + gitleaks + yamllint,
  via official tool-bundled images pinned by digest.

**GitLab diverges** because the self-hosted runner cannot reach
`api.github.com` (rate-limited) or `sigstore.dev`, so mise's aqua/ubi installs
fail there (see the `gitlab-runner-no-github-egress` memory). It works around
this with prebuilt images; the other two use mise directly.

That makes **GitHub the strictest gate** — a change can pass GitLab and still
fail on GitHub. Do not "fix" that by weakening the GitHub workflow.

**Pin by digest/SHA, never by tag.** GitHub Actions are pinned to full commit
SHAs and GitLab images to `@sha256:` digests, each with a comment naming the
release. A tag is mutable: `@v4` or `:latest` can be repointed at new code with
no commit here, which is both a supply-chain hole and a source of pipelines that
turn red without anything changing. Refresh an action with
`gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha`; an image with
`docker inspect --format='{{index .RepoDigests 0}}' <image>:<tag>` after a pull.

**Sync rule:** whenever you change one of these three files, evaluate the other
two and keep the shared gates aligned — same shellcheck flags/excludes/severity,
same gitleaks config, same allowlists. If you add a gate to `mise run lint`, it
reaches GitHub for free; decide separately whether GitLab can carry it, given
the GitHub/sigstore constraint, rather than letting the surfaces drift.

**Where a gate can be shared outright, share it.** `mise-scripts/shell-files.sh` and
`mise-scripts/yaml-files.sh` are the sole selectors for shellcheck and yamllint,
called by every surface that runs those gates, so which files get linted is
structurally identical rather than lists kept in step by hand. Both are POSIX
`sh` using only `find`/`grep` because the CI images ship **no git** —
`git ls-files` is not available there, which is why selection is path-based.

`yaml-files.sh` also excludes `docker/.docker/mcp/config.yaml` and
`gh/.config/gh/hosts.yml`. Those are gitignored and machine-provisioned: absent
in a fresh CI clone, present on a provisioned box, so a `find` that included
them would lint local state that can never be committed and make the local run
disagree with CI. Their committed `.example` siblings are linted normally.

It selects **by shebang, not by extension**. The previous `*.sh`/`*.bash` globs
silently skipped every extensionless command in `commands/.local/bin` and
`git/.local/bin` — eight scripts, including the `wt-*` helpers both worktree
tools depend on. Those files have no extension by design (they are on `PATH`),
so no glob can ever find them; a new one would have gone unlinted the same way.

Excluded: `*.sample` (git's vendored hook samples under
`git/.config/git/templates/hooks/`, not our code), plus
`__sdkman-noexport-init.sh` (zsh syntax) and `RofiEmoji.sh` (emoji data
mis-parsed as code). The exclusion used to be that whole templates directory;
it was narrowed to `*.sample` when our own hook shims moved in beside the
samples — they need linting like anything else.

**`lint:private` blocks re-introduction.** `mise-scripts/no-local-values.sh` fails if
content contains a *value* from `~/.config/dotfiles/local.env` (reading them at run
time, so no private string is ever committed as a denylist — only the variable
name is printed) or a generic private pattern (RFC1918, `/home/<user>`, `desc:`
serials). Runs in lefthook pre-commit, `mise run lint`, GitLab CI, and GitHub
Actions. CI has no `local.env`, which is why the pattern half exists; and CI is the
real enforcement since `--no-verify` skips the hook.

**`SCRUB_ORG` / `SCRUB_WORK_DIR` cover identifiers**, which neither half caught
before: an employer name is not a value any config consumes, and it is not private
by *shape* — no pattern can tell one company name from any other word. So they are
declared in `local.env` purely for the gate to recognise, and matched under looser
rules than a hostname: **case-insensitive, minimum 4 characters** instead of 8.
Both relaxations are load-bearing — a 7-letter company name never clears the
8-character floor, and the lowercased directory form of the same word never
matches case-sensitively. This was found the hard way: work session entries
re-entered `tmux/.config/sesh/sesh.toml` on master after the scrub branch was cut,
and every existing gate passed them.

Its limit is the same as the rest of half 1: **a machine with no `local.env`, and
CI, cannot enforce it.** The name is only known to machines that declare it, so
this catches re-introduction at the author's commit, not at the merge.

**A failure must not print what it caught.** Half 1 only ever prints the variable
name. Half 2 matches by pattern, so it can point at a location — but in `--all`
mode, the mode CI runs, it prints `path:line` and withholds the content: CI job
logs are a published surface once the mirror is public, and a gate that echoes the
offending line into them discloses exactly what it blocked. Staged mode still
prints the line, since that runs in the author's own terminal on content they just
wrote. Keep that asymmetry if you touch `check_pattern`.

**gitleaks now has a third surface:** the global `pre-commit` hook
(`git/.config/git/hooks/pre-commit`), on top of `mise run lint:secrets` and CI.
It stays aligned by *using the repo's own `.gitleaks.toml` when one exists*, so
each repo's allowlists apply, rather than carrying a copy. Scopes differ on
purpose — mise and CI scan the tree (`gitleaks dir .`), the hook scans staged
content (`gitleaks protect --staged`). In this repo `lefthook.yml` already owns
`pre-commit` and runs the same gitleaks command, so the template hook is skipped
here and does not double-run.
