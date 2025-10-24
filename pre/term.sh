#!/usr/bin/env bash

tmux source - <<EOF

set -g default-terminal "tmux-256color"
# Truecolor
set -as terminal-overrides ",xterm*:Tc"
# Undercurl
set -as terminal-overrides ',xterm*:Smulx=\E[4::%p1%dm'  # undercurl support
# Underscore colours - needs tmux-3.0
set -as terminal-overrides ',xterm*:Setulc=\E[58::2::::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'
# extended keys
set -as terminal-features 'xterm*:extkeys'
# In theory, sync render
#TODO: this may have fixed those popup plugins if don't want to use nvim anymore
set -as terminal-features 'xterm*:sync'

EOF
