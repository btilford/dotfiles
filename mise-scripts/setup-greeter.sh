#!/usr/bin/env bash
# Install the greetd + ReGreet greeter from greeter/etc/greetd (mise run setup:greeter).
#
# stow only targets $HOME, so this copies into /etc with sudo. Idempotent: re-run
# after editing anything under greeter/ or the machine's monitors.local.lua.
#
# It does NOT switch the display manager unless asked, because a greeter that
# fails to start on the next boot leaves only a console:
#
#   mise run setup:greeter                 # install files, keep SDDM
#   mise run setup:greeter -- --enable     # also disable sddm, enable greetd
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
src=$repo/greeter/etc/greetd
theme=/var/lib/greetd-theme
pam=/etc/pam.d/greetd
x11_override=/etc/sddm.conf.d/99-x11-greeter.conf
enable=0

for arg in "$@"; do
  case $arg in
    --enable) enable=1 ;;
    *)
      echo "usage: $0 [--enable]" >&2
      exit 2
      ;;
  esac
done

say() { printf '==> %s\n' "$*"; }

# 1. Packages. Installing needs the user's own pacman/paru, so only report.
missing=()
for pkg in greetd greetd-regreet swaybg; do
  pacman -Q "$pkg" > /dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
  echo "missing packages: ${missing[*]}" >&2
  echo "  sudo pacman -S ${missing[*]}" >&2
  exit 1
fi

# 2. greetd config. Keep the package's original once, for reference.
say "installing /etc/greetd"
[[ -e /etc/greetd/config.toml.orig ]] || sudo cp -p /etc/greetd/config.toml /etc/greetd/config.toml.orig
for f in config.toml hyprland.lua regreet.toml; do
  sudo install -m 644 "$src/$f" "/etc/greetd/$f"
done

# 3. Machine-local monitor layout. The greeter cannot read $HOME, so copy it.
layout=$HOME/.config/hypr/lua/monitors.local.lua
if [[ -r $layout ]]; then
  say "copying monitor layout (MON.main pins the login window)"
  sudo install -m 644 "$layout" /etc/greetd/monitors.local.lua
else
  say "no $layout: greeter uses auto-detected monitors"
fi

# 4. Theme dir, owned by this user so greeter-theme-sync needs no root. Seed fixed
#    defaults only where nothing is there yet — never clobber a synced copy.
say "seeding $theme"
sudo install -d -o "$(id -u)" -g "$(id -g)" -m 755 "$theme"
[[ -s $theme/regreet.css ]] || install -m 644 "$src/regreet.css" "$theme/regreet.css"
if [[ ! -s $theme/wallpaper ]]; then
  seed=$repo/hyprland/.config/hypr/wallpaper_effects/.wallpaper_current
  [[ -s $seed ]] || seed=/usr/share/hypr/wall0.png
  install -m 644 "$seed" "$theme/wallpaper"
fi

# 5. Unlock kwallet at login, as /etc/pam.d/sddm does. `-` = skip if the module
#    is absent rather than fail the login.
if ! grep -q pam_kwallet5 "$pam"; then
  say "adding pam_kwallet5 to $pam"
  [[ -e $pam.orig ]] || sudo cp -p "$pam" "$pam.orig"
  sudo sed -i \
    -e '/^auth[[:space:]]\+include[[:space:]]\+system-local-login/a -auth       optional     pam_kwallet5.so' \
    -e '$a -session    optional     pam_kwallet5.so auto_start' \
    "$pam"
fi
grep -q 'auth.*pam_kwallet5' "$pam" || {
  echo "pam_kwallet5 auth line not added — edit $pam by hand" >&2
  exit 1
}

# 6. User path unit. Wire .wants by hand: `systemctl enable` on a stowed unit is
#    safe, but `disable`/`reenable` deletes the stow symlink itself.
units=$HOME/.config/systemd/user
if [[ -e $units/greeter-theme-sync.path ]]; then
  say "enabling greeter-theme-sync.path"
  mkdir -p "$units/default.target.wants"
  ln -sfn ../greeter-theme-sync.path "$units/default.target.wants/greeter-theme-sync.path"
  systemctl --user daemon-reload
  systemctl --user start greeter-theme-sync.path
  systemctl --user start greeter-theme-sync.service
else
  echo "greeter-theme-sync.path not stowed — stow -R --no-folding -t ~ commands" >&2
fi
[[ -s ${XDG_CACHE_HOME:-$HOME/.cache}/wallust/regreet.css ]] ||
  say "no wallust render yet: the greeter uses the fixed CSS until the next wallpaper change"

# 7. Display manager.
if ((enable)); then
  say "switching display manager: sddm -> greetd"
  sudo systemctl disable sddm.service
  sudo systemctl enable greetd.service
  if [[ -e $x11_override ]]; then
    say "removing $x11_override (SDDM-only workaround)"
    sudo rm -f "$x11_override"
  fi
  say "done. Reboot to use greetd. To revert: sudo systemctl disable greetd && sudo systemctl enable sddm"
else
  say "installed. SDDM is still the display manager. To switch: mise run setup:greeter -- --enable"
fi
