# Load machine-local values from ~/.config/dotfiles/local.env.
#
# That file is untracked and machine-specific: hostnames and gateway URLs. It
# holds NO credentials — those are fetched at point of use by dotfiles-secrets, so
# nothing here ever calls infisical. Nothing private belongs in THIS file — it is
# published. See commands/.local/share/dotfiles/required-env for the manifest and
# `dotfiles-local-env --check` to find what is missing.
#
# Numbered 05 deliberately: conf.d loads alphabetically, and configs that set
# their own fallback use `set -q VAR; or set -gx VAR default`. If this ran after
# them (e.g. hermes.fish) the default would already be set and the local value
# would never apply. Values load early; behaviour overrides go in a `99-local`
# file instead.
#
# Format is plain KEY=VALUE, no quotes and no expansion, so systemd can consume
# the very same file via ~/.config/environment.d/50-local.conf (a symlink to it).

set -l _local_env "$HOME/.config/dotfiles/local.env"

if test -r "$_local_env"
    while read -l line
        # Skip blanks and comments.
        string match -qr '^\s*(#|$)' -- $line and continue

        set -l pair (string split -m 1 '=' -- $line)
        if test (count $pair) -eq 2
            set -gx (string trim -- $pair[1]) (string trim -- $pair[2])
        end
    end < "$_local_env"
end
