#!/bin/bash

tmux source - <<EOF

set -sa terminal-overrides ",xterm*:Tc"
set -g default-terminal "tmux-256color"
# Undercurl
set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'  # undercurl support
# Underscore colours - needs tmux-3.0
set -as terminal-overrides ',*:Setulc=\E[58::2::::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

EOF
