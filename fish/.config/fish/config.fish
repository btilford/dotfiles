# >>> lig pre >>>
# lig (terminal autocomplete) is optional. Skip both hooks when it is absent.
set -l lig_bin (command -s lig; or path filter -x /opt/homebrew/bin/lig)
if test -n "$lig_bin"
    eval ($lig_bin init fish pre | string collect)
end
# <<< lig pre <<<
source ~/.config/fish/env.fish

if not status is-interactive
    exit
end

mise activate fish | source

# Enable vi key bindings
fish_vi_key_bindings

# Customize the mode indicator
function fish_mode_prompt
    switch $fish_bind_mode
        case default
            set_color --bold red
            echo 'N'
        case insert
            set_color --bold green
            echo 'I'
        case replace_one
            set_color --bold green
            echo 'R'
        case visual
            set_color --bold brmagenta
            echo 'V'
        case '*'
            set_color --bold red
            echo '?'
    end
    set_color normal
end

source ~/.config/fish/custom.fish
source ~/.config/fish/aliases.fish
source ~/.config/fish/keybinds.fish

if test -f ~/.config/fish/local_only.fish
    source ~/.config/fish/local_only.fish
end


# >>> lig post >>>
if test -n "$lig_bin"
    eval ($lig_bin init fish post | string collect)
end
# <<< lig post <<<
