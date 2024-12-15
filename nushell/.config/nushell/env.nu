$env.GPG_TTY = (tty)
/nix/store/65lafl8zxvwslpg2dlpxz1wlxnf11scv-gnupg-2.4.5/bin/gpg-connect-agent updatestartuptty /bye | ignore

$env.SSH_AUTH_SOCK = ($env.SSH_AUTH_SOCK? | default (/nix/store/65lafl8zxvwslpg2dlpxz1wlxnf11scv-gnupg-2.4.5/bin/gpgconf --list-dirs agent-ssh-socket))

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
/home/btilford/.nix-profile/bin/starship init nu | save --force /home/btilford/.cache/starship/init.nu

let carapace_cache = "/home/btilford/.cache/carapace"
if not ($carapace_cache | path exists) {
  mkdir $carapace_cache
}
/nix/store/lbi7gc8wpmdsgqi4zrwifmz47y39sjmm-carapace-1.0.2/bin/carapace _carapace nushell | save -f $"($carapace_cache)/init.nu"

$env.OBSIDIAN_REST_API_KEY = ***REMOVED***