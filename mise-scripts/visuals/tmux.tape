# vhs tape for the tmux terminal surface.
#   vhs mise-scripts/visuals/tmux.tape -o build/visuals/tmux-motion-<ts>.gif
# Driven by mise-scripts/visual-capture.sh when vhs is installed; without vhs the
# harness falls back to a real terminal inside the nested compositor.
#
# The tmux server here is PRIVATE: -L "$QS_VISUALS_TMUX_SOCKET" with the working
# tree's .tmux.conf. Never the default socket — that is the user's live server,
# which would leak their real work into the capture and let this tape kill their
# sessions. visual-capture.sh exports both vars; the defaults below only matter
# when running the tape by hand.
#
# Keep it short — this GIF is browsed on a phone.

Output tmux.gif

Set Shell bash
# Nerd Font, not vhs's default: the status line and prompt are built from glyphs
# (session indicator, git state, the notification indicator this surface exists to
# show). Without this every one of them renders as a tofu box.
Set FontFamily "JetBrainsMono Nerd Font"
Set FontSize 16
Set Width 1200
# Tall enough for the split panes, no taller — vhs pads the frame with empty
# terminal, and dead space is wasted bytes in a GIF browsed on a phone.
Set Height 480
Set Padding 12
Set TypingSpeed 40ms
# Match the desktop's palette (Theme.qml fallbacks: bg #1a0808, fg #cdd6f4,
# accent #ff6600) so the terminal surface reads as part of the same system as the
# other captures rather than as a stock vhs recording.
Set Theme { "background": "#1a0808", "foreground": "#cdd6f4", "cursor": "#ff6600", "selection": "#40241a", "black": "#1a0808", "red": "#ff5555", "green": "#50fa7b", "yellow": "#f1fa8c", "blue": "#8be9fd", "magenta": "#ff79c6", "cyan": "#8be9fd", "white": "#cdd6f4", "brightBlack": "#6c5148", "brightRed": "#ff6e6e", "brightGreen": "#69ff94", "brightYellow": "#ffffa5", "brightBlue": "#a4ffff", "brightMagenta": "#ff92df", "brightCyan": "#a4ffff", "brightWhite": "#ffffff" }

Hide
Type `TM="tmux -L ${QS_VISUALS_TMUX_SOCKET:-qs-visuals-tape} -f ${QS_VISUALS_TMUX_CONF:-$PWD/tmux/.tmux.conf}"` Enter
Type "$TM kill-server 2>/dev/null; clear" Enter
Sleep 500ms
Show

Type "$TM new-session -A -s visuals" Enter
Sleep 2s

Type "echo 'notification indicator lands in the status line'" Enter
Sleep 1500ms

Type "tmux split-window -h" Enter
Sleep 1500ms

Type "tmux list-panes" Enter
Sleep 2s

Hide
Type "tmux kill-server" Enter
Sleep 300ms
