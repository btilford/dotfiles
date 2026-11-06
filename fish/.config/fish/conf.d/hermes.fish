# Hermes TUI gateway. The real host is machine-local — set
# HERMES_TUI_GATEWAY_URL in ~/.config/dotfiles/local.env (untracked).
# conf.d/05-local-env.fish reads that file first (digits sort before letters), so
# its value is already set here; the default below only applies when nothing sets it.
set -q HERMES_TUI_GATEWAY_URL
or set -gx HERMES_TUI_GATEWAY_URL "http://localhost:8642"
