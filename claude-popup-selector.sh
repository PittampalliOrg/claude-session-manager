#!/usr/bin/env bash
# Claude Session Selector for tmux popup

set -euo pipefail

# Get all sessions
sessions=$(/home/vpittamp/claude-sesh-enhanced.sh --get-sessions-only)

if [ -z "$sessions" ]; then
    echo "No Claude sessions found"
    sleep 2
    exit 0
fi

# Select session using fzf
selected=$(echo "$sessions" | column -t -s $'\t' | \
    fzf --height=100% \
        --layout=reverse \
        --info=inline \
        --prompt="Select Claude session: " \
        --header="Navigate with arrows, Enter to select, ESC to cancel" \
        --preview="echo {}")

# Exit if nothing selected
if [ -z "$selected" ]; then
    exit 0
fi

# Extract session ID (second to last field)
session_id=$(echo "$selected" | awk '{print $(NF-1)}')

# Resume the session
echo "Resuming session ${session_id:0:8}..."
claude --resume "$session_id"