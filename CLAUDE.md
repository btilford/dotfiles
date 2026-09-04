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
| `NAS_MOUNT_ROOT` / `NAS_SHARES` / `HOME_NET_PREFIXES` | `mount-library.sh` | `~/nas` / three shares / the built-in prefix list (values live in `local.env`; documented in `private-dotfiles`) |

The authoritative list is `commands/.local/share/dotfiles/required-env`, which
`dotfiles-local-env --check` reads — so this table cannot silently drift from what
the code actually needs.

Untracked, provision from the `.example` beside it: `docker/.docker/mcp/config.yaml`
(holds a Google app password), `hyprland/.config/hypr/lua/monitors.local.lua`,
`pi-agent/.pi/agent/models.json`, `quickshell/.config/quickshell/notifications.json`,
`aerc/.config/aerc/accounts.conf`.

`accounts.conf` is the one of those that **no structural gate can read** —
`lint:mcp-config` only parses JSON and YAML, and aerc's account file is INI. So
the example puts the password behind `source-cred-cmd` / `outgoing-cred-cmd`
calling `dotfiles-secrets --get`, which leaves the file with nothing secret in it
by construction rather than by discipline. aerc also refuses to start unless the
file is `0600`, so copy it with `install -m 600`.

Untracked with **no example, by design** — the tool writes them itself and there is
nothing to template: `gh/.config/gh/hosts.yml` (`gh auth login`, which stores an
`oauth_token:` there when no OS keyring is available) and
`glab-cli/.config/glab-cli/config.yml` (`glab auth login`, then
`mise run glab:config` for the rest of the settings). Everything about those two
tools that *can* be tracked already is — `gh/.config/gh/config.yml` and
`glab-cli/.config/glab-cli/aliases.yml` are stowed normally.

Out of tree entirely, in `~/.gitconfig.local` — `.gitconfig` includes it last:
the self-hosted GitLab `[credential]` block, and the work identity profile plus
its `includeIf`. `dirs.gitconfig` has **no catch-all `includeIf`**, so on a work
machine missing that block, repos under the work directory get no identity and
commits fail outright.

Three secrets were committed here before this rule existed and the scanner of the
day (`gitleaks`) read past all of them across the full history. `.betterleaks.toml`
now carries a custom
rule for each shape — `npmrc-authtoken`, `google-app-password`,
`bare-secret-export`. Don't remove one without a replacement.

## One checkout, and why config still needs a path seam

`~/dotfiles` is the **single checkout** — every stow symlink resolves there — and
branches are worked **in place**, not in worktrees. The same applies to
`~/private-dotfiles`.

The worktree model was dropped deliberately. It insulated the running desktop from
half-finished edits, but the cost turned out to be higher than the protection:

- **Nothing was ever verified where it runs.** A worktree edit is invisible to the
  live system until merged, so "test it" always meant "merge it first and hope" —
  and several bugs shipped that way, including a fish reader that errored on every
  shell start.
- **Two checkouts drift.** A shared script fixed in one copy and not the other is
  invisible until something disagrees; that happened to `stow-status.sh` within an
  hour of it existing.
- **Tooling assumes the deploy path.** Stow links, `git worktree list` ordering and
  the status task all resolve against the primary checkout, so a worktree needed
  special handling in each.

**The trade-off you are now taking on:** `git checkout <branch>` swaps live config
instantly, because the symlinks point at this working tree. A broken commit is a
broken desktop until you check out master again. So:

- Keep the checkout on `master` when you are not actively working.
- Prefer `mise run status` after any checkout that adds or removes files — a
  branch switch can leave a package partially stowed.
- For anything that can black-screen the session (Hyprland, quickshell), still
  verify with a path override before merging rather than by restarting the live
  component.

**Config we own resolves env first, fixed path as fallback.** That rule survives
the worktree removal and matters more now, not less: it is what lets a component be
exercised without pointing the live system at it.

| Tool | Test a branch copy with |
| ------ | --------------------------- |
| quickshell | `qs -p ~/dotfiles/quickshell/.config/quickshell/shell.qml` |
| tmux | `tmux -L <private-socket> -f ~/dotfiles/tmux/.tmux.conf` |
| metapac | `metapac --config-dir ~/dotfiles/metapac/.config/metapac` |
| nvim | `nvim -u ~/dotfiles/nvim/.config/nvim/init.lua` |
| worktrunk | `wt --config ~/dotfiles/worktrunk/.config/worktrunk/config.toml …` |
| workmux | `workmux add <name> --dry-run --config ~/dotfiles/workmux/.config/workmux/config.yaml` |
| local.env readers | `DOTFILES_LOCAL_ENV=<file> fish --no-config <script>` |
| `dotfiles-local-env` | `DOTFILES_SHARE_DIR=<repo>/commands/.local/share/dotfiles …` |
| scrub gate | `DOTFILES_SCRUB_PATTERNS=<file> ./mise-scripts/no-local-values.sh --all` |

`workmux --config` *merges with* the global config rather than replacing it, so a
check reflects the merge, not the branch alone. `--dry-run` prints the resolved
worktree path, base, tmux target and hooks without touching anything.

No seam, so verify live and be ready to revert: shell rc files (sourced from fixed
`~` paths at login) and Hyprland's own config discovery (`-c` applies at launch
only, `hyprctl reload` always re-reads `~/.config/hypr`).

`mise-scripts/visual-capture.sh` is the worked example — it defaults to the working
tree for both the shell entry point and the tmux config, so a capture shows what is
in the branch rather than what happens to be stowed.

**worktrunk and workmux stay installed and configured** — they are still the right
tool for *other* repos. They are simply not used for these two.

### worktrunk and workmux share one layout

Config for both is still maintained here, and both still get used — **for other
repos**. Nothing below applies to `~/dotfiles` or `~/private-dotfiles` any more.

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

### worktrunk's shell integration writes through the stow symlinks

`wt` needs a shell function, not just a binary — it returns `cd` and `exec` directives
through temp files. Four shells, four owners:

| Shell | Integration lives at | Owner |
| --- | --- | --- |
| zsh | `zsh/.zshrc` | this repo, tracked |
| bash | `bash/.bashrc` | this repo, tracked |
| fish | `~/.config/fish/functions/wt.fish` + `completions/wt.fish` | worktrunk; excluded |
| nushell | `~/Library/…/nushell/vendor/autoload/wt.nu` (macOS) | worktrunk; outside every stow target |

