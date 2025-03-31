#!/bin/bash

tmux source - <<EOF

set -gF @fzf_scripts '#{@plugins_dir}/tmux-fzf/scripts'
set -gF @fzf_switch_window '#{@fzf_scripts}/window.sh switch'

setenv -gF TMUX_FZF_MENU "switch window\n#{@fzf_switch_window}\n"
setenv -g TMUX_FZF_OPTIONS "-p -w 95% -h 98% -m --preview-window=up,85%"
setenv -g TMUX_FZF_WINDOW_FORMAT "#{@my_window_index}"

EOF

