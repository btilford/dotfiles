# macOS handoff — after the `macos` branch retirement

**Temporary doc.** Delivered via `master` because the `macos` branch is gone.
Delete this file once the macOS machine is reconciled.

## What changed

The long-lived `macos` platform branch was **deleted** (2026-07-17). Every unique
change it carried already lives on `master` **except** its `tmux/.tmux.conf` fork,
which only *removed* Linux-specific bits. Master's tmux config is now cross-platform
via `if-shell` guards + per-machine override files, so macOS runs `master` directly.

## Do this on the macOS machine

1. **Get on master, drop the fork.**
   ```sh
   cd ~/dotfiles
   git fetch -p                 # prunes the deleted macos + feature branches
   git checkout master
   git pull --ff-only
   git branch -D macos          # local copy is now dead; delete it
   ```

2. **Re-stow tmux** (config content flows through the symlink; only needed if the
   link is missing):
   ```sh
   stow --no-folding -R tmux
   ```

3. **Recreate your macOS-only tmux prefs as uncommitted local overrides.**
   These replace what the old branch hard-coded. Two slots (order matters — see the
   comments in `tmux/.tmux.conf`):

   - **PRE** `~/.tmux.local.conf` — loads before plugins; set options + plugin
     `@options` here:
     ```tmux
     # macOS: wrap pane navigation at edges (old macos-branch preference)
     set -g @tmux-nvim-navigation-cycle true
     ```
   - **POST** `~/.tmux.local.post.conf` — loads after tpm; only for overriding what
     plugins themselves set (bindings/status/colors). Probably empty.

   Neither file is tracked — `git status` will not show them.

4. **Things now handled automatically (no action):**
   - `clipborg` keybind (`prefix`-less `v` popup) is guarded by `command -v clipborg`
     — absent on macOS, so it's silently skipped. Install clipborg if you want it.
   - The catppuccin plugin file loads are guarded by `[ -r <file> ]`, so the plugin's
     version/layout difference on macOS no longer errors at startup.

5. **Verify tmux parses:**
   ```sh
   tmux -L cfgcheck -f ~/.tmux.conf new-session -d true && \
     tmux -L cfgcheck show -g @tmux-nvim-navigation-cycle && \
     tmux -L cfgcheck kill-server
   ```

## Ongoing rule

No more `macos` branch. Machine-specific config goes in an `if-shell` guard in the
committed file, or in the uncommitted local-override files (mirrors fish
`conf.d/local.fish`). macOS stays current by **pulling master**, never merging back.

## Cleanup

When done, remove this file:
```sh
git rm macos-handoff.md && git commit -m "docs: drop macos-handoff (reconciled)" && git push
```
