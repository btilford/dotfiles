# Secrets helpers. DEFINES functions — runs nothing.
#
# Nothing here touches infisical at shell startup, deliberately: a network call in
# conf.d hangs every new terminal when the daemon is unreachable or the keyring is
# locked. Secrets arrive only when you ask for them.
#
#   secrets-run opencode     secrets live in that process only, and die with it
#   secrets-load             export into THIS shell, for tools that need env vars
#
# Prefer secrets-run. secrets-load leaves the values in the shell and in every
# child it later spawns, which is occasionally what you want and always worth
# choosing on purpose.

function secrets-run --description 'Run a command with Infisical secrets in its environment'
    if test (count $argv) -eq 0
        echo "usage: secrets-run COMMAND [ARGS...]" >&2
        return 2
    end
    dotfiles-secrets --run -- $argv
end

function secrets-load --description 'Export Infisical secrets into the current shell'
    set -l dotenv (dotfiles-secrets --dotenv)
    or return 1

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
