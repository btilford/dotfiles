# `how size disk` -> proposes the df/du command.
#
# A function in functions/ rather than a line in the atuin block of
# keybinds.fish: fish autoloads this file on first use, so it costs nothing at
# shell start, and it stays defined whether or not that block ran.
#
# "$argv" is quoted deliberately. `atuin ai inline` takes the query as ONE
# positional argument; unquoted, fish would expand the list and send only the
# first word, dropping the rest silently.
#
# `inline` proposes onto the prompt and does not execute — the same posture as
# enter_accept = false in the atuin config.
function how --description "Ask atuin AI for a command (atuin ai inline)"
    if not command -q atuin
        echo "how: atuin is not installed" >&2
        return 127
    end

    if test (count $argv) -eq 0
        echo "usage: how <what you want to do>   e.g. how size disk" >&2
        return 2
    end

    atuin ai inline -- "$argv"
end
