$env.GPG_TTY = (tty)
gpg-connect-agent updatestartuptty /bye | ignore
$env.SSH_AUTH_SOCK = ($env.SSH_AUTH_SOCK? | default (gpgconf --list-dirs agent-ssh-socket))

$env.M2_HOME = ($env.HOME | path join .m2)
$env.GOPATH = ($env.HOME | path join go)

# Editor — resolve from PATH, no hardcoded /usr/bin
let nvim_path = (which nvim | get path?.0? | default "nvim")
$env.VISUAL = $nvim_path
$env.EDITOR = $nvim_path
$env.config = ($env.config? | default {} | merge { buffer_editor: $nvim_path })

# PATH additions
$env.PATH = (
    $env.PATH
    | split row (char esep)
    | append /usr/local/bin
    | append ($env.HOME | path join .local/bin)
    | append ($env.GOPATH | path join bin)
    | append ($env.HOME | path join .cargo/bin)
    | uniq
)

# bun — global JS CLIs live in ~/.bun/bin (bun is the sole owner of global JS
# tools; npm globals are deliberately unused). Same path on Linux and macOS.
# Prepended so it wins over any stale runtime-managed shim. No-op without bun.
let bun_bin = ($env.HOME | path join .bun/bin)
if ($bun_bin | path exists) {
    $env.BUN_INSTALL = ($env.HOME | path join .bun)
    $env.PATH = ($env.PATH | split row (char esep) | prepend $bun_bin | uniq)
}

# CHROME_BIN — headless-browser test runners (Karma, Puppeteer, Playwright's
# chrome channel, Kotlin/JS + wasmJs `browserTest`) exec whatever this points at.
# Karma's chrome launcher only probes `google-chrome`, `chrome` and
# `chromium-browser`, so a machine carrying Brave — or Arch's bare `chromium` —
# fails to launch a browser it actually has. Brave first (daily driver here),
# the rest as fallbacks. No-op when none is present or when already set.
let chrome_bin = (
    [brave chromium chromium-browser google-chrome-stable google-chrome]
    | each {|b| which $b }
    | flatten
    | get --optional path
    | compact
    | get --optional 0
)
if $chrome_bin != null and not ("CHROME_BIN" in $env) {
    $env.CHROME_BIN = $chrome_bin
}

# Starship prompt cache
if (which starship | is-not-empty) {
    let starship_cache = ($env.HOME | path join .cache/starship)
    if not ($starship_cache | path exists) { mkdir $starship_cache }
    starship init nu | save --force ($starship_cache | path join init.nu)
}

# Carapace completions cache
if (which carapace | is-not-empty) {
    $env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
    carapace _carapace nushell | save --force ($env.HOME | path join .config/nushell/carapace.nu)
}

# Zoxide
if (which zoxide | is-not-empty) {
    zoxide init nushell --cmd cd | save -f ($env.HOME | path join .config/nushell/.zoxide.nu)
}

# Yazi wrapper: cd into last directory on exit
def --env y [...args] {
    let tmp = (mktemp -t "yazi-cwd.XXXXXX")
    yazi ...$args --cwd-file $tmp
    let cwd = (open $tmp)
    if $cwd != "" and $cwd != $env.PWD {
        cd $cwd
    }
    rm -fp $tmp
}

# Sensitive credentials — load from local-only file not in version control
# Create ~/.config/nushell/local.nu and add secrets there
# Note: source requires a parse-time literal; the file must exist at parse time.
source ~/.config/nushell/local.nu
if (which mise | is-not-empty) {
    let mise_path = ($nu.default-config-dir | path join mise.nu)
    ^mise activate nu | save $mise_path --force
}