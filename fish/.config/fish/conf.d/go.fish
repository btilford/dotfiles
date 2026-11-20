# Put the directory `go install` writes to on PATH: $GOBIN, else the first
# $GOPATH entry's bin, else ~/go/bin. No-op on machines without it.

set -l gobin $HOME/go/bin
if set -q GOBIN; and test -n "$GOBIN"
    set gobin $GOBIN
else if set -q GOPATH; and test -n "$GOPATH"
    set gobin (string split : -- $GOPATH)[1]/bin
end

if test -d "$gobin"
    fish_add_path --global "$gobin"
end
