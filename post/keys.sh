#!/bin/bash

shopt -s expand_aliases
alias bind='tmux bind'

not_tmux_pattern=$(echo "$TMUX_ESCAPED_PROGRAMS" | xargs | tr -s '[:space:]' '|')
not_tmux_pattern=${not_tmux_pattern%?}
if [[ -z $not_tmux_pattern ]]; then
    not_tmux_pattern="fzf|n?vim"
fi

# Best version, don't run a process for every keystroke... (especially not ps which causes crowdstrike and others to freak out)
# Using the powers of wrap.cpp and ../scripts/setup-wrappers
not_tmux_hacked="#{&&:#{>:#{@escape_nav_keys},0},#{!=:1,#{pane_in_mode}}}"

# As much as I love this version, its incorrect when you don't just literally run 'nvim' or 'fzf' in a way that tmux detects (foreground, man, piping)
not_tmux_fast="#{&&:#{m/r:^$not_tmux_pattern$,#{pane_current_command}},#{!=:1,#{pane_in_mode}}}"
# This version seems marginally faster than the other fully compliant one
not_tmux="pgrep '$not_tmux_pattern' | xargs ps -o tty= -o state= -p | grep -iqE '^#{s|/dev/||:pane_tty} +[^TXZ ]+'"
# So... combine them for fastest nav within nvim/fzf, but slower regular tmux nav :(
# Works pretty well!
not_tmux_hybrid="test $not_tmux_fast = 1 || $not_tmux"

split_args='-c "#{pane_current_path}"'
equalize='select-layout -E'

#TODO: remove debug
bind u display '#{@escape_nav_keys}'
bind 'C-u' set -gp @escape_nav_keys 0

#------------------------------------------------------------
# FZF (Ctrl-f/w/= below)
#------------------------------------------------------------
# This isn't working after my refactor, oops, cannot figure out why
# tmux setenv -g TMUX_FZF_LAUNCH_KEY "C-f"
# Have a workaround tho
bind "C-f" run -b '#{@fzf_scripts}/../main.sh'

function bind_escapable() {
    local key="$1"
    shift
    bind -n "$key" "$@"
    bind "$key" send-keys
    bind -T copy-mode-vi "$key" "$@"
}

function bind_escapable_vim_aware() {
    local key="$1"
    shift
    if [[ $_TMUX_ESCAPE_NAV_ENABLED = 1 ]]; then
        bind -n "$key" if -F "$not_tmux_hacked" send-keys "$*"
        bind "$key" if -F "$not_tmux_hacked" "$*" send-keys
    else
        # For whatver reason I'm having so much trouble getting bash and tmux to both play nice with quoting and/or braces
tmux source - <<EOF
        # bind -n "$key" if "$not_tmux_hybrid" send-keys { $* }
        bind -n "$key" if -F "$not_tmux_fast" send-keys { if "$not_tmux" send-keys { $* } }
        bind "$key" if -F "$not_tmux_fast" { if "$not_tmux" send-keys { $* } } send-keys
EOF
    fi
    bind -T copy-mode-vi "$key" "$@"
}

#------------------------------------------------------------
# HJKL utils
#------------------------------------------------------------

# Associative array is better but mac bash default version is 3.2, let's just workaround
hjkl=(h j k l)
arrows=(Left Up Down Right)
split_flags=(hb v vb h)
select_flags=(L D U R)
direction_names=(left top bottom right)
# kind of obvious but screw it
num_directions=4

function get_direction_index() {
    local i
    for ((i=0; i<num_directions; i++)); do
        if [[ ${hjkl[$i]} == "$1" || ${arrows[$i]} == "$1" ]]; then
            echo $i
            return 0
        fi
    done
    echo -1
    return 1
}

function do_split() {
    i=$(get_direction_index "$1")
    echo "split-window -${split_flags[$i]} $split_args; $equalize"
}

function do_select_pane() {
    i=$(get_direction_index "$1")
    echo "select-pane -${select_flags[$i]}"
}

#------------------------------------------------------------
# Panes
#------------------------------------------------------------

# Prefix-hjkl - Try to nav (if zoomed), otherwise split
function bind_direction_split() {
    i=$(get_direction_index "$1")
    direction_name="${direction_names[$i]}"
    bind "$1" if -F "#{==:#{window_zoomed_flag},1}" \
        "resize-pane -Z; if -F '#{==:#{pane_at_$direction_name},1}' '$(do_split "$1")' '$(do_select_pane "$1")'" \
        "$(do_split "$1")"
}

# Ctrl-hjkl (no prefix) directional nav for both regular/copy modes (vim aware)
function bind_direction_nav() {
    bind_escapable_vim_aware "C-$1" "$(do_select_pane "$1")"
}

for d in "${hjkl[@]}"; do
    bind_direction_split "$d"
    bind_direction_nav "$d"
done

# Ctrl . last-pane, else create pane to the right
bind_escapable "C-." if -F '#{>:#{window_panes},1}' 'last-pane' 'split-window -h -c "#{pane_current_path}"'

# Ctrl z/q zoom/quit

bind_escapable_vim_aware 'C-q' "kill-pane; $equalize"
bind_escapable 'C-z' resize-pane -Z

# Prefix + Ctrl-o "only pane" (kill others)
bind "C-o" kill-pane -a

# Alt-arrow nav (not vim aware)
for a in "${arrows[@]}"; do
    bind_escapable "M-$a" "$(do_select_pane "$a")"
done

# = - FZF pane layout
bind "=" run -b "#{@fzf_scripts}/pane.sh layout"
bind e "$equalize"

bind "C-s" setw synchronize-panes

# Default pane splitting with no bells/whistles
bind '"' split-window -v
bind % split-window -h

#------------------------------------------------------------
# Windows
#------------------------------------------------------------

# Ctrl-; to toggle with recent
# The quotes are kind of gross due to tmux
bind_escapable 'C-\;' last-window

# Ctrl+Alt vim keys for navigating windows
# Not sure why, but on iterm ctrl+alt is registering as ctrl+shift for these keys
bind_escapable 'C-H' previous-window
bind_escapable 'C-L' next-window

# Shift arrow to switch windows
bind_escapable 'S-Left'  previous-window
bind_escapable 'S-Right' next-window

# Prefix C-x kill window
bind "C-x" confirm kill-window

# Rename window
bind r command "rename-window '%%'"

# FZF switch window
bind "C-w" run -b "#{@fzf_switch_window}"

#------------------------------------------------------------
# Simple Native Binds
#------------------------------------------------------------
tmux source - <<EOF # hello treesitter :)

# Prefix (currently hacked with iTerm remap C-' to m-;
unbind C-b
set -g prefix "M-;"
bind "M-;" send-prefix

bind R source -F '#{@config_file}'

bind "C-Space" run -b "#{@fzf_scripts}/keybinding.sh"
bind "Space" show-wk-menu-root

# Copy Mode
# TODO: better copy mode plugins and workflows
bind v copy-mode
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
# Is zsh not sending prompt escape chars?
bind -T copy-mode-vi '[' send-keys -X previous-prompt
bind -T copy-mode-vi ']' send-keys -X next-prompt

EOF
