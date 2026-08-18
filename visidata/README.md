# visidata — terminal data explorer

Stow package. `stow --no-folding visidata` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.visidatarc` | `~/.visidatarc` |
| `.config/visidata/configy.py` | `~/.config/visidata/configy.py` (empty) |
| `.config/visidata/plugins/` | `~/.config/visidata/plugins/` (`keep.txt` placeholder) |

`.visidatarc` is Python, executed at startup:

```python
import plugins
options.clipboard_copy_cmd = 'wl-copy'
```

`wl-copy` rather than visidata's default (`pbcopy` on macOS, `xclip` on Linux) —
this is a Wayland session, and the X clipboard tool would copy into an XWayland
clipboard that no native app reads.

`import plugins` pulls in `~/.visidata/plugins/__init__.py`, which is **not**
tracked here. Nothing is installed there, so the import is a no-op on a fresh
machine; it exists so a per-machine plugin can be dropped in without editing the
tracked rc.

The whole file is Linux-shaped. On macOS, either set
`options.clipboard_copy_cmd = 'pbcopy'` in a local override or leave the package
unstowed.
