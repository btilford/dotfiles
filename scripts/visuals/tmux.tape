# vhs tape for the tmux terminal surface.
#   vhs scripts/visuals/tmux.tape -o build/visuals/tmux-motion-<ts>.gif
# Driven by scripts/visual-capture.sh when vhs is installed; without vhs the
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
Set FontSize 16
Set Width 1200
Set Height 700
Set Padding 12
Set TypingSpeed 40ms

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
