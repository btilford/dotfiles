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


    # WORK MACHINES TALK TO NO SERVER. Local sqlite only.
    #
    # This has to be asserted, not assumed. atuin's own defaults are
    # sync_address = https://api.atuin.sh/ and auto_sync = true, and neither
    # appears in the tracked config.toml (they are profile-varying, so they are
    # deliberately absent to keep the env override working). Today a work
    # machine syncs nothing only because it is not logged in — an accident of
    # state, not a guarantee. One `atuin login` would silently start shipping
    # work shell history to a third party.
    #
    # Derived from DOTFILES_PROFILE rather than set per machine, defaulting to
    # work, so a new machine is safe before anyone remembers to configure it.
    # Same direction as the nvim AI gate: absence means off.
    #
    # The agent hooks and local history are unaffected — they need no server,
    # which is the whole point of giving work atuin at all.
    if test "$DOTFILES_PROFILE" != personal
        set -gx ATUIN_AUTO_SYNC false
        set -e ATUIN_SYNC_ADDRESS
        set -e ATUIN_AI__ENABLED
        set -e ATUIN_AI__ENDPOINT
    else if not set -q ATUIN_SYNC_ADDRESS
        # Personal, but no sync server configured yet. Force sync OFF rather
        # than letting atuin fall back to its upstream default of
        # https://api.atuin.sh/ — an unconfigured or stale shell would otherwise
        # silently ship personal shell history to a third party. This is not
        # hypothetical: it happened, from a terminal opened before the variable
        # was added to local.env.
        set -gx ATUIN_AUTO_SYNC false
    end

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
