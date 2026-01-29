alias ll="eza -al --icons always"
alias lt="eza --tree --level 2 --icons always"
alias shutdown='systemctl poweroff'


function git.latest 
  set -l count $argv[1]
  if test -z "$count"
        set count 5
  end
  git describe --tags (git rev-list --tags --max-count=$count)
end
