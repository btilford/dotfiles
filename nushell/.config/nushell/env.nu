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
    | append ($env.GOPATH | path join bin)
    | append ($env.HOME | path join .cargo/bin)
    | prepend ($env.HOME | path join .local/bin)
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

let nu_dir = ($nu.default-config-dir)

# config.nu `source`s the files generated below, and `source` resolves at parse
# time — but nushell parses config.nu only after env.nu has finished running, so
# generating them here is what makes a cold start work on a fresh clone. They are
# gitignored precisely because they are host-specific and regenerated every start.
#
# The stub for an unavailable tool is load-bearing, not defensive: a missing file
# is a parse error that takes the whole shell down, and no `if ... path exists`
# guard around `source` prevents it — the parser runs before the guard does.
def ensure-stub [path: path] {
    if not ($path | path exists) { touch $path }
}

# Carapace completions cache
if (which carapace | is-not-empty) {
    $env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
    carapace _carapace nushell | save --force ($nu_dir | path join carapace.nu)
} else {
    ensure-stub ($nu_dir | path join carapace.nu)
}

# Zoxide
if (which zoxide | is-not-empty) {
    zoxide init nushell --cmd cd | save -f ($nu_dir | path join .zoxide.nu)
} else {
    ensure-stub ($nu_dir | path join .zoxide.nu)
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

# Sensitive credentials / machine-local config. Genuinely untracked now — the stub
# is created here rather than shipped in the repo, so writing a secret into it can
# no longer commit that secret. env.nu deliberately does NOT `source` it: that would
# be parse-time, i.e. before this line can create it. config.nu sources it instead,
# which parses after env.nu has run.
ensure-stub ($nu_dir | path join local.nu)

if (which mise | is-not-empty) {
    ^mise activate nu | save ($nu_dir | path join mise.nu) --force
} else {
    ensure-stub ($nu_dir | path join mise.nu)
}