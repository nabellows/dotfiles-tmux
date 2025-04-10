#!/bin/bash

# Yes, ik its gross, its because the repo is catppuccin as prefix instead of suffix ('catppuccin/tmux')
CTPN_PLUG_DIR="$TMUX_PLUGINS_PATH/tmux/"
CTPN_PLUG_SCRIPT="$CTPN_PLUG_DIR/catppuccin.tmux"

dir_color="#{@thm_lavender}"
dir_text="#(_NO_NICKNAME=1 useful-dir #{pane_current_path})"
win_text="#(_SHORT_PKG=1 #{@scripts}/tmux-win-name '#{window_id}' >/dev/null)#{E:@my_window_name_formatted}"
flavor="${CATPPUCCIN_FLAVOR:-mocha}"

mode_color="#{@thm_yellow}"
synchronized_color="#{@thm_red}"

function mode-or-sync-color() {
  local if_regular="$1"
  echo "#{?pane_in_mode,$mode_color,#{?pane_synchronized,$synchronized_color,$if_regular}}"
}

# Unset all catppuccin vars to allow re-sourcing
tmux show-options -g | awk '/^(@catppuccin|@thm_)/ {print $1}' | while read -r var; do
  tmux set -ug "$var"
done

tmux source - <<EOF

# catppuccin config should be done before running plugs
set -g @catppuccin_flavor "$flavor"
setenv -g CATPPUCCIN_FLAVOR "$flavor"

# Add preferred names that were missing
set -g @thm_base "#{@thm_bg}"
set -g @thm_text "#{@thm_fg}"

#------------------------------------------------------------
# Status Line
#------------------------------------------------------------
set -g @catppuccin_status_left_separator "█"

set -g @catppuccin_directory_color "$dir_color"
set -g @catppuccin_directory_text " $dir_text"
set -g @catppuccin_application_color "#{@thm_rosewater}"

set -g @catppuccin_cpu_icon " "
set -g @catppuccin_cpu_text " #{l:#{cpu_percentage}}"
set -g @catppuccin_cpu_color "#{l:#{cpu_fg_color}}"
set -g @catppuccin_status_cpu_text_fg "#{l:#{cpu_fg_color}}"
set -g @catppuccin_status_cpu_text_bg "#{l:#{cpu_bg_color}}"

set -g @catppuccin_battery_color "#{@thm_teal}"

# CPU plugin settings

set -g @cpu_low_fg_color "#{E:@thm_fg}"
set -g @cpu_medium_fg_color "#{E:@thm_yellow}"
set -g @cpu_high_fg_color "#{E:@thm_red}"

set -g @cpu_low_bg_color "#{E:@catppuccin_status_module_text_bg}"
set -g @cpu_medium_bg_color "#{E:@catppuccin_status_module_text_bg}"
set -g @cpu_high_bg_color "#{E:@catppuccin_status_module_text_bg}"

set -g @cpu_percentage_format "%2d%%"
set -g @cpu_medium_thresh "50"
set -g @cpu_high_thresh "80"

set -g @catppuccin_session_color "#{E:#{?client_prefix,#{@thm_peach},$(mode-or-sync-color '#{@thm_green}')}}"

#------------------------------------------------------------
# Window status
#------------------------------------------------------------
# TODO: probably make selected win text omit the dir name since its already present in tmux status line. Then the emphasis is more on "what are my OTHER windows"
set -g @catppuccin_window_current_number_color "#{@thm_peach}"
set -g @catppuccin_window_status_style "basic"

set -g @catppuccin_window_text "$win_text"
set -g @catppuccin_window_current_text "$win_text"

#------------------------------------------------------------
# Panes
#------------------------------------------------------------
set -g @catppuccin_pane_border_style "fg=#{@thm_overlay_0},bg=#{@thm_mantle}"
set -g @catppuccin_pane_active_border_style "fg=#{l:$(mode-or-sync-color '#{@thm_lavender}')},bg=#{@thm_mantle}"

if 'test -f $CTPN_PLUG_SCRIPT' \
  'run $CTPN_PLUG_SCRIPT' \
  'display "Seems catppuccin plugin is not installed (first-time setup), you may need to re-source"'

EOF

#------------------------------------------------------------
# IMPORTANT: all non-@-prefix variables here!
# https://github.com/catppuccin/tmux/blob/main/docs/reference/status-line.md#notes-for-tpm-users
#------------------------------------------------------------
tmux source - <<EOF # tmux treesitter funny, just breaking it up

#------------------------------------------------------------
# Status Line
#------------------------------------------------------------
set -g status-right-length 100
set -g status-left-length 100
set -g status-left ""
set -g status-right "#{E:@catppuccin_status_directory}"
set -ag status-right "#{E:@catppuccin_status_application}"
set -agF status-right "#{E:@catppuccin_status_cpu}"
set -agF status-right "#{E:@catppuccin_status_battery}"
set -ag status-right "#{E:@catppuccin_status_session}"

# Ugly-ish but functional
set -gF status-left "##{?pane_in_mode,#[bg=$mode_color]#[fg=#{@thm_mantle}]#[bold] COPY MODE #[reverse]#[default] ,}"

#------------------------------------------------------------
# General appearance
#------------------------------------------------------------
set -gF window-active-style 'bg=#{@thm_bg},fg=#{@thm_fg}'
set -gF window-style 'bg=#{@thm_mantle},fg=#{@thm_subtext_1}'


EOF
