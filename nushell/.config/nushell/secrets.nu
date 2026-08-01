# Secrets helpers. DEFINES commands — runs nothing.
#
# Nothing here touches infisical at shell startup, deliberately: a network call at
# load time hangs every new terminal when the daemon is unreachable or the keyring
# is locked. Secrets arrive only when you ask for them.
#
#   secrets-run opencode     secrets live in that process only, and die with it
#   secrets-load             export into THIS shell, for tools that need env vars
#
# Prefer secrets-run. secrets-load leaves the values in the shell and in every
# child it later spawns.

# `--env` is required: without it load-env would apply to the command's own scope
# and vanish on return.
export def --env secrets-load [] {
    let dotenv = (dotfiles-secrets --dotenv | complete)
    if $dotenv.exit_code != 0 {
        error make { msg: $"dotfiles-secrets failed: ($dotenv.stderr | str trim)" }
    }

    let parsed = ($dotenv.stdout
        | lines
        | where {|line| ($line | str trim) != "" and not (($line | str trim) | str starts-with "#") }
        | reduce --fold {} {|line, acc|
            let parts = ($line | split row --number 2 "=")
            if ($parts | length) == 2 {
                # infisical's dotenv format quotes values; strip one layer.
                $acc | upsert ($parts.0 | str trim) ($parts.1 | str trim | str trim --char '"' | str trim --char "'")
            } else {
                $acc
            }
        })

    $parsed | load-env
    print --stderr $"[secrets] loaded ($parsed | columns | length) secret\(s\) into this shell"
}

export def --wrapped secrets-run [...args] {
    if ($args | is-empty) {
        error make { msg: "usage: secrets-run COMMAND [ARGS...]" }
    }
    dotfiles-secrets --run -- ...$args
}