**The zsh and bash lines must stay in the rc file itself, never in a
`~/.config/{zshrc,bashrc}` drop-in.** `wt config shell install` reads only `~/.zshrc`,
`~/.bashrc` and `config.fish`; a drop-in is invisible to it. Both rc files are stow
symlinks into this repo, so an install that finds no line **appends one into tracked
source** — which is what dirtied `zsh/.zshrc` on 2026-08-31. Verified: with the line
deleted from a sandbox `~/.zshrc` and the drop-in copy present, `install --dry-run`
still proposes re-adding it.

The line is therefore repo-owned, and must stay byte-identical to what
`wt config shell init <shell>` documents, since that string is the installer's only
idempotency marker. Both files carried the line **twice** — rc file plus `50-custom` —
so every bash shell paid two `wt config shell init` subprocesses at startup.

`skip-shell-integration-prompt = true` in `worktrunk/.config/worktrunk/config.toml` is
the second half. worktrunk offers to install integration on any first run where it
reads as inactive, and accepting is what triggers the write; the flag is the answer
worktrunk itself records when you decline, committed once instead of re-given per
machine. Note it cannot be checked locally — worktrunk ignores unrecognised config keys
without a word, and the offer only appears on a TTY.

`wt config shell uninstall` is the documented reversal.

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

### Stacks live in the one checkout

Since **these two repos no longer use worktrees**, stacking is straightforward:
create branches with `git-spice branch create`, navigate with `up`/`down`, and
restack from wherever you are.

The hazard this replaces is worth remembering, because it applies to any *other*
repo you do use worktrees in: `up`/`down`/`branch checkout` perform a real
checkout, and restack a real rebase, so neither can touch a branch checked out in
another worktree. Verified on 0.31.2, and it fails quietly:

```console
$ git-spice upstack restack
WRN feat-c: checked out in another worktree (/…/work-wt), skipping
INF feat-b: restacked on feat-a
```

