# Secrets: load the session cache, and define the point-of-use helpers.
#
# NOTHING HERE CALLS INFISICAL. That rule has not changed and must not: a network
# call in conf.d hangs every new terminal when the daemon is unreachable or the
# keyring is locked. What changed is where the values come from — a tmpfs file
# that dotfiles-secrets.service filled once at login. Reading it is a local read
# of a few hundred bytes, so this costs a fraction of a millisecond and cannot
# block on anything.
#
#   secrets-refresh          re-fetch after rotating a key (restarts the unit)
#   secrets-run opencode     secrets in that ONE process, gone when it exits
#   secrets-load             re-read the cache into THIS shell
#
# See the header of `dotfiles-secrets` for why the cache is tmpfs rather than
# disk, and for the exposure this trades away.

# Load first, define functions after: a conf.d file is sourced before the prompt,
# and anything later in startup that reads one of these variables (a prompt
# segment, a tool's fish completions) must see it already set.
#
# `-` on the test, not on the read: a machine with no cache is the normal state
# on a box that never ran the unit, and it must produce silence, not an error on
# every shell start.
set -l _cache "$XDG_RUNTIME_DIR/dotfiles/secrets.env"
if test -r "$_cache"
    while read -l line
        # Same guard shape as 05-local-env.fish, and for the same reason: written
        # as `string match ... and continue`, fish reads `and continue` as two
        # more arguments to string match rather than as a conditional, so blanks
        # and comments would be fed to `set -gx`.
        if string match -qr '^\s*(#|$)' -- $line
            continue
        end
        set -l pair (string split -m 1 '=' -- $line)
        if test (count $pair) -eq 2
            # infisical's dotenv format quotes values; strip one layer. `-c` must
            # precede `--`, or fish reads the flag as data and the quotes survive
            # into the exported value.
            set -l val (string trim -- $pair[2])
            set val (string trim -c '"\'' -- $val)
            # An EMPTY value is dropped rather than exported. This is the bug that
            # made every AI tool on this box fail at once: a failed fetch exported
            # VAR="", every later `set -q VAR` then reported it present, and no
            # shell ever retried — while consumers saw a set-but-empty key and
            # reported it as auth failure rather than as missing config.
            if test -n "$val"
                set -gx (string trim -- $pair[1]) $val
            end
        end
    end < "$_cache"
end
set -e _cache

function secrets-run --description 'Run a command with Infisical secrets in its environment'
    if test (count $argv) -eq 0
        echo "usage: secrets-run COMMAND [ARGS...]" >&2
        return 2
    end
    dotfiles-secrets --run -- $argv
end

function secrets-refresh --description 'Re-fetch Infisical secrets into the session cache'
    systemctl --user restart dotfiles-secrets.service
    or return 1
    # The restart refills the cache but cannot reach back into shells that are
    # already running — including this one. Re-read it here so the shell you typed
    # this in is actually fixed, which is the whole reason you typed it.
    secrets-load
end

function secrets-load --description 'Export Infisical secrets into the current shell'
    # Prefer the cache: it is already there, it costs a file read, and it is the
    # same content. Only go to the network when there is no cache to read.
    set -l cache "$XDG_RUNTIME_DIR/dotfiles/secrets.env"
    set -l dotenv
    if test -r "$cache"
        set dotenv (cat "$cache")
    else
        set dotenv (dotfiles-secrets --dotenv)
        or return 1
    end

    set -l count 0
    for line in $dotenv
        string match -qr '^\s*(#|$)' -- $line; and continue
        set -l pair (string split -m 1 '=' -- $line)
        test (count $pair) -eq 2; or continue
        # infisical's dotenv format quotes values; strip one layer. Note `-c` must
        # precede `--`, or fish reads the flag as data and the quotes survive into
        # the exported value.
        set -l val (string trim -- $pair[2])
        set val (string trim -c '"\'' -- $val)
        set -gx (string trim -- $pair[1]) $val
        set count (math $count + 1)
    end
    echo "[secrets] loaded $count secret(s) into this shell" >&2
end
