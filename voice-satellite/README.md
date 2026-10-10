# voice-satellite — Home Assistant voice satellite (Linux Voice Assistant)

Stow package. `stow --no-folding voice-satellite` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/containers/systemd/linux-voice-assistant.container` | `~/.config/containers/systemd/…` (podman quadlet → `linux-voice-assistant.service`) |
| `.config/linux-voice-assistant/lva.env.example` | `~/.config/linux-voice-assistant/lva.env.example` |

Runs [Linux Voice Assistant](https://github.com/OHF-Voice/linux-voice-assistant)
(OHF's ESPHome-protocol satellite) in a rootless podman container. Wake word
detection (microWakeWord, default "Okay Nabu") runs locally; audio only goes to
Home Assistant after the wake word. HA adopts it through the ESPHome integration.

## Why a rootless quadlet, not Docker

It needs this user's PipeWire socket (`$XDG_RUNTIME_DIR/pulse/native`), which only
exists inside a logged-in session. A user unit starts with that session and runs
as this uid, so the socket is readable with no uid/group mapping. A system Docker
container would start at boot, before any session audio exists.

Requirements per machine: `podman` (≥ 4.4, for quadlets) and PipeWire with
`pipewire-pulse`, plus a mic and speaker.

## Install on a machine

```sh
stow --no-folding voice-satellite
cp ~/.config/linux-voice-assistant/lva.env.example ~/.config/linux-voice-assistant/lva.env  # optional overrides
systemctl --user daemon-reload
systemctl --user start linux-voice-assistant
```

Quadlet units are generated, so there is nothing to `enable`: `WantedBy=default.target`
in the file starts it on every login. Logs: `journalctl --user -u linux-voice-assistant`.

`lva.env` is machine-local and never stowed (see `.stow-local-ignore`). The
satellite name defaults to the hostname; set `CLIENT_NAME`, devices, wake word or
mic processing there. Any upstream `.env.example` variable works.

## Firewall

HA connects **to** the satellite on TCP 6053 (ESPHome API). With ufw, allow it from
the HA host only, never a blanket `ufw allow 6053`:

```sh
sudo ufw allow from <home-assistant-ip> to any port 6053 proto tcp comment 'LVA <- home assistant'
```

Then in HA: Settings → Devices & services → it should be discovered as an ESPHome
device; if mDNS doesn't cross, add **ESPHome** manually with `<this-host>:6053`.
Finally assign the voice pipeline on the new device's page.

## Notes

- The peripheral WebSocket API (6055, for Pi LED/button hats) is disabled; it is
  unauthenticated and unused on a desktop.
- Desk/webcam mics pick up the speakers; try `MIC_NOISE_SUPPRESSION=2` if the wake
  word false-triggers on its own replies.
- The image is pinned by digest (v1.1.15). Bump deliberately.