It **skips and carries on**, so that branch keeps a stale base and stays
`(needs restack)` in `git-spice ls` — annotated `[wt: <path>]`. A restack that
reports success has not necessarily restacked the whole stack. Upstream
worktree-scoped filtering (abhinav/git-spice#1247) is still open.

Stale base metadata bites the same way after a merge: a branch whose recorded base
was deleted fails `branch onto` with a conflict rather than a clear message. Fix
with `git-spice branch untrack` then `branch track --base master`.

## Files the repo does not own

A stow package may only contain files this repo writes end to end. Every other
file in a stowed directory — wallust output, an app's own preferences, a
tool-installed fish function — gets one of exactly three treatments. Getting this
wrong is not cosmetic: `mise run status` reported **31 conflicts across 10
packages** purely because there was no rule, and the advice it printed for them
was actively destructive.

| Tier | For | Mechanism |
| --- | --- | --- |
| **excluded** | the owner writes it, nothing needs a starting point | package `.stow-local-ignore` + `.gitignore`; untracked, unstowed |
| **frozen seed** | the owner writes it, but something breaks if it is absent | tracked + stowed + `skip-worktree`, listed in `.stow-frozen` |
| **repo-owned** | we write it, the app merely reads it | ordinary tracked file |

**Excluded** is the default; reach for **frozen** only when absence is fatal.
`hypr/lua/colors.lua` is the worked example: `lua/init.lua` does a bare
`require("lua.colors")`, so a machine with no `colors.lua` does not get default
colours, it gets a Hyprland config that fails to load. `ghostty/wallust.conf` is
the opposite — ghostty reads it if present — and it was tracked as an **empty
0-byte file**, so re-stowing that package would have blanked the terminal palette.

`skip-worktree` lives in `.git/index` and **is not committed**, so it cannot reach
another clone. `.stow-frozen` is the committed half; `mise run setup:frozen`
applies it, `-- --check` audits. To change a frozen file deliberately, unset the
bit first — otherwise the commit keeps the old content and says nothing.

**Tool-installed shell functions are the recurring case.** worktrunk installs both
`functions/wt.fish` and `completions/wt.fish`; the repo shipped a fork of the
first that had drifted a full feature behind (the live copy had a `COMPLETE`
recursion guard ours lacked, against a stale Homebrew completion re-entering the
stub). Racing a tool for a path it installs on every upgrade is unwinnable —
exclude it and let the tool own it.

### `--no-folding` does not protect a package that was already folded

Stow without `--no-folding` links a whole **directory** when every file under it
belongs to one package. Passing the flag later changes nothing for a package
already deployed that way, and nothing re-checks: `kmonad`, `fastfetch` and `gh`
sat folded for months under a rule that had supposedly prevented it.

A folded file is a live grenade, because **the file at the target is not a
symlink — its parent is**. So `~/.config/kmonad/us_ansi_100.kbd` looks like an
ordinary real file, `diff` against the repo shows no difference (it *is* the repo's
file), and deleting it deletes it **out of the repo**. That is exactly what
happened on 2026-08-12: 20 tracked files removed by following the "move the real
file aside and re-stow" advice, recovered with `git checkout`.

`stow-status.sh` now classifies this as **FOLDED** rather than `shadowed`, walking
each file's ancestors for a directory link into the package. The repair is
`stow -R --no-folding -t ~ <pkg>` and never a deletion.

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

### Secrets reach the shell from a tmpfs cache — never from a startup fetch

`local.env` holds **no credentials**, and **no shell calls infisical at startup** —
that second point is a hard constraint, not a preference: a network call in
`conf.d` hangs every new terminal when the gateway is unreachable or the wallet is
locked.

**Secrets ARE in the shell environment, and that is deliberate.** The earlier rule
("nothing reaches the environment automatically; `secrets-load` is never called for
you") was reversed: consumers that can only take an environment variable — clipborg
expands `${ENV}` at config load and hard-errors on an unset one; opencode, aider and
nvim are the same shape — do not work in a plain terminal otherwise, and wrapping
every entry point was not practical.

The constraint above survives the reversal because the fetch moved **off** the
shell's path rather than into it:

- `dotfiles-secrets.service` (systemd **user** unit) fetches **once at login** and
  writes `$XDG_RUNTIME_DIR/dotfiles/secrets.env` — tmpfs, dir 0700, file 0600,
  destroyed at logout. Not disk: no backup picks it up, nothing survives a reboot.
- Every shell drop-in does a **plain read of that local file**. No network, no
  infisical, no keyring, nothing that can block or prompt. A terminal opens at the
  same speed whether the gateway is up, down, or was never configured here.
- Other user units read the same file with `EnvironmentFile=-%t/dotfiles/secrets.env`
  (the leading `-` keeps a unit startable on a machine with no secrets at all).

The honest cost, stated plainly: secrets are now in the environment of every shell
and everything it spawns, not just a command you named. Same-user exposure only —
the mode bits stop other users, and root could read process memory regardless — but
it is strictly more surface than point-of-use was. `--run` remains preferable for
anything that does not need the variable ambiently.

**The unit no longer orders against the wallet unlock, and the history explains
why.** infisical's own CLI token lives in the Secret Service, and the store holding
it starts *locked*. Under Plasma `plasma-kwallet-pam.service` unlocks the wallet
from the password PAM captured at login. Under Hyprland nothing pulls that unit in,
so `autostart.lua` starts it by hand. Without an unlock the login fetch ran against
a locked store and silently produced no cache — observed 2026-08-03, where the first
symptom was `git-spice` failing hours later for an apparently unrelated reason.
Adding `Wants=`/`After=plasma-kwallet-pam.service` did not fix it reliably either
(2026-08-04: the unlock is racy). `dotfiles-secrets` now authenticates with a
machine identity when one is provisioned, so there is nothing to unlock and nothing
to order against. The unit's own comment carries the full account.

Two points survive that change:

- Ordering the unit from `autostart.lua` does **not** work for this consumer. The
  unit reaches `default.target` before Hyprland runs its first `exec_cmd`.
- **The Secret Service is pinned to ksecretd/kwallet, and that took a deliberate
  fix.** gnome-keyring ships the only activation file for `org.freedesktop.secrets`
  under `/usr/share`, and kwallet ships none, so gnome-keyring owned the name by
  default — a keyring `plasma-kwallet-pam.service` never unlocks. The `xdg` package
  now ships a user-level activation file naming ksecretd, and the gnome-keyring
  units are masked per machine. Check the owner with
  `busctl --user list | grep org.freedesktop.secrets`, and read `xdg/CLAUDE.md` for
  the two traps: the bus caches service files at startup, and a running ksecretd
  never reclaims the name once it has started without it.

**A failed fetch must fail the unit.** `SuccessExitStatus` covers **78**
(`EX_CONFIG`) only — "this machine has no infisical and no `INFISICAL_*`", which is
a normal state. It used to cover `1`, and since `die()` is the script's only exit
that made a locked wallet, an unreachable gateway and a logged-out CLI all report
success while writing nothing.

Checking token validity first is not a way around it. The CLI has no local expiry
check — `infisical token` only *renews* universal-auth tokens, over the network —
and the user token lives in the OS keyring, so even reading it can raise an unlock
prompt. A validity check is a network call plus a possible prompt, which is
strictly worse at startup than the cache it would replace.

So `commands/.local/bin/dotfiles-secrets` is the single accessor, and there are
four ways a secret reaches a consumer:

| Path | For | Lifetime |
| ------ | ------ | ------ |
| the session cache | any tool needing ambient env vars (clipborg, opencode, aider, nvim) | the login session |
| `--get NAME` | consumers we control, at point of use | one call |
| `--get --fresh NAME` | bypassing a stale cache after a rotation | one call |
| `--run -- CMD` | narrowing exposure back to one process | that process only |
| `secrets-load` | re-reading the cache into a running shell | until the shell exits |

`--run` is a thin wrapper over `infisical run`, which injects into the child and
nothing else.

**`--get` resolves environment → cache → network, in that order.** It used to go
straight to the network every time, which made it a *blocking ten-second stall* for
its most important caller: nvim's `ai.lua` fetches `NEOVIM_API_KEY` through
`vim.fn.system()`, which is synchronous. Measured 2026-08-03 — 10.0s (the full
timeout) versus 4ms reading the same value from the cache the login unit had
already written. The trade-off is staleness after a rotation, which is what
`--fresh` is for. The secret name is validated against `[A-Za-z0-9_]` before it
reaches the `eval` that reads the environment — that is a security boundary, not a
nicety.

**Every shell reads the cache at startup, and none of them fetch.** The drop-ins
are `06-secrets` (fish, bash, zsh) and `secrets.nu` (nushell); each reads
`$XDG_RUNTIME_DIR/dotfiles/secrets.env` if it exists and is a no-op if it does not.
In nushell that read is an `export-env` block — the only construct in a module that
runs at `use` time *and* whose env changes reach the caller's scope.

They also define `secrets-load` (re-read the cache; falls back to a live fetch only
if there is no cache) and `secrets-refresh` (restart the unit, then reload — what to
run after rotating a key). Keep the four in step: fish diverged for a while as the
only shell that auto-loaded, which left bash, zsh and nushell fetching over the
network in `secrets-load` and never touching the cache at all.

Every failure is printed to stderr *and* appended to
`~/.local/state/dotfiles/secrets.log`, with the reason distinguished — missing
binary, unconfigured, timed out, logged out, or no such secret. The log exists for
nvim, which swallows stderr; without it a failed fetch there would be a silent
missing key. Values are never logged. Calls are bounded by `timeout` and run with
`</dev/null`, so they can neither prompt nor stall a caller.

The old failure mode this replaces: `api_key = vim.env.NEOVIM_API_KEY or
"missing-NEOVIM_API_KEY"` evaluated at config load, which sent the literal string
`missing-NEOVIM_API_KEY` as a credential whenever nvim started outside a shell.

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

## Local inference: the gate is the endpoint, not the machine

Every AI consumer here — nvim, atuin, Continue — points at **one endpoint per
host**, and whether it runs at all is decided by *where that endpoint is*, not by
whose laptop it is.

The rule that replaced: `nvim/.../plugins/ai.lua` used to gate on
`DOTFILES_PROFILE == "personal"`, and the atuin shell drop-ins did the same. That
answers "whose laptop is this", which is the wrong question — what matters is
where the buffer text goes. It also made "work" mean "no AI at all", which ruled
out the case this section exists for: **an inference server running on the work
machine itself**, which sends nothing anywhere.

Three variables, in order of authority:

| Variable | Effect |
| --- | --- |
| `DOTFILES_AI=off` | kill switch. Nothing loads, whatever else is set. |
| `AI_GATEWAY` | this host's OpenAI-compatible endpoint. Falls back to `LITELLM_GATEWAY`. |
| `DOTFILES_PROFILE` | `personal` permits a **remote** gateway; anything else permits **loopback only**. |

So the homelab keeps working unchanged, a work laptop can run its own models,
and a work laptop cannot reach the homelab gateway. Absence of a gateway means
OFF, never "try somewhere else" — the same rule as the empty `ATUIN_*` variables
below. `ai.lua` matches loopback **literals** only: a hostname that resolves to
127.0.0.1 today is not a guarantee, and this decides whether work code leaves the
machine.

**This was not hypothetical.** This Mac had `DOTFILES_PROFILE=personal` in
`local.env`, so minuet and codecompanion were live and pointed at the homelab
gateway, and `OLLAMA_HOST` pointed at the homelab too — a plain `ollama pull` on
the laptop went there and timed out.

### Roles, not model names

`commands/.local/bin/ollama-role-aliases` creates `role/completion` and
`role/chat` as `ollama cp` copies, the local counterpart of the role aliases
`sync-litellm-models` gives the homelab. Consumers name the role; each host
decides the weights. **Re-run it after any `ollama pull`** — `ollama cp` copies a
manifest rather than pointing at one, so a re-pulled base tag silently leaves the
alias on the old weights.

`role/reasoning` is deliberately absent locally. The homelab points it at a 35B
and codecompanion's chat and agent strategies want it; a missing model is an
error at the point of use, whereas an alias quietly resolving to something a
quarter the size looks like it worked.

### `role/chat` has two hard requirements, and they eliminated the obvious pick

atuin AI runs with file tools and command execution enabled, so the chat model
must **call tools** and must **not think** — a thinking preamble is paid on every
query. Measured 2026-08-31, same prompt and tool schema:

| Model | Thinking | Tool call |
| --- | --- | --- |
| `qwen3:8b` | yes, cannot be disabled | — |
| `qwen2.5-coder:7b` | no | **none emitted** |
| `qwen2.5:7b` | no | correct |

qwen3's thinking cannot be switched off through an OpenAI-compatible endpoint,
which is the only kind atuin-ai-server speaks: `think: false` works on Ollama's
native `/api/chat` and is **ignored** on `/v1/chat/completions`,
`chat_template_kwargs.enable_thinking` is ignored too, `PARAMETER think false` is
not a Modelfile parameter, and `SYSTEM /no_think` does not reach the newer
template. The fix has to be model choice, not configuration.

That a *coder* model lost on tool calling is worth remembering: these are CLI
questions, so a coder looks like the obvious fit and answers them well — it just
cannot drive the tools.

### macOS specifics

- **The cask is `ollama-app`; the formula is `ollama`.** Different tokens, so no
  ambiguity — but the formula has a history of broken MLX on Apple Silicon.
- **Our LaunchAgent runs the server, not Ollama.app.** The app installs its own
  login agent and two servers cannot share 11434. `ollama serve` from the agent
  still resolves the MLX runners, which live beside the binary inside the bundle.
- **launchd is fine with a stowed symlink** — the systemd "never `systemctl
  enable` a stowed unit" hazard has no launchd analogue.
- **Env goes in the plist's `EnvironmentVariables`**, not `launchctl setenv`:
  setenv does not survive a reboot and cannot be committed.
- **`OLLAMA_HOST` must be a bare host with no port.** Three things read it — the
  server (bind address), the CLI (target), and gen.nvim (a hostname it formats
  `http://%s:%s` against 11434). Only the bare form is right for all three.
- **MLX is per model and is not automatic.** There are no `-mlx`/nvfp4 tags for
  the small models this host serves, so they run the GGUF path. Check `ollama ps`
  for `PROCESSOR = 100% GPU`.

## atuin: a personal/work split that is not an OS split

`atuin` (shell history, sync, AI) is the first package whose config varies by
**profile** — personal vs work — rather than by OS. It gets no second stow
package and no per-host file. atuin has no include mechanism, so the seam is the
environment, and three properties of it are load-bearing.

**1. The config file beats the environment.** atuin reads `ATUIN_<KEY>`, and
`ATUIN_<SECTION>__<KEY>` (double underscore) for nested keys — but a key present
in `config.toml` cannot be overridden by the env. Verified on 18.18.1. So every
profile-varying key is *deliberately absent* from the tracked
`atuin/.config/atuin/config.toml`; writing a "sensible default" for one there
silently switches its override off forever. The five: `sync_address`,
`auto_sync`, `ai.enabled`, `ai.endpoint`, `ai.model`. `ai.api_token` is a
credential and is in neither place.

**2. These do NOT go in `local.env`, and must not be added to `required-env`.**
An empty `ATUIN_*` value is not read as "unset" — it is parsed, it fails, and it
takes down settings loading for the whole binary:

```console
$ ATUIN_SYNC_ADDRESS= atuin status
Error: could not load client settings
Caused by: failed to deserialize: relative URL without a base: "" for key `sync_address`
```

`gen-local-env.sh` builds `local.env` from the manifest and emits an **empty
placeholder** for every variable in it, so listing these there would break every
atuin command on any freshly provisioned machine. They live in the untracked
`99-local` drop-in instead — which is anyway the repo's documented slot for a
value that differs *between* machines, and personal-vs-work is exactly that. The
tracked shell drop-ins still unset any set-but-empty `ATUIN_*` before init, so a
hand-written empty line cannot brick the shell either.

**3. In fish, no `conf.d` file can win Ctrl+R.** fish sources all of `conf.d`
*before* `config.fish`, whose first line sources `env.fish` → `fzf --fish |
source`, which binds Ctrl+R. So atuin's init lives in
`fish/.config/fish/keybinds.fish` (sourced late from `config.fish`), not in a
drop-in like every other integration in that package.

Two naming traps found on the way there, both worth remembering beyond atuin:

- **fish `conf.d` loads in byte order, and digits sort before letters.**
  `90-atuin.fish` ran *ahead* of `fzf.fish`, not after it. The numbered-drop-in
  intuition from `~/.config/bashrc` does not transfer — and by the same token the
  reserved **`99-local` slot does not load last in fish**, though it does in bash
  and zsh.
- **There are two fzf integrations here**, both binding Ctrl+R: the fisher plugin
  `fzf.fish` (`_fzf_search_history`) and upstream `fzf --fish`
  (`fzf-history-widget`). Both had to be dealt with. The plugin's binding is
  released properly via `fzf_configure_bindings --history=` — editing the
  plugin's own `conf.d` file would be reverted by `fisher update` — and atuin
  simply rebinds over the upstream one. fzf keeps Ctrl+T, Alt+C and its five
  Alt+Ctrl widgets.

bash and zsh are ordinary: `60-atuin` in each, numbered above `50-custom` because
that is where `fzf --bash` / `fzf --zsh` bind Ctrl+R. nushell **is** supported by
`atuin init nu` and is not wired up yet.

## Alt+e edits the command line, in every shell

fish binds Alt+e to `edit_command_buffer` as a **preset**, in every vi mode, so
that package carries no binding for it. The other three shells are made to match:
`bash/.config/bashrc/70-keybinds`, `zsh/.config/zshrc/70-keybinds`, and an
`open_command_editor_alt` entry in `nushell/.config/nushell/config.nu`. Each is
numbered or placed to load after fzf and atuin, the two integrations that bind
keys.

**The behaviour being matched is "edit, then return to the prompt" — not "edit,
then run".** fish, zle's `edit-command-line` and reedline's `openeditor` all hand
the edited text back for review. readline has no such function: its
`edit-and-execute-command` (Ctrl+X Ctrl+E, still bound) executes the moment the
editor exits. So bash rewrites the buffer itself through `READLINE_LINE` in a
`bind -x` function — which needs **bash ≥ 4.0**, and macOS ships 3.2 as
`/bin/bash`, hence the version guard and the degraded fallback there.

Two things this depends on, neither of them local to these files:

- **zsh's main keymap here is `viins`, not `emacs`.** Nothing sets `bindkey -v` —
  zsh selects vi mode when `$EDITOR` matches `*vi*`, and `00-init` exports
  `EDITOR=nvim`. All three keymaps are bound so the binding survives either mode.
- **On macOS the Option key must send Escape.** `ghostty/config` sets
  `macos-option-as-alt = true`; without it Option+e is a dead-key accent and no
  shell ever sees Alt+e.

## Structure

- **Cross-platform**: `atuin`, `atuin-ai-server`, `bash`, `fish`, `zsh`, `nvim`, `tmux`, `git`, `starship`, `yazi`, `lazygit`, `helix`, `metapac`, `workmux`, `tuicr`, `continue`, `ghostty`, `gh`, `gh-dash`
- **macOS-only**: `aerc`, `macos`
- **Linux-only**: `hyprland`, `rofi`, `konsole`, `kmonad`, `brave-linux`, `xdg`
- **Shared base**: `base`
- **Dormant**: `terminator`, `wezterm`, `yakuake`, `zellij`. Kept for the config,
  not in use on any machine, and none of the four is declared in metapac. Expect
  them to read `unstowed` in `mise run status` — that is the correct state, not a
  package waiting to be stowed.

`ghostty` was listed as macOS-only and is not: it runs on Linux, is installed on
the Arch box, and its package is stowed there. Only the `macos-option-as-alt`
note in the Alt+e section is macOS-specific, and it lives in that section.

**A package can be legitimately PARTIAL.** `ollama` carries a macOS LaunchAgent
plist alongside its cross-platform files, so on Linux it reports `2/3 linked`
forever. `mise run status -- -v` names the missing file, which is how to tell
that case from a package that genuinely needs re-stowing.

## Branches

- `master` — the only long-lived branch, and what the single checkout sits on when
  no work is in progress. Feature branches are created and worked **in place** in
  `~/dotfiles` (see "One checkout" above); no worktrees.

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
  per host, selected by a generic OS key (`arch`/`macos`) via `--hostname`, since
  metapac has no OS detection. Arch (`arch`): `arch`, `bun`, `cargo`, `flatpak`, `mise`, `uv`
  - groups `core`, `desktop-arch`. macOS (`macos`): `brew`,
  `cargo`, `mise`, `uv`, `bun` + groups `core`, `macos`.
  `[arch] package_manager = "paru"` is required so AUR installs stay behind the
  aur-policy gate. `npm` and `pipx` are deliberately disabled.
- **Group files:** `core.toml` (cross-platform), `desktop-arch.toml` (Arch),
  `macos.toml` (macOS). Moving a package `core` → `desktop-arch` is Arch-neutral
  (Arch enables both) and only drops it from the Mac's set — the safe way to make
  a `core` entry Arch-only.
- **One owner per tool class.** bun owns global JS CLIs, uv owns global Python
  CLIs, mise owns runtimes. Never enable `npm`/`pipx` alongside them — two
  backends claiming the same tool breaks sync/clean semantics. The one
  documented exception is **bun itself** — see "backend order is alphabetical"
  below.
- **Backend order is alphabetical, and a backend never waits for its
  interpreter.** metapac processes backends in enum order — `Arch`, `Brew`,
  `Bun`, `Cargo`, … `Mise` — so **a backend's interpreter cannot be declared in
  a backend that sorts after it.** bun was the worked example: it was declared
  under `mise` on both hosts on the theory that mise owns runtimes, but `Bun`
  runs before `Mise`, so on a machine without bun `sync` reached the bun backend
  first and died with a bare
  `command failed: "bun install --global …", error: Os { code: 2, kind: NotFound }`
  — ENOENT on the `bun` binary, not on any package. It aborts the whole run, so
  the mise backend never executed either: on the Mac, `mise ls -g` was empty and
  node/terraform/tmux/yarn/ktlint/gcloud had never once been installed. It only
  looked fine on the Arch box because bun had been installed there by hand.

  bun therefore comes from the **OS package manager** on both hosts —
  `extra/bun` in `desktop-arch.toml`'s `arch` block, homebrew-core `bun` in
  `macos.toml`'s `brew` block. Both sort before `Bun`, and brew's prefix is on
  `PATH` without mise shims (metapac spawns a bare `bun`, so a mise-installed
  one would also need `~/.local/share/mise/shims` on `PATH`, which
  `mise run metapac` does not provide). Apply the same reasoning to any future
  interpreter-style backend.
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

- **mise is almost entirely per-host.** Each host declares its own set
  (`desktop-arch.toml`: android-sdk, zig; `macos.toml`: node, terraform, yarn,
  ktlint, tmux, gcloud). bun is deliberately **not** among them — it is the
  interpreter for the shared `core` bun list, which the ordering note above
  explains it cannot be.

  **`java` is the one exception, and lives in `core.toml`.** mise replaced sdkman
  as the JDK owner (2026-08-14, when the sdkman init blocks came out of every
  shell), and nvim's jdtls config is cross-platform, so both hosts need it. It is
  pinned to the **LTS line** — `temurin-25`, not `latest`, which would follow
  every 6-month non-LTS release, and not a full version, which would pin the
  patch. Only one JDK can be declared: metapac keys a package by name, so mise's
  multi-version form has no representation. A second JDK is a per-machine
  `mise use -g java@temurin-21`; `nvim-java.lua` globs the mise installs dir and
  picks it up as an extra jdtls runtime with no config change.
- **metapac's mise backend can't manage `npm:`/`vfox:`-prefixed tools** (e.g.
  `npm:cavemen`, `vfox:…-gcloud`). `unmanaged` lists them but `sync` aborts with
  "invalid packages" if they're declared — a catch-22 with no ignore option in
  0.10.0. Keep mise blocks to plain registry tools; relocate the rest (cavemen →
  the bun backend). gcloud stayed on mise, under its short registry name
  `gcloud` rather than `vfox:…-gcloud`, and brew is no longer an owner for it.
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
  registry has no entry. The secret scanner is the same shape, and is *also*
  pinned in `mise.toml` for the lint suite and CI — that duplication is
  deliberate, because a system-wide git hook cannot depend on a project's mise
  toolchain. Since `betterleaks` replaced `gitleaks` (2026-08-24) the two OSes
  diverge further: brew has `betterleaks`, Arch has no repo package at all, and
  `aur/betterleaks` builds from git HEAD with a `pkgver()` that queries the
  GitHub API at build time — an unpinned source this repo does not take. On Arch
  it therefore comes from mise only: `mise use -g betterleaks@latest`, which is
  **not optional**, because the global `pre-commit` hook no-ops without the
  binary on PATH.

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
brew trust jetbrains/utils shopify/shopify gammons/tap rimio-ai/rimz  # macOS, or metapac sync aborts
mise run hooks                             # hk -> .git/hooks, PER CLONE (fallback)
mise run setup:frozen                      # skip-worktree bits, PER CLONE (.stow-frozen)
mise run setup:git-spice                   # git-spice: template, forge URL, auth, hooks
wt config shell install                    # fish + nushell only; the zsh/bash lines are tracked
glab auth login --hostname <host>          # then: mise run glab:config, PER CLONE
install -m 600 ~/.config/aerc/accounts.conf{.example,}   # then fill it in
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.dotfiles.ollama.plist  # macOS
mise run setup:ollama-roles                # role/* aliases; RE-RUN AFTER ollama pull
mise run setup:atuin-ai-server             # docker: atuin-ai-server on 127.0.0.1:8080
atuin hook install claude-code             # atuin agent hooks, one per agent
atuin hook install codex
atuin hook install pi

systemctl --user mask gnome-keyring-daemon.socket gnome-keyring-daemon.service
systemctl --user enable --now dotfiles-secrets.service
```

**`mise run glab:config` is per clone, not per machine, because of a permission
check.** glab refuses to read its config directory if anything in it is
group/world-readable — `aliases.yml has the permissions 644, but glab requires
600` — and it fails *before* auth, so every glab command dies, including the
credential helper git uses to push to the self-hosted host. `aliases.yml` is
stowed from this repo and **git records only the executable bit**, so a fresh
clone always lands at 644 and always hits this. The task now chmods it first;
the fix is invisible to git, which is also why it cannot be committed once and
forgotten.

**Both `systemctl --user` lines are easy to miss.** Masking gnome-keyring is what
holds `org.freedesktop.secrets` on kwallet; `xdg/CLAUDE.md` has the detail. And a
stowed unit is only **linked**, never enabled. `dotfiles-secrets.service` declares
`WantedBy=default.target`, but stow creates the symlink and nothing runs `enable`,
so the login fetch never fired on this laptop and no session cache existed at all.
`systemctl --user is-enabled dotfiles-secrets.service` prints `linked` when it is
not wired up.

**The atuin agent hooks write files this repo deliberately does not track.**
`atuin hook install <agent>` edits `~/.claude/settings.json`, `~/.codex/hooks.json`
and writes `~/.pi/agent/extensions/atuin.ts` — generated content, reinstalled
idempotently (it prints `already installed, skipping` and leaves the file alone),
so tracking a copy would just go stale. The hooks record every Bash tool call the
agent makes — command, cwd, exit code, duration — into the same history the shell
writes to. They need no server, which is why they are the one part of the atuin
setup the work machine gets in full.

**`mise run hooks` is no longer the load-bearing step, but it still exists.**
Under lefthook it was per clone and nothing ran it, so the formatters (shfmt,
stylua, taplo, markdownlint) and the secret scan never fired on a commit — which
is where the formatting backlog came from. hk (2026-08-24) removes that failure
mode: `git/.config/git/hk.gitconfig` registers hk once as a **config-based hook**
(`hook.hk-pre-commit.command` / `hook.hk-commit-msg.command`, git 2.54+), so any
repo carrying an `hk.pkl` runs its hooks with no per-clone install, and a repo
without one is a silent no-op. `mise run hooks` (`hk install`) remains the
fallback for a git older than 2.54, or a machine whose user gitconfig is not
ours; `setup:git-spice` step 7 checks for either.

Four interactions to know:

- **Config hooks do not displace `.git/hooks/*` — both run.** That is the
  opposite of `lefthook install`, which renamed an existing `pre-commit` to
  `pre-commit.old` and never ran it, silently displacing the global secret gate.
  Here the `init.templateDir` hooks (git-spice `post-checkout`, betterleaks
  `pre-commit`) keep working alongside hk.
- **Which means the two would scan staged content twice.** The template
  `pre-commit` hook therefore stands down when the repo has an `hk.pkl` that
  *names* betterleaks. Testing for the file alone would drop the gate the moment
  a repo adopted hk without a scanner step.
- **Never name a `[hook "…"]` section after a hook event.** `[hook "pre-commit"]`
  is a fatal ambiguity with `hook.<event>.enabled` and makes every git command in
  that repo fail. Hence `hk-pre-commit` / `hk-commit-msg`.
- **`hk install --global` is not used**, though it writes exactly these keys: it
  bakes an absolute, version-pinned mise path
  (`~/.local/share/mise/installs/hk/<version>/hk`) into `~/.gitconfig` — a stow
  symlink into this repo — so the path would be committed, break on the next
  `mise upgrade`, and be wrong on every other machine.
  `git/.local/bin/hk-git-hook` resolves hk at run time instead.

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

Three of them have a second caller by design — `no-local-values.sh` (hk + CI),
`shell-files.sh` and `yaml-files.sh` (both CI jobs). The directory name says who
*owns* them, not who may run them; when moving or renaming one, grep `hk.pkl` and
`.gitlab-ci.yml` as well as `mise.toml`.

**Three** surfaces run the same class of checks and must be kept as close as
possible:

- **`mise.toml`** — the local toolchain + `mise run lint` tasks (shell, secrets,
  yaml, json, nu, fish, lua) and `mise run fmt` formatters. The full suite.
- **`.github/workflows/lint.yml`** — runs `mise run lint`, i.e. the same full
  suite. GitHub runners have no egress restriction, so mise installs the real
  toolchain. It additionally `apt install`s fish and lua-check, because
  `lint:fish` and `lint:lua` **self-skip when their tool is missing** and would
  otherwise report success while checking nothing.
- **`.gitlab-ci.yml`** — a deliberate *subset*: shellcheck + betterleaks +
  yamllint, via official tool-bundled images pinned by digest.

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
same betterleaks config, same allowlists. If you add a gate to `mise run lint`, it
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
`git/.config/git/templates/hooks/`, not our code), plus `RofiEmoji.sh` (emoji
data mis-parsed as code). The exclusion used to be that whole templates directory;
it was narrowed to `*.sample` when our own hook shims moved in beside the
samples — they need linting like anything else.

**`lint:private` blocks re-introduction.** `mise-scripts/no-local-values.sh` fails if
content contains a *value* from `~/.config/dotfiles/local.env` (reading them at run
time, so no private string is ever committed as a denylist — only the variable
name is printed) or a generic private pattern (RFC1918, `/home/<user>`, `desc:`
serials, US phone numbers). Runs in the hk pre-commit and commit-msg hooks, `mise run lint`, GitLab CI, and GitHub
Actions. CI has no `local.env`, which is why the pattern half exists; and CI is the
real enforcement since `--no-verify` skips the hook.

**A third half covers identifiers:** `~/.config/dotfiles/scrub.patterns`, an
untracked list of extended regexes, one per line, matched case-insensitively.
Neither other half can catch an employer or client name — it is not a value any
config consumes, and it has no *shape* distinguishing it from any other word. This
was found the hard way: work sessions re-entered `tmux/.config/sesh/sesh.toml` on
master after the scrub branch was cut, past every gate.

Regexes rather than literals because one line then covers every spelling
(`acme|acme[- ]?corp|acmeco`) and can anchor to a path shape. Provision from
`scrub.example.patterns`; `dotfiles-local-env --check` reports when the file is
absent, since a gate that silently isn't armed is worse than no gate.

Two properties to preserve:

- **Only the line number is printed, never the pattern.** The pattern spells out
  the string being kept out — printing it on failure would disclose exactly what
  was blocked. Same discipline as half 1's variable names.
- **A pattern that does not compile fails the gate.** `grep` exits 2 on a bad
  regex, which is neither "found" nor "clean"; treated as a pass, a typo would
  switch that line off permanently and silently.

**It matches against `path:line:text`, so it catches file *names* too.** That is
how a kmonad keymap under `kmonad/.config/kmonad/` was found — the client name was
in the *filename*, and both the acceptance greps and a plain `grep -ri` over the
tree missed it because they only ever looked at file *contents*. Renamed to
`macos-work-2025.kbd`. When scrubbing, check names as well as content.

**Write about a scrubbed string without spelling it.** This paragraph originally
named that file in full, so the commit documenting the scrub re-introduced the
identifier into a published file — and the gate caught it on the next run. Say
"the client name", not the name.

Its limit is the same as half 1's: **a machine with no `scrub.patterns`, and CI,
cannot enforce it.** The names are only known where they are declared, so this
catches re-introduction at the author's commit, not at the merge.

**A failure must not print what it caught.** Half 1 only ever prints the variable
name. Half 2 matches by pattern, so it can point at a location — but in `--all`
mode, the mode CI runs, it prints `path:line` and withholds the content: CI job
logs are a published surface once the mirror is public, and a gate that echoes the
offending line into them discloses exactly what it blocked. Staged mode still
prints the line, since that runs in the author's own terminal on content they just
wrote. Keep that asymmetry if you touch `check_pattern`.

### Commit metadata leaks independently of file content

Two surfaces the file-content gates never saw:

**Commit messages.** Published exactly like a file, and previously ungated —
`pre-commit` runs before the message exists, so nothing looked at it. There is now
a `commit-msg` hook running `no-local-values.sh --message`, i.e. the same three
halves over the message body (git's own `#` comment lines stripped).

**Author identity, which local git config does not control.** `default.gitconfig`
sets the GitHub noreply address, and every locally-made commit is correct. But
**GitLab stamps merge commits with the account's own commit-email setting**, which
was the real personal address — so 58 commits on `master`, every one of them a
`Merge branch … into 'master'` made through the web UI, carry it. Nothing local
could have caught that: the wrong identity is applied server-side, after the push.

The fix is two-part and neither part is in this repo:

1. **Stop new ones:** set the GitLab account's *Commit email* to the **same
   GitHub noreply address the local profile uses**, so both forges produce one
   canonical author. Verify with `glab api user | jq .commit_email`.

   The obvious-looking choice — GitLab's own private `users.noreply` option — is
   **wrong here**: that address embeds the instance hostname
   (`{id}-{user}@users.noreply.<gitlab host>`), which is itself private
   infrastructure, so it trades a personal-email leak for a hostname leak on every
   merge commit. The gate would flag it.

   GitLab normally only accepts *verified* account emails, and a noreply address
   can never receive a confirmation mail. It works here because the instance sets
   `email_confirmation_setting = off` and the account is an instance admin, so the
   address can be added with `skip_confirmation`. On an instance without both,
   the fallback is to stop merging in the web UI — merge locally and push, and
   every commit carries the local identity.
2. **Remove existing ones:** `git filter-repo --mailmap`, using the mailmap in the
   private repo (`git/.mailmap`). It cannot live here — a mailmap must contain the
   address it maps *from*, so committing it would publish exactly what it removes,
   and the email gate would fail on it. This joins the Phase 2 rewrite.

`noreply@anthropic.com` appears in 191 commit messages (the `Co-Authored-By`
trailer) and is deliberately exempt — `no-reply@` and `users.noreply.*` addresses
exist to be published, so flagging them would fight the fix.

**The scanner is betterleaks since 2026-08-24.** Same author as gitleaks, MIT,
and drop-in on everything this repo relied on: it reads `.betterleaks.toml`
falling back to `.gitleaks.toml`, reads `.betterleaksignore` / `.gitleaksignore`,
honours `gitleaks:allow`, and keeps the fingerprint format — the ignore file
carried over untouched at the rename, and a full-history scan reported the same
outstanding four findings. It is pure Go (no Hyperscan/CGO), scans git in
parallel, and filters candidates with a BPE token-efficiency measure instead of
Shannon entropy.

**It has a third surface:** the global `pre-commit` hook
(`git/.config/git/hooks/pre-commit`), on top of `mise run lint:secrets` and CI.
It stays aligned by *using the repo's own config when one exists*, so each repo's
allowlists apply rather than carrying a copy. Scopes differ on purpose — the hook
scans staged content (`betterleaks git --staged`). In this repo `hk.pkl` owns
`pre-commit` and runs a betterleaks step itself, so the template hook stands down
here and does not double-run.

**Use `betterleaks git --staged`, never an inherited alias.** gitleaks' `protect`
and `detect` were deprecated in v8.19.0 and survived only as hidden aliases; the
same reasoning applies to anything betterleaks carries over for compatibility.
The global hook reaches every repo on the machine via `init.templateDir`, so it
is the worst place to leave a call that a future major can remove.

**Redaction is asymmetric, deliberately.** CI and `audit:secrets-*` pass
`--redact`; the local hooks do not. A CI job log is a published surface, so a
finding there must name the file and line without printing the value — the same
rule `no-local-values.sh` already follows in `--all` mode. A local hook runs in
the author's own terminal on content they just wrote, where seeing the value is
how you know what to fix.

**A secret shaped like config is the gap that actually bit.** `.betterleaks.toml`
carries `json-credential-value` and `yaml-credential-value` because a plaintext
UniFi password lived in an MCP `env` block in `opencode.json` for 15 months, and
every rule up to then required the literal word `export`. Both rules use
`secretGroup` so the reported (and redacted) secret is the value alone, and both
share one `[[allowlists]]` scoped with `targetRules` rather than keeping two
copies of the placeholder exemptions in step.

**`.betterleaksignore` is how known findings are silenced — never `paths`.** It pins
one finding in one commit by fingerprint, so it cannot over-reach the way a path
allowlist does. Rules for adding to it are in the file itself; the short version
is that a fingerprint goes in only after the credential is revoked, and never to
make a scan pass.

**Two audits, answering different questions.** `mise run audit:secrets-history`
is betterleaks over the full log — *does anything look like a secret*.
`mise run audit:secrets-live` is trufflehog with `--results=verified` — *is any of
it still live*, by calling the provider. Neither subsumes the other: trufflehog
has no detector for a self-hosted controller login and would not have found the
UniFi password, while a detection scan cannot tell a dead token from a live one.
Both are out of `lint`'s depends list because both need the network. betterleaks
does ship its own provider-shaped `--validation`; it is deliberately off on every
gate here, so detection never makes outbound calls.

**The structural gate is `lint:mcp-config`, and it is the only one that cannot be
fooled by an ordinary-looking credential.** `mise-scripts/config-secret-refs.py`
asserts that a value under a credential-named key — or anywhere inside an `env`
block — is a *reference*: `${VAR}`, `!printenv VAR`, `op://…`, or a bare
`VAR_NAME`. It never inspects the value's content, so a short lowercase device
password fails exactly as loudly as a 40-char token. Three entry points, one
implementation: the lint task (tracked content), hk (the files it selected), and
`mise run audit:mcp-config` (`--live`, this machine's untracked agent configs).
Not in the GitLab subset — it needs python, and that runner uses tool-bundled
images; GitHub runs the full suite.

**The only non-bypassable gate is server-side.** `--no-verify` skips every local
hook, and CI reports after the objects are already pushed and mirrored.
`server-hooks/pre-receive.d/betterleaks` is the free GitLab Self-Managed equivalent
of push protection; it is not installed by this repo, see that directory's README.

**`.betterleaks.toml` has NO `paths` allowlists, and must not gain any.** A path
allowlist matches in every scan mode, so silencing an untracked live config also
blinds a `betterleaks git` history scan to every secret that path once held. That is
a real regression that already bit: `glab-cli/config.yml`, `docker/mcp/config.yaml`
and `base/.npmrc` were path-allowlisted, a full-history scan read clean, and five
GitLab PATs plus a Nexus admin token and a Google app password sat undetected in
the log. The untracked-config problem is instead solved at the scan boundary:

- **`mise run lint:secrets`** scans **tracked content only** — `git archive HEAD`
  into a temp dir, then `betterleaks dir` — so untracked provisioned files (real
  tokens) are never seen and need no allowlist.
- **`mise run audit:secrets-history`** scans full history (`betterleaks git`) with the
  same allowlist-free config. It is the honest pre-rewrite audit and stays RED
  until `git filter-repo` has stripped the historical blobs. Expect it to fail
  until then.
- **CI's `betterleaks dir .`** is inherently tracked-only — a fresh clone has no
  untracked local files — so it needs no change and stays aligned.

Only line-target `regexes` allowlists are allowed (e.g. the public GPG
`signingKey`), because those match content, not a whole path across history.
