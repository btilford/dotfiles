# metapac

Declarative system packages across every machine, from one config. Group files
are the source of truth; [metapac](https://github.com/ripytide/metapac) installs
what's declared (`sync`) and reports/removes what isn't (`unmanaged` / `clean`).

Replaced `pug`, whose gist-syncing pacman hook had been broken since 2024.

## Layout

```
.config/metapac/
  config.toml              per-host enabled backends + groups (hostname tables)
  groups/core.toml         cross-platform: cargo, bun (installable on every host)
  groups/desktop-arch.toml Arch/CachyOS only: arch, flatpak, mise, cargo, uv, bun
  groups/macos.toml        macOS only: brew, mise, cargo, bun
```

One config for every host. Per-machine divergence lives in the
`[hostname_enabled_backends]` / `[hostname_groups]` tables in `config.toml`, not
in separate stow packages.

| Host | Backends | Groups |
|------|----------|--------|
| `cachyos-fwd` (Arch) | `arch`, `bun`, `cargo`, `flatpak`, `mise`, `uv` | `core`, `desktop-arch` |
| `example-macos-host.local` (macOS) | `brew`, `cargo`, `mise`, `uv`, `bun` | `core`, `macos` |

**Moving a package `core` → `desktop-arch` is Arch-neutral** (Arch enables both
groups) and drops it only from the Mac's set — the safe way to make a shared
entry Arch-only. The reverse (`core` → `macos`) makes it macOS-only.

## Setup on a new machine

1. **Install metapac.**
   - Arch: from the AUR (`paru -S metapac`) — `[arch] package_manager = "paru"`
     keeps AUR installs behind the aur-policy gate.
   - macOS: `cargo install metapac --locked` (no brew formula; `--locked` avoids
     a newer-rustc transitive pull — bump with `rustup update stable` if needed).
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

## Gotchas

- **macOS reads `~/Library/Application Support/metapac/`, not XDG.** metapac uses
  the OS-native config dir and **ignores `XDG_CONFIG_HOME`**. The stow package
  lands at `~/.config/metapac/`, so without the step-3 bridge symlink a no-flag
  `metapac` on macOS silently loads an *empty default* config — every backend
  reads "clean" / "nothing to install", a false pass. Linux uses XDG, so
  `~/.config/metapac/` is already correct there. (`--config-dir <path>` overrides
  per-invocation and is the worktree testing seam.)
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
