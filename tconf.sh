#!/bin/bash

shopt -s nullglob
cd "$TMUX_CONFIG_DIR" || exit 2

# DEBUG=1

function debug() {
  if [[ "$DEBUG" -eq 1 ]]; then
    tmux display "$*"
    sleep 0.5
  fi
}

function source_file() {
  f=$(realpath "$1")
  if [[ $f = *.sh ]]; then
    tmux run "$f"
    debug "ran $f as shell"
  elif [[ $f = *.conf ]]; then
    tmux source "$f"
    debug "ran $f as conf"
  fi
}

# Probably want a more elegant system, but pre/ is made for pre-plugin execution
# After second thoughts, I'm already ending up with implicit dependencies such as that between keys->fzf (depends on fzf variables)
# It only happens to work for now because of the coincidental alphabetical order
# Maybe tconf.sh shouldn't exist and require explicit registry in tmux.conf... (how often would I add new files?)
for f in pre/*; do
  if [[ -f "$f" ]]; then
    source_file "$f"
  fi
done

source_file ./plugins.sh

