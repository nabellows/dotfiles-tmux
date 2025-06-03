#!/bin/bash

bind() {
    tmux 'bind' "$@"
}

POPUP="$TMUX_SCRIPTS_PATH/popup"
POPUP_NVIM_TERM="$TMUX_SCRIPTS_PATH/popup-nvim-term"
POPUP_WIN_SESH="tmux-popup-win-#{window_id}"

# Currently hacked with iTerm remap C-' to <m-;> ... note that it is double quoted here in the sh-syntax area so that it is actually quoted when subbed in tmux heredocs
PREFIX='M-\;'

tmux unbind C-b
tmux set -g prefix "$PREFIX"
# Prefer to use double-prefix for scratch popup, breaking the usual escaped-key pattern
# which is fine because when do I ever want to send <M-;> ? A non-escaped alternative
# such that its at least POSSIBLE to send the sequence is fine...
bind "'" send-prefix

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
if [[ $(uname) == "Darwin" ]]; then
    # This version seems marginally faster than the other fully compliant one
    not_tmux="pgrep '$not_tmux_pattern' | xargs ps -o tty= -o state= -p | grep -iqE '^#{s|/dev/||:pane_tty} +[^TXZ ]+'"
else
    not_tmux="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?$not_tmux_pattern$'"
fi
# So... combine them for fastest nav within nvim/fzf, but slower regular tmux nav :(
# Works pretty well!
not_tmux_hybrid="test $not_tmux_fast = 1 || $not_tmux"

#TODO: remove debug
bind u show -p
bind 'C-u' run "tmux show -p | grep -E '@is_($not_tmux_pattern)' | cut -d' ' -f1  | xargs -I{} tmux set -p {} 0; tmux set -p @escape_nav_keys 0"

split_args='-c "#{pane_current_path}"'
equalize='select-layout -E'

#------------------------------------------------------------
# Interesting stuff, fzf, popups...
#------------------------------------------------------------
bind R source -F '#{@config_file}'
bind "C-f" run -b '#{@fzf_scripts}/../main.sh'
bind "C-w" run -b "#{@fzf_switch_window}"
bind "=" run -b "#{@fzf_scripts}/pane.sh layout"

bind "C-Space" run -b "#{@fzf_scripts}/keybinding.sh"
bind "Space" show-wk-menu-root

bind "$PREFIX" run "$POPUP_NVIM_TERM"
# Still prefer this version as its marginally more responsive and I don't have much use for nvim-in-nvim (lazygit is solid, don't really need persistence for most workflows)
# Also, the embedded/remote editing is broken in the other for now (TODO, implement)
# Update: I added hella hacks to the nvim version so the embedded/remote editing is equivalent. Only gap right now is feels *slightly* more stuttery in nvim
bind C-g run "$TMUX_SCRIPTS_PATH/lazygit-popup"
# Somewhat convoluted, can perhaps add all the lazygit setup into core popup. POPUP_KEY not needed but helps nvim-session-args figure it out
bind g run "$TMUX_SCRIPTS_PATH/lazygit-popup nvim-term-session $POPUP_WIN_SESH-lazygit lazygit"
bind b run "$POPUP_NVIM_TERM btm"
bind C-t run "$POPUP_NVIM_TERM"
bind C-n run "$POPUP -T nvim nvim-session $POPUP_WIN_SESH-nvim"
bind C-m run "POPUP_KEY=spt $POPUP_NVIM_TERM spotify_player"

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

bind e "$equalize"

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
if [[ $(uname) == "Darwin" ]]; then
    # Not sure why, but on iterm ctrl+alt is registering as ctrl+shift for these keys on mac
    bind_escapable 'C-H' previous-window
    bind_escapable 'C-L' next-window
else
    bind_escapable 'C-M-h' previous-window
    bind_escapable 'C-M-l' next-window
fi

# Shift arrow to switch windows
bind_escapable 'S-Left'  previous-window
bind_escapable 'S-Right' next-window

bind "C-x" confirm kill-window

#------------------------------------------------------------
# Simple Native Binds
#------------------------------------------------------------
bind r command "rename-window '%%'"
bind "C-s" setw synchronize-panes
# Copy Mode
# TODO: better copy mode plugins and workflows
bind v copy-mode
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
# Is zsh not sending prompt escape chars?
bind -T copy-mode-vi '[' send-keys -X previous-prompt
bind -T copy-mode-vi ']' send-keys -X next-prompt

_TMUX_SOURCE_INSTANT_KEYS=1 . "$HOME/.zshkeys"

