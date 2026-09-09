# macos — macOS-only bootstrap and window management

Stow package. macOS only. `stow --no-folding macos` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.aerospace.toml` | `~/.aerospace.toml` |
| `Library/KeyBindings/DefaultKeyBinding.dict` | `~/Library/KeyBindings/DefaultKeyBinding.dict` |
| `init.sh` | *(not stowed — a script you run once)* |

**AeroSpace** is the tiling window manager — the closest macOS gets to the
Hyprland layout on Linux, with workspaces and keyboard-driven focus rather than
Spaces. Read "AeroSpace mirrors the Hyprland keymap" below for the mapping.

**`DefaultKeyBinding.dict`** is a Cocoa text-system keybinding table, applied to
every AppKit text field on the machine. It is the only way to get Emacs/readline
motions into native apps; nothing about it is per-app.

## `init.sh` is a one-shot record, not an installer to run blind

It is a flat list of `brew install` lines from the original machine setup. Read it
before running:

- It has a typo on the first line (`brew isntall --cask ghostty`), which will fail
  and — because the script has no `set -e` — be skipped silently.
- Several formulae in it are stale (`exa` is unmaintained; `eza` replaced it).
- It predates [`metapac`](../metapac), which is now the declarative source of
  truth for packages on both platforms. `macos.toml` there is the list to trust.

Treat `init.sh` as history. Add packages to `metapac/.config/metapac/groups/macos.toml`.

## AeroSpace mirrors the Hyprland keymap

`.aerospace.toml` is written against `hyprland/.config/hypr/lua/`. It is not the
upstream sample. Treat the Hyprland Lua files as the source of truth. If a
binding changes there, change it here too.

The config is untested. It was written from the AeroSpace documentation, not from
a live run on a Mac.

### `alt` stands in for `SUPER`, and `alt` is the Command key

Hyprland uses `SUPER`, the key beside the space bar. Read `alt` in
`.aerospace.toml` wherever the Hyprland config says `SUPER`.

**`alt` in this file is the Command key, not the Option key.** This Mac maps
Option to Command and Command to Option in System Settings. That swap happens
below the event tap AeroSpace reads, so AeroSpace sees the remapped modifier:

| The file says | The user presses |
|---|---|
| `alt` | the Command key |
| `cmd` | the Option key |

The keyboard firmware records the same direction. `macos.dtsi` in the
`zmk-config` repository confirms it by test: ZMK sends `LALT` and macOS sees
Command.

Verify the direction before you rely on it. If a test contradicts it, swap `alt`
and `cmd` through the whole file and change nothing else.

Hyprland uses `SUPER + ALT` for the "move a window to a workspace" row. A Mac
keyboard cannot send that pair, so those bindings use `alt-ctrl`.

### Modes replace submaps

The Hyprland keymap is modal. A leader key opens a submap, the next key acts
inside it, and `escape` leaves. AeroSpace binding modes work the same way.

| Hyprland submap | Leader | AeroSpace mode | Leader |
|---|---|---|---|
| `open-cmd` | `SUPER + o` | `open` | `alt-o` |
| `system-cmd` | `SUPER + s` | `system` | `alt-s` |
| `window-cmd` | `SUPER + w` | `window` | `alt-w` |
| `window-swap` | `s` inside `window-cmd` | `swap` | `s` inside `window` |
| `workspace-cmd` | `SUPER + d` | `workspace` | `alt-d` |
| `focus-cmd` | `SUPER + f` | `focus` | `alt-f` |
| `time-cmd` | `SUPER + t` | `time` | `alt-t` |
| `notif-cmd` | `SUPER + n` | *(dropped)* | — |
| `timer-cmd` | `SUPER + m` | *(dropped)* | — |

`notif-cmd` and `timer-cmd` are dropped. Every binding in both calls the
quickshell IPC, `qs ipc call`. quickshell is Wayland software and does not run on
macOS.

The inner keys of each mode are the same letters as the Hyprland submap.

Three surfaces share one mnemonic set: the Hyprland submaps, the keyboard leader
in `macos.dtsi`, and these modes. The letters are `w` for window, `f` for focus,
`d` for desktop, and `s` for system. Do not add a fourth spelling.

### What AeroSpace cannot reproduce

AeroSpace is a tiling window manager, not a compositor. The list below records
each Hyprland behavior that has no equivalent. The config repeats each item in a
comment beside the place it would have gone.

**Layouts.** Hyprland has `dwindle`, `master` and `scrolling`, and
`lua/layout-auto.lua` switches between them on monitor hotplug. AeroSpace has
`tiles` and `accordion` only. The cycle binding becomes `layout tiles accordion`,
on `alt-slash`. Every master-area command is lost: swap with master, roll the
stack, and the master orientation controls.

**Decoration.** AeroSpace has `[gaps]` and nothing else. The gap values match
`lua/windows.lua`. Everything in `lua/decorations.lua` is gone: `rounding = 15`,
border width and colors, blur, glow, shadow, per-window opacity, dimming, and the
screen shader.

**Window rules.** `lua/windowrules.lua` is 236 lines. AeroSpace
`[[on-window-detected]]` can float a window and send it to a workspace, and
nothing else. Size, position, opacity, blur and animation rules are dropped. Most
of the Hyprland float list is Linux software, so only five rules carry over.

**Mouse.** AeroSpace has no mouse bindings. `SUPER` plus drag to move, `SUPER +
SHIFT` plus drag to resize, and `SUPER` plus scroll to change workspace are all
lost.

**Free window movement.** Hyprland nudges a floating window by 10 pixels on
`ALT + h/j/k/l`, and centers one on `c`. AeroSpace places floating windows itself
and offers neither command.

**Window groups.** `SUPER + g` toggles a Hyprland group. AeroSpace has no groups.

**Linux binaries.** These bindings call software that does not exist on macOS:

| Hyprland binding | Reason it is dropped |
|---|---|
| `SUPER + Escape` | `wlogout` power menu. macOS has no scriptable equivalent. |
| `SUPER + slash` | Keymap cheatsheet overlay (quickshell). |
| `SUPER + r`, `SUPER + CTRL + RETURN` | Application launcher. macOS uses `cmd-space`. |
| `SUPER + y`, `open-cmd` `v` | Clipboard history (clipborg, quickshell). |
| `SUPER + i`, `SUPER + SHIFT + N`, `SUPER + c` | Notification and clock drawers (quickshell). |
| `open-cmd` `e`, `u`, `i` | Emoji, glyph and icon pickers (rofi launcher). macOS has `ctrl-cmd-space`. |
| `system-cmd` `b` | Restart the status bar (waybar or quickshell). |
| `workspace-cmd` `w`, `t` | Wallpaper and theme choosers (wallust). |
| `XF86` media and brightness keys | macOS drives its own media row. |

These bindings have a macOS counterpart and are kept:

| Hyprland | macOS counterpart |
|---|---|
| `hyprctl reload` | `reload-config` |
| DPMS cycle, `loginctl lock-session` | `pmset displaysleepnow` |
| SpeedCrunch | Calculator |
| Mission Center | Activity Monitor |
| `focus class:...` | `open -a <application>` |
| `wl-copy` in `CopyDateTime.sh` | `pbcopy` |

### The keyboard leader depends on `ctrl-1` to `ctrl-5`

`macos.dtsi` in the `zmk-config` repository builds leader sequences in firmware.
Nine of them reach a desktop by sending `ctrl-1` to `ctrl-5`, `ctrl-left` or
`ctrl-right`:

| Sequence | Sends | Meaning |
|---|---|---|
| `f b` | `ctrl-1` | Focus the browser |
| `f t` | `ctrl-2` | Focus the terminal |
| `f i` | `ctrl-3` | Focus the IDE |
| `f n` | `ctrl-4` | Focus Notion |
| `f o` | `ctrl-5` | Focus Obsidian |
| `d 1` to `d 5` | `ctrl-1` to `ctrl-5` | Go to a desktop by number |
| `d n` | `ctrl-right` | Next desktop |
| `d p` | `ctrl-left` | Previous desktop |

Those sequences were written for native macOS Spaces. AeroSpace wins over native
Spaces, so every `ctrl-N` sequence would stop working the moment AeroSpace takes
over.

`.aerospace.toml` therefore binds `ctrl-1` to `ctrl-5`, `ctrl-left` and
`ctrl-right` to the matching AeroSpace workspaces. The firmware needs no change.
**Do not remove those seven bindings.** Removing one breaks the keyboard.

macOS must not eat those seven shortcuts first. Read "Native Spaces do not exist"
below for the setting to clear.

The workspace order is fixed, and `[[on-window-detected]]` rules keep each
application on its own workspace:

| Workspace | Application |
|---|---|
| 1 | Browser |
| 2 | Terminal |
| 3 | IDE |
| 4 | Notion |
| 5 | Obsidian |

The `focus` mode uses the same five letters and switches to the same five
workspaces, so `alt-f b` and the firmware sequence `f b` do the same thing.

AeroSpace workspaces keep their numbers rather than application names, so that
`alt-1` to `alt-0` still match `SUPER + 1` to `SUPER + 0` on Linux. The table
above is the meaning of each number.

Two firmware sequences still call native macOS window management, and both fight
AeroSpace:

| Sequence | Sends | Problem |
|---|---|---|
| `w f` | `ctrl-cmd-f` | Native fullscreen creates a native Space. |
| `w i` | `cmd-m` | Minimize hides the window from the tiling tree. |

Use `alt-w f` and `alt-w m` instead. Repointing the two firmware sequences is a
job for the `zmk-config` repository, which is a separate repository. Change
nothing in it from this package.

### Native Spaces do not exist

AeroSpace wins every conflict with native macOS Spaces. Treat native Spaces as if
they are not there. The AeroSpace guide states the same intent:

> The intended workflow of using AeroSpace workspaces is to only have one macOS
> Space [...] and don't interact with macOS Spaces anymore.

Do these once per machine. Without them, macOS handles the shortcut before
AeroSpace sees it, and the keyboard leader breaks.

1. Open Mission Control. Delete every desktop except one.
2. Open System Settings > Desktop & Dock > Mission Control.
3. Turn off "Displays have separate Spaces". The AeroSpace guide reports that
   macOS is more stable with it off.
4. Turn off "Automatically rearrange Spaces based on most recent use".
5. Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
6. Clear every "Switch to Desktop N" shortcut.
7. Clear "Move left a space" and "Move right a space".

Two AeroSpace commands are deliberately unused for the same reason.
`macos-native-fullscreen` creates a native Space, and `macos-native-minimize`
hides a window from the tiling tree. The `window` mode uses `fullscreen` on `f`
and `fullscreen --no-outer-gaps` on `m` instead.

`automatically-unhide-macos-hidden-apps = true` is set for the same reason. It
keeps `cmd-h` from taking a window out of the tiling tree.

### Direction keys are `hjkl`

`hjkl` means left, down, up and right in every surface here: the `vi` layer in
`kmonad/.config/kmonad/`, the Hyprland focus bindings, and AeroSpace. Focus and
move both use those four letters, in that order. Never make the arrow keys the
primary binding.

### Workspaces

Workspaces 1 to 10 keep their numbers, so `alt-1` to `alt-0` match `SUPER + 1` to
`SUPER + 0`. Workspaces 11 to 13 stay on `alt-f1` to `alt-f3`. On Linux they are
pinned to the XREAL glasses. The glasses are not used with the MacBook, so the
three workspaces are present but unpinned. macOS needs the `fn` key for the
function row unless the keyboard preference is changed.

AeroSpace workspaces are numbered here, so the Hyprland names (`Main`, `CLI1`,
`RefLeft`, and the rest) are lost. Workspaces 1 to 5 carry the meaning listed in
"The keyboard leader depends on `ctrl-1` to `ctrl-5`" above.

`[workspace-to-monitor-force-assignment]` is present but commented out. The
MacBook usually runs one display, where every assignment is a no-op. Uncomment it
to use it. Use only the patterns `main` and `secondary`. Never write a monitor
name or a panel serial into this file. This repository is public.

### Verify the window rules on the machine

`[[on-window-detected]]` matches on the application bundle identifier. The nine
identifiers in the file were not verified on a Mac. The IDE has no rule, because
its identifier differs per product. List the real ones with:

```sh
aerospace list-apps
```

## Also needed on a Mac

metapac reads its config from `~/Library/Application Support/metapac/`, not XDG,
and silently loads an **empty default** otherwise — every backend disabled, so
everything reads "clean". Bridge it once per machine:

```sh
ln -s ~/.config/metapac ~/"Library/Application Support/metapac"
```
