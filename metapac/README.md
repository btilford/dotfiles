# metapac

Declarative system packages across every machine, from one config. Group files
are the source of truth; [metapac](https://github.com/ripytide/metapac) installs
what's declared (`sync`) and reports/removes what isn't (`unmanaged` / `clean`).

Replaced `pug`, whose gist-syncing pacman hook had been broken since 2024.

## Layout

```text
.config/metapac/
  config.toml              per-host enabled backends + groups (OS-key tables)
  groups/core.toml         cross-platform: cargo, bun (installable on every host)
  groups/desktop-arch.toml Arch/CachyOS only: arch, flatpak, mise, cargo, uv, bun
  groups/macos.toml        macOS only: brew, mise, cargo, bun
  groups/wsl-ubuntu.toml   WSL Ubuntu/Debian only: apt, mise, cargo
```

One config for every host. Per-machine divergence lives in the
`[hostname_enabled_backends]` / `[hostname_groups]` tables in `config.toml`, not
in separate stow packages.

| Host | Backends | Groups |
|------|----------|--------|
| `arch` (Linux/Arch) | `arch`, `bun`, `cargo`, `flatpak`, `mise`, `uv` | `core`, `desktop-arch` |
| `macos` (macOS) | `brew`, `cargo`, `mise`, `uv`, `bun` | `core`, `macos` |
| `wsl-ubuntu` (WSL Ubuntu/Debian) | `apt`, `bun`, `cargo`, `mise` | `core`, `wsl-ubuntu` |

**Moving a package `core` → `desktop-arch` is Arch-neutral** (Arch enables both
groups) and drops it only from the Mac's set — the safe way to make a shared
entry Arch-only. The reverse (`core` → `macos`) makes it macOS-only.

## Setup on a new machine

1. **Install metapac.**
   - Arch: from the AUR (`paru -S metapac`) — `[arch] package_manager = "paru"`
     keeps AUR installs behind the aur-policy gate.
   - Arch, **before the first sync**: enable upstream aurscan's signed `[manticore]`
     repo. `aurscan-bin` left the AUR, and metapac validates every package before
     installing any, so without the repo the whole sync aborts with
     `packages for the Arch backend are invalid: {"aurscan-bin"}`. Steps are
     upstream's ([aurscan#install](https://github.com/manticore-projects/aurscan#install)):

     ```sh
     curl -fsSL https://manticore-projects.github.io/aurscan/aurscan.gpg | sudo pacman-key --add -
     sudo pacman-key --lsign-key 61E73AA7539ACB261ABCF10C188331308EF56D11
     grep -q '^\[manticore\]' /etc/pacman.conf ||
       printf '\n[manticore]\nSigLevel = Required DatabaseOptional\nServer = https://manticore-projects.github.io/aurscan/$arch\n' |
       sudo tee -a /etc/pacman.conf
     ```

     If `aurscan-git` is installed, remove it first (`sudo pacman -R aurscan-git`):
     it is an unrelated ClamAV wrapper claiming the same `/usr/bin/aurscan`.
   - Arch, **before the first sync**: install every enabled backend's binary
     from the OS repos — `sudo pacman -S --needed flatpak bun uv rustup` then
     `rustup default stable`. metapac queries *all* backends before installing
     anything, so a fresh machine dies on the first missing one (`flatpak
     remotes … NotFound`); a mise-shimmed `uv` doesn't count, because
     `mise run metapac` puts `/usr/bin` first.
   - Arch: a first sync clones ~100 AUR PKGBUILDs at once and aur.archlinux.org
     answers some with `Recv failure: Connection reset by peer`. Re-run, or
     pre-clone them serially into `~/.cache/paru/clone` — paru then only fetches.
   - macOS: `cargo install metapac --locked` (no brew formula; `--locked` avoids
     a newer-rustc transitive pull — bump with `rustup update stable` if needed).
   - WSL Ubuntu: `cargo install metapac --locked`, after the WSL bootstrap below.
2. **Stow.** `stow --no-folding metapac` from `~/dotfiles` (one package at a time
   with `--no-folding`, per repo rules).
3. **macOS only — bridge the config path (REQUIRED, see gotcha below):**

   ```sh
   ln -s ~/.config/metapac ~/"Library/Application Support/metapac"

   ```

4. **Set the hostname rows** in `config.toml` if this is a new host (`hostname`
   shows the name metapac detects; `metapac --hostname <name>` overrides for tests).
5. **Bootstrap** an empty group: `metapac unmanaged >> groups/<host>.toml`, then
   split entries into the right group. Declare what's installed so `unmanaged`
   reports clean and `clean` is a no-op; prune deliberately later.
6. **Verify:** `metapac unmanaged` silent, `metapac sync` reports nothing missing,
   **before** ever running `metapac clean`.

### WSL Ubuntu bootstrap

`metapac-hostname-key` returns `wsl-ubuntu` when `/proc/sys/kernel/osrelease`
says `microsoft` and `/etc/os-release` is Ubuntu/Debian. Another WSL distro gets
an unkeyed `wsl-<id>`, so metapac no-ops. The apt backend runs `sudo apt`, so run
it interactively.

Four things must exist before the first `metapac sync`, because no backend can
provide them in time:

```sh
sudo apt install -y build-essential pkg-config libssl-dev curl git stow
curl -fsSL https://sh.rustup.rs | sh -s -- -y        # cargo backend
curl -fsSL https://mise.run | sh                     # mise backend
curl -fsSL https://bun.sh/install | bash             # bun backend: no Ubuntu
                                                     # package; Apt/Bun run before Mise
cargo install metapac --locked
mise use -g github:abhinav/git-spice                 # not a registry short name,
                                                     # so metapac can't declare it
```

Then stow `commands` + `metapac`, open a new shell, and run `metapac sync`.

- **Git must be ≥ 2.54, and Ubuntu 26.04 ships 2.53.** `git/hk.gitconfig`
  registers hk through config-based hooks (2.54+). Older git ignores them
  silently, and `hooks/pre-commit` stands down in any repo whose `hk.pkl` runs
  betterleaks, so those repos get **no secret scan at all**. Install from the
  PPA first: `sudo add-apt-repository ppa:git-core/ppa && sudo apt install git`.
- **The `apt` group starts with `apt-mark showmanual`** from the fresh install.
  Run `metapac unmanaged` before any `clean`, because anything installed by hand
  since then is on the removal list.

## Gotchas

- **macOS reads `~/Library/Application Support/metapac/`, not XDG.** metapac uses
  the OS-native config dir and **ignores `XDG_CONFIG_HOME`**. The stow package
  lands at `~/.config/metapac/`, so without the step-3 bridge symlink a no-flag
  `metapac` on macOS silently loads an *empty default* config — every backend
  reads "clean" / "nothing to install", a false pass. Linux uses XDG, so
  `~/.config/metapac/` is already correct there. (`--config-dir <path>` overrides
  per-invocation and is the worktree testing seam.)
- **Homebrew's tap-trust gate aborts the whole sync, per machine.** A formula
  from a third-party tap now needs explicit trust, and brew exits non-zero
  without it — which metapac treats as a failed command and stops on, so one
  untrusted tap blocks every remaining backend:

  ```console
  Error: Refusing to load formula jetbrains/utils/kotlin-lsp from untrusted tap
  Error: 0: command failed: "brew install kotlin-lsp"
  ```

  Four declared packages come from taps: `kotlin-lsp` (jetbrains/utils),
  `shopify-cli` (shopify/shopify), `slk` (gammons/tap), `rimz` (rimio-ai/rimz).

  ```sh
  brew trust jetbrains/utils shopify/shopify gammons/tap rimio-ai/rimz
  ```

  Trust is machine state, not repo state — it cannot be committed, so this is a
  per-machine bootstrap step like the config-dir bridge above. `brew trust
  --formula <tap>/<name>` is the narrower form if you would rather not trust
  everything a tap ships later. Do **not** set `HOMEBREW_NO_REQUIRE_TAP_TRUST=1`
  to make it go away: that disables the check for every tap on the machine.

- **`metapac clean` uninstalls everything not declared.** Always read its
  confirmation list; never `--no-confirm` blind unless you've just read
  `metapac unmanaged` and the list is exactly what you intend to remove.
- **mise `npm:` / `vfox:` tools can't be managed** (metapac 0.10.0). `unmanaged`
  lists them but `sync` aborts with "invalid packages" if they're declared —
  no ignore option. Keep mise blocks to plain registry short names; relocate the
  rest (e.g. `gcloud` via its short mise name, not `vfox:…`; npm CLIs → the bun
  backend).
- **bun ANSI bug.** `bun pm ls -g` colorizes even when piped and ignores
  `NO_COLOR`, so metapac's bun backend captures escape codes into package names
  and treats every bun package as unmanaged. Each shell defines a `metapac`
  wrapper forcing `FORCE_COLOR=0` (see the `bun` drop-ins in `fish`/`bash`/`zsh`
  and `nushell/config.nu`). Non-interactive callers must set `FORCE_COLOR=0`
  themselves. Drop the wrapper and `clean` will offer to remove your bun packages.
- **One owner per tool class.** bun owns global JS CLIs, uv owns global Python
  CLIs, mise owns runtimes. `npm` and `pipx` are deliberately disabled — two
  backends claiming the same tool breaks sync/clean semantics.
- **Orphaned *dependencies* are invisible** — metapac only tracks explicitly
  installed packages. Use `pacman -Qdtq` (Arch) / `brew autoremove` (macOS) for
  those. The brew backend tracks `--installed-on-request` formulae + all casks,
  merged into one list; it installs/removes either by name via `brew remove`
  (no `--force`/`--zap`).

Not managed by metapac, by design: nvim plugins (lazy.nvim + `lazy-lock.json`)
and Mason's LSP/formatter tools (declared via `mason-tool-installer`).
