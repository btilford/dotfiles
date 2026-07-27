# CHROME_BIN — headless-browser test runners (Karma, Puppeteer, Playwright's
# chrome channel, Kotlin/JS + wasmJs `browserTest`) exec whatever this points at.
#
# Karma's chrome launcher only probes `google-chrome`, `chrome` and
# `chromium-browser`, so a machine carrying Brave — or Arch's bare `chromium` —
# fails with "Errors occurred during launch of browser for testing.
# - ChromeHeadless. Please make sure that you have installed browsers." even
# though a perfectly good Chromium is installed. Naming it explicitly fixes that.
#
# Brave first (it is the daily driver here); plain Chromium and Chrome are
# fallbacks so this works on any machine. No-op when none is present, which
# leaves the launcher's own probe untouched. Never respects an existing value —
# an explicit CHROME_BIN from the environment wins.

if not set --query CHROME_BIN
    for browser in brave chromium chromium-browser google-chrome-stable google-chrome
        if command --query $browser
            set --export --global CHROME_BIN (command --search $browser)
            break
        end
    end
end
