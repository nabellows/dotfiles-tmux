#!/bin/bash

tmux source - <<EOF

set -g mouse on
set -sg extended-keys on
set -g focus-events on
set -g set-clipboard on
set-window-option -g mode-keys vi
# used when entering tmux command, vi mode was just weird and confusing
set -g status-keys emacs

set -sg escape-time 0
set -g status-interval 2

# Start windows and panes at 1, not 0
set -g base-index 1
set -g pane-base-index 1
set-window-option -g pane-base-index 1
set -g renumber-windows on

EOF
