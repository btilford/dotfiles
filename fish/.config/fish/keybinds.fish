# Key bindings, sourced from config.fish.
#
# WHY THIS IS NOT A conf.d DROP-IN
#
# Everything else in this package is a conf.d drop-in, and atuin started out as
# one. It cannot be. fish sources the whole of conf.d BEFORE config.fish, and
# config.fish's very first line sources env.fish, which runs
# `fzf --fish | source` — binding Ctrl+R to fzf-history-widget. So a conf.d file
# can never win Ctrl+R here no matter what it is named.
#
# Naming made it worse before that was understood: conf.d loads in byte order and
# digits sort BEFORE letters, so `90-atuin.fish` ran ahead of `fzf.fish` rather
# than after it. (That trap applies to the reserved `99-local` slot too — in fish
# it does not load last, unlike the numbered ~/.config/bashrc drop-ins.) Both
# layers had to be beaten, and only config.fish is late enough.
#
# The one thing still after this is local_only.fish, which is the machine-local
# override slot — deliberately left able to win.

if not status is-interactive
    exit
end

if command -q atuin
    # Guard against a set-but-EMPTY ATUIN_* variable. atuin resolves settings
    # from the config file first and the environment second, and an empty value
    # is not treated as "unset" — it is parsed, it fails, and it takes down
    # settings loading for the whole binary:
    #
    #   Error: could not load client settings
    #   Caused by: failed to deserialize: relative URL without a base: ""
    #              for key `sync_address`
    #
    # Every atuin command then errors, including the init below. A live hazard,
    # not a theoretical one: the machine-local files in this repo are generated
    # with empty placeholders for anything not yet filled in.
    for _atuin_var in ATUIN_SYNC_ADDRESS ATUIN_AUTO_SYNC ATUIN_AI__ENABLED ATUIN_AI__ENDPOINT ATUIN_AI__MODEL
        if set -q $_atuin_var; and test -z "$$_atuin_var"
            set -e $_atuin_var
        end
    end
    set -e _atuin_var

    # Two separate fzf integrations bind Ctrl+R to a history widget, and atuin
    # replaces both:
    #
    #   fzf.fish (fisher plugin)  -> _fzf_search_history, via fzf_configure_bindings
    #   fzf --fish (env.fish)     -> fzf-history-widget
    #
    # The plugin's is released properly. `--history=` with an empty value is
    # fzf.fish's documented way to drop one binding: the function uninstalls its
    # whole set and reinstalls it without that key, leaving the other five
    # (Alt+Ctrl+F directory, Alt+Ctrl+L git log, Alt+Ctrl+S git status,
    # Alt+Ctrl+P processes, Ctrl+V variables) intact. Editing the plugin's own
    # conf.d file instead would be reverted by `fisher update`.
    if functions -q fzf_configure_bindings
        fzf_configure_bindings --history=
    end

    # The `fzf --fish` one has no such switch, so atuin's init simply rebinds
    # over it. Ctrl+T (files) and Alt+C (cd) from that integration are untouched.
    #
    # atuin binds Ctrl+R (search), Up (search, prefix-filtered) and `?` at an
    # empty prompt (the AI assistant). Pass --disable-ctrl-r / --disable-up-arrow
    # / --disable-ai to reclaim any of them.
    atuin init fish | source
end
