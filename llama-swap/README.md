# llama-swap — multi-model LLM serving layer

Stow package. `stow --no-folding llama-swap` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/llama-swap/config.yaml` | `~/.config/llama-swap/config.yaml` |
| `.config/systemd/user/llama-swap.service` | `~/.config/systemd/user/llama-swap.service` |

## Why it replaced Lemonade

Lemonade serves exactly one LLM at a time (`max_models.llm = 1`), so the
completion model and the assistant model evict each other on every alternating
request — which makes inline completion unusable. llama-swap keeps a **group** of
models resident together and swaps only the ones it must.

## Why every model command is a `podman run`

Building llama.cpp for gfx1151 (Strix Halo) is fiddly enough that the
`kyuz0/amd-strix-halo-toolboxes` images exist specifically to get it right, and
they are rebuilt against llama.cpp master. A container shares the host kernel, so
the kernel-level concerns (amdgpu, ROCm's kernel driver, GTT sizing via
`amdgpu.gttsize`, amdxdna) stay host-side and already are in place here —
everything the toolbox provides is userspace.

**Use a live tag.** `rocm-7.2.1` looks reasonable and is abandoned: re-pulling it
yielded llama.cpp b8940 while upstream was at b10235, and Qwen3.6-35B-MTP failed
to load with `missing tensor 'blk.40.ssm_conv1d.weight'` purely because of that
age. The maintained tags (`rocm-7.14`, `rocm-6.4.4`, `therock-nightly`,
`vulkan-radv`, `vulkan-amdvlk`) rebuild several times a day.

The commands are written out per model rather than shared through a macro. That
repetition is deliberate — macro support varies between llama-swap releases, and a
config that fails to parse takes **every** model down at once.

## Enabling the unit

Never `systemctl --user enable` a stowed unit — `disable`/`reenable` deletes the
symlink, i.e. the file. Link `.wants` by hand:

```sh
ln -s ~/.config/systemd/user/llama-swap.service \
      ~/.config/systemd/user/default.target.wants/llama-swap.service
systemctl --user daemon-reload
```

If it cannot see files under `$HOME`, check `systemctl --user cat llama-swap` for
`ProtectHome=` before debugging permissions — that sandboxing returns EACCES
regardless of ownership, and it has bitten this setup before.
