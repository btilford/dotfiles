$env.GPG_TTY = (tty)
gpg-connect-agent updatestartuptty /bye | ignore
$env.SSH_AUTH_SOCK = ($env.SSH_AUTH_SOCK? | default (gpgconf --list-dirs agent-ssh-socket))

$env.M2_HOME = ($env.HOME | path join .m2)
#source ./.zoxide.nu

#if ($env | get -i ZELLIJ | is-empty) {
#  zellij
#} else {
#  echo "Zellij already running..,"
#}
def --env y [...args] {
	let tmp = (mktemp -t "yazi-cwd.XXXXXX")
	yazi ...$args --cwd-file $tmp
	let cwd = (open $tmp)
	if $cwd != "" and $cwd != $env.PWD {
		cd $cwd
	}
	rm -fp $tmp
}



let starship_cache = "~/.cache/starship"
if not ($starship_cache | path exists) {
  mkdir $starship_cache
}
starship init nu | save --force ~/.cache/starship/init.nu
## ~/.config/nushell/env.nu
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
let carapace_cache = "~/.cache/carapace"
if not ($carapace_cache | path exists) {
  mkdir $carapace_cache
}
# /usr/bin/carapace _carapace nushell | save -f $"($carapace_cache)/init.nu"
carapace _carapace nushell | save --force ~/.cache/carapace/init.nu

$env.OBSIDIAN_REST_API_KEY = '***REMOVED***'

$env.GOPATH = '~/go'
$env.PATH = (
  $env.PATH
    | split row (char esep)
    | append /usr/local/bin
    | append ($env.HOME | path join .local/bin)
    | append ($env.GOPATH | path join bin)
    | append ($env.HOME | path join .cargo/bin)
    | uniq
)

$env.VISUAL = '/usr/bin/nvim'
$env.EDITOR = '/usr/bin/nvim'
$env.config.buffer_editor = '/usr/bin/nvim'

zoxide init nushell | save -f ~/.zoxide.nu
