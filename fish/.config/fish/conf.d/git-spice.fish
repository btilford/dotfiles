# git-spice — stacked branches. Upstream docs spell the command `gs`, but the
# binary installs as `git-spice` (both the AUR package and homebrew-core), and
# /usr/bin/gs is ghostscript — required by okular/cups-pdf/texlive and invoked as
# a bare `gs` by imagemagick and matplotlib. So `gs` is an interactive alias
# only; scripts and git hooks must call `git-spice` directly.
#
# Completions are eval'd rather than committed to completions/ (the workmux
# convention) because `git-spice shell completion fish` bakes in the binary's
# absolute path — /usr/bin on Arch, a brew prefix on macOS — which is not portable
# and breaks the repo's no-absolute-paths rule. Sourcing regenerates it per host,
# and per installed version.

if command -q git-spice
    alias gs="git-spice"
    git-spice shell completion fish | source
end
