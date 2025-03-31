#!/bin/bash

#TODO: https://github.com/tmux-plugins/tmux-copycat
#TODO: https://github.com/laktak/extrakto
#TODO: yank such as 'tmux-plugins/tmux-yank' (better alternatives)

TPM_PATH="$TMUX_PLUGIN_MANAGER_PATH/tpm"

# As it turns out, tpm was never using actual set -g values (as I suspected)
#  and instead trying to be clever and parse your config file for you
# It obviously fails spectacularly for my layout, so revert to the 'deprecated'
#  (but in some comments, "un-deprecated") syntax to actually make it a set-option value
tmux set -g @tpm_plugins "

tmux-plugins/tpm
catppuccin/tmux
tmux-plugins/tmux-cpu
tmux-plugins/tmux-battery
sainnhe/tmux-fzf
tmux-plugins/tmux-prefix-highlight
alexwforsythe/tmux-which-key

"

if [[ ! -d "$TPM_PATH" ]]; then
  # Pretty sure user will never see this since tmux won't have started for them
  tmux display "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_PATH" && "$TPM_PATH"/bin/install_plugins
fi

tmux run "$TPM_PATH/tpm"
