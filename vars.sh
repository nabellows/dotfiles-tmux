#!/bin/bash

is_battery_mac() {
  [[ "$(uname)" == "Darwin" ]] && pmset -g batt | grep -q "Battery"
}

if is_battery_mac ; then
  tmux set -g @has_battery 1
fi

if [[ -n "$SSH_CONNECTION" ]]; then
  tmux set -g @is_remote 1
  tmux setenv -g TMUX_REMOTE 1
fi

tmux source - <<EOF

set -gF @plugins_dir "$HOME/.tmux/plugins"
set -gF @scripts "#{@config_dir}/scripts"

setenv -gF TMUX_CONFIG_FILE '#{@config_file}'
setenv -gF TMUX_CONFIG_DIR '#{@config_dir}'
setenv -gF TMUX_PLUGIN_MANAGER_PATH '#{@plugins_dir}'
setenv -gF TMUX_PLUGINS_PATH '#{@plugins_dir}'
setenv -gF TMUX_SCRIPTS_PATH '#{@scripts}'

EOF
