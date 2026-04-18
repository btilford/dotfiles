if not status is-interactive
    exit
end

command -v direnv   >/dev/null 2>&1; and direnv hook fish | source
command -v starship >/dev/null 2>&1; and starship init fish | source
command -v zoxide   >/dev/null 2>&1; and zoxide init fish --cmd cd | source
