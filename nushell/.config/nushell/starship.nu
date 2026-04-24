# Loaded via `overlay use ./starship.nu` in config.nu
# Mirrors `starship init nu` output but resolves starship from PATH.
export-env {
    let starship_bin = (which starship | get path?.0? | default "starship")

    $env.STARSHIP_SHELL = "nu"
    load-env {
        STARSHIP_SESSION_KEY: (random chars -l 16)
        PROMPT_MULTILINE_INDICATOR: (^$starship_bin prompt --continuation)
        PROMPT_INDICATOR: ""

        PROMPT_COMMAND: {||
            (
                # CMD_DURATION_MS is "0823" (string) when no command ran — coerce to int.
                let cmd_duration = if $env.CMD_DURATION_MS == "0823" { 0 } else { $env.CMD_DURATION_MS };
                ^$starship_bin prompt
                    --cmd-duration $cmd_duration
                    $"--status=($env.LAST_EXIT_CODE)"
                    --terminal-width (term size).columns
                    ...(
                        if (which "job list" | where type == built-in | is-not-empty) {
                            ["--jobs", (job list | length)]
                        } else {
                            []
                        }
                    )
            )
        }

        config: ($env.config? | default {} | merge {
            render_right_prompt_on_last_line: false
        })

        PROMPT_COMMAND_RIGHT: {||
            (
                let cmd_duration = if $env.CMD_DURATION_MS == "0823" { 0 } else { $env.CMD_DURATION_MS };
                ^$starship_bin prompt
                    --right
                    --cmd-duration $cmd_duration
                    $"--status=($env.LAST_EXIT_CODE)"
                    --terminal-width (term size).columns
                    ...(
                        if (which "job list" | where type == built-in | is-not-empty) {
                            ["--jobs", (job list | length)]
                        } else {
                            []
                        }
                    )
            )
        }
    }
}
