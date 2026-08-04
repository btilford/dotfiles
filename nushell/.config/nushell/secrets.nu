# Secrets: read the session cache into the environment on `use`, and define the helpers.
#
# The old rule here was "runs nothing" — no secret ever reached the environment
# automatically. That was reversed deliberately (see the header of
# `dotfiles-secrets`): consumers that can only take an environment variable —
# clipborg expands ${ENV} at config load and hard-errors on an unset one;
# opencode, aider and nvim are the same shape — do not work in a plain terminal
# otherwise, and wrapping every entry point was not practical.
#
# What has NOT changed is the reason that rule existed: **no shell may call
# infisical at startup.** That is a network round trip on every new terminal and
# it hangs the shell when the gateway is unreachable or the wallet is locked.
#
# So the fetch moved off the shell's path rather than into it: one systemd user
# unit (dotfiles-secrets.service) fetches ONCE at login into
# $XDG_RUNTIME_DIR/dotfiles/secrets.env (tmpfs, 0600, gone at logout), and the
# export-env block below is a plain read of that local file.
#
#   secrets-run opencode     secrets live in that process only, and die with it
#   secrets-load             re-read the cache into THIS shell
#   secrets-refresh          re-fetch (after rotating a key), then reload

# Shared by the export-env block and secrets-load, so the two can never drift in
# how they treat quoting or comments.
def parse-dotenv [text: string] {
    $text
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
    }
}

def cache-path [] {
    let runtime = ($env.XDG_RUNTIME_DIR? | default "")
    if ($runtime | is-empty) { "" } else { $"($runtime)/dotfiles/secrets.env" }
}

# `export-env` is the only thing in a module that runs at `use` time AND whose
# environment changes reach the caller's scope — a plain `def --env` would have to
# be invoked by config.nu, and an ordinary top-level statement would not export.
# Reading a missing cache is a no-op, never an error: a machine with no secrets,
# or a login where the fetch failed, must still get a working shell.
export-env {
    let cache = (cache-path)
    if ($cache | is-not-empty) and ($cache | path exists) {
        parse-dotenv (open --raw $cache) | load-env
    }
}

# `--env` is required: without it load-env would apply to the command's own scope
# and vanish on return.
export def --env secrets-load [] {
    let cache = (cache-path)

    # Prefer the cache and fall back to a live fetch. Reversing that order would
    # put a network call on the common path for no gain.
    let text = if ($cache | is-not-empty) and ($cache | path exists) {
        open --raw $cache
    } else {
        let dotenv = (dotfiles-secrets --dotenv | complete)
        if $dotenv.exit_code != 0 {
            error make { msg: $"dotfiles-secrets failed: ($dotenv.stderr | str trim)" }
        }
        $dotenv.stdout
    }

    let parsed = (parse-dotenv $text)
    $parsed | load-env
    print --stderr $"[secrets] loaded ($parsed | columns | length) secret\(s\) into this shell"
}

export def --env secrets-refresh [] {
    systemctl --user restart dotfiles-secrets.service
    secrets-load
}

export def --wrapped secrets-run [...args] {
    if ($args | is-empty) {
        error make { msg: "usage: secrets-run COMMAND [ARGS...]" }
    }
    dotfiles-secrets --run -- ...$args
}
