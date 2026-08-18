# docs — images embedded in the package READMEs

**Not a stow package.** Nothing here is symlinked into `$HOME`.

```text
docs/images/quickshell-bar.png            top bar (cropped)
docs/images/quickshell-launcher.png       launcher, drun mode
docs/images/quickshell-session.png        session / power overlay
docs/images/quickshell-popup.png          notification popup (cropped)
docs/images/quickshell-notifications.png  notification history drawer (cropped)
```

## Where these come from — and where they do NOT go

Every image is produced by the headless capture harness, never by screenshotting
the live desktop:

```sh
mise run screenshots -- --no-motion --scene <name>
```

Output lands in `build/visuals/`, which is **gitignored scratch**. The long-term
visual history — every batch, with motion clips, indexed by an append-only ledger
— lives in the notes vault at `$DOTFILES_SCREENSHOT_ARCHIVE`, not in this repo.
See [`mise-scripts/visuals/README.md`](../mise-scripts/visuals/README.md).

This directory is the **third** thing: a handful of current stills that the
package READMEs embed. Keep it that way. It is not an archive, and a new capture
should replace a file here rather than accumulate beside it.

## Before adding an image

This repo is published to a public GitHub mirror, and **an image is not covered by
any of the three scrub gates** — `no-local-values.sh` reads text, not pixels. A
screenshot can leak a hostname in a bar module, a path in a title bar, a real
notification body, or a client name in a window list, and none of it will be
caught before the push.

So: capture headlessly (the nested session has no real notifications, no real
workspaces and no real windows), then **look at the image** before committing it.

## Refreshing

```sh
mise run screenshots -- --no-motion --scene bar --scene drawer --scene modal
magick build/visuals/bar-<ts>.png -crop 1920x40+0+0 +repage docs/images/quickshell-bar.png
cp build/visuals/drawer-<ts>.png docs/images/quickshell-launcher.png
oxipng -o 4 --strip safe docs/images/*.png
```

`oxipng` is lossless and optional; without it the files are roughly twice the size.
