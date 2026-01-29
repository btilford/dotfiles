# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

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

source ~/.config/fish/env.fish
source ~/.config/fish/custom.fish
source ~/.config/fish/aliases.fish
source ~/.config/fish/keybinds.fish
if test ~/.config/fish/local_only.fish
    source ~/.config/fish/local_only.fish
else
    echo "No local_only.fish found, skipping."
end


### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
set --export --prepend PATH "/Users/btilford/.rd/bin"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# Added by `rbenv init` on Tue Jun 10 13:26:03 MDT 2025
# status --is-interactive; and rbenv init - --no-rehash fish | source

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
set --export --prepend PATH "/Users/btilford/.rd/bin"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# Added by `rbenv init` on Tue Jun 10 13:26:03 MDT 2025
status --is-interactive; and rbenv init - --no-rehash fish | source
