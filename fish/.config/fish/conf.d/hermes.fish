# Hermes TUI gateway. The real host is machine-local — set
# HERMES_TUI_GATEWAY_URL in ~/.config/fish/conf.d/local.fish (untracked).
# conf.d loads alphabetically, so local.fish is sourced after this file and its
# value wins; the default below only applies when nothing sets it.
set -q HERMES_TUI_GATEWAY_URL
or set -gx HERMES_TUI_GATEWAY_URL "http://localhost:8642"
