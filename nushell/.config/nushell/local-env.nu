# Load machine-local values from ~/.config/dotfiles/local.env.
#
# That file is untracked and machine-specific: hostnames and gateway URLs. It
# holds NO credentials — those are fetched at point of use by dotfiles-secrets, so
# nothing here ever calls infisical. Nothing private belongs in THIS file — it is
# published. Manifest: commands/.local/share/dotfiles/required-env.
# Find what is missing with: dotfiles-local-env --check
#
# Sourced from config.nu BEFORE local.nu, so a machine can still override anything
# here by hand. Unlike local.nu this file is tracked, which is why it holds only
# the reader and never a value.
#
# Format is plain KEY=VALUE, no quotes and no expansion — the same file feeds the
# other shells and systemd's environment.d.

let local_env_file = ($env.HOME | path join ".config" "dotfiles" "local.env")

if ($local_env_file | path exists) {
    open $local_env_file
    | lines
    | where {|line| ($line | str trim) != "" and not (($line | str trim) | str starts-with "#") }
    | reduce --fold {} {|line, acc|
        let parts = ($line | split row --number 2 "=")
        if ($parts | length) == 2 {
            $acc | upsert ($parts.0 | str trim) ($parts.1 | str trim)
        } else {
            $acc
        }
    }
    | load-env
}
