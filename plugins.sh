#!/bin/bash

#TODO: https://github.com/tmux-plugins/tmux-copycat
#TODO: https://github.com/laktak/extrakto
#TODO: yank such as 'tmux-plugins/tmux-yank' (better alternatives)

TPM_PATH="$TMUX_PLUGIN_MANAGER_PATH/tpm"

tmux source - <<EOF

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'catppuccin/tmux'
set -g @plugin 'tmux-plugins/tmux-cpu'
set -g @plugin 'tmux-plugins/tmux-battery'
set -g @plugin 'sainnhe/tmux-fzf'
set -g @plugin 'tmux-plugins/tmux-prefix-highlight'
set -g @plugin 'alexwforsythe/tmux-which-key'

EOF

if [[ ! -d "$TPM_PATH" ]]; then
  # Pretty sure user will never see this since tmux won't have started for them
  tmux display "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_PATH" && "$TPM_PATH"/bin/install_plugins
fi

tmux run "$TPM_PATH/tpm"
