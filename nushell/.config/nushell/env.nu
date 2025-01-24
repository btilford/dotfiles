$env.GPG_TTY = (tty)
/usr/bin/gpg-connect-agent updatestartuptty /bye | ignore
$env.SSH_AUTH_SOCK = ($env.SSH_AUTH_SOCK? | default (/usr/bin/gpgconf --list-dirs agent-ssh-socket))


source ./.zoxide.nu

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



let starship_cache = "/home/btilford/.cache/starship"
if not ($starship_cache | path exists) {
  mkdir $starship_cache
}
/usr/bin/starship init nu | save --force /home/btilford/.cache/starship/init.nu

let carapace_cache = "/home/btilford/.cache/carapace"
if not ($carapace_cache | path exists) {
  mkdir $carapace_cache
}
/usr/bin/carapace _carapace nushell | save -f $"($carapace_cache)/init.nu"

$env.OBSIDIAN_REST_API_KEY = '***REMOVED***'

$env.GOPATH = '/home/btilford/go'
$env.PATH = (
  $env.PATH
    | split row (char esep)
    | append /usr/local/bin
    | append ($env.HOME | path join .local/bin)
    | append ($env.GOPATH | path join bin)
    | uniq
)

$env.VISUAL = '/usr/bin/nvim'
$env.EDITOR = '/usr/bin/nvim'
$env.config.buffer_editor = '/usr/bin/nvim'


