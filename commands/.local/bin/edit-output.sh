#!/usr/bin/env bash

file=`mktemp`.sh
tmux capture-pane -pS -32768 > $file
tmux new-window -n:edit-output "nvim '+ normal G$' $file"

