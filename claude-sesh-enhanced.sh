#!/usr/bin/env bash

# Claude + Sesh Enhanced Integration
# Modern CLI interface using fzf, gum, sesh, and zoxide

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
PROJECTS_DIR="${CLAUDE_DIR}/projects"

# Terminal cleanup function
cleanup_terminal() {
    # Only cleanup if we're in an interactive terminal
    if [ -t 0 ] && [ -t 1 ]; then
        # Disable application keypad mode
        printf '\033[?1l\033>' 2>/dev/null || true
        # Reset terminal settings to sane defaults
        stty sane 2>/dev/null || true
    fi
}

# Only set up cleanup trap for interactive sessions (not subprocesses)
if [ -t 0 ] && [ -t 1 ] && [ -z "${CLAUDE_SESH_SUBPROCESS:-}" ]; then
    trap cleanup_terminal EXIT INT TERM
fi

# Check for required tools
check_dependencies() {
    local missing=()
    
    for tool in fzf gum sesh zoxide jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        gum style \
            --foreground 196 \
            --border double \
            --border-foreground 196 \
            --padding "1 2" \
            --margin "1" \
            "Missing required tools: ${missing[*]}" \
            "Please install them first."
        exit 1
    fi
}

# Get session metadata including working directory
get_session_metadata() {
    local file="$1"
    local session_id=$(basename "$file" .jsonl)
    
    # Extract metadata from first user message
    local metadata=""
    while IFS= read -r line; do
        if [ -z "$line" ] || ! echo "$line" | grep -q '^{'; then
            continue
        fi
        
        local parsed=$(echo "$line" | jq -r '
            select(.type=="user" and .message.content != null) |
            {
                timestamp: .timestamp,
                cwd: .cwd,
                branch: .gitBranch,
                message: (
                    if .message.content | type == "array" then 
                        .message.content[0].text // ""
                    elif .message.content | type == "string" then
                        .message.content
                    else 
                        ""
                    end | 
                    if type == "string" then . else "" end |
                    split("\n")[0] | .[0:80]
                )
            }
        ' 2>/dev/null || true)
        
        if [ -n "$parsed" ] && [ "$parsed" != "null" ]; then
            metadata="$parsed"
            break
        fi
    done < "$file"
    
    # Get summary if exists
    local summary=$(grep '"type":"summary"' "$file" 2>/dev/null | head -1 | jq -r '.summary // empty' 2>/dev/null || echo "")
    
    # Get line count for preview
    local lines=$(wc -l < "$file" 2>/dev/null || echo "0")
    
    # Combine into single JSON object
    if [ -n "$metadata" ]; then
        echo "$metadata" | jq --arg sid "$session_id" --arg summary "$summary" --arg lines "$lines" \
            '. + {session_id: $sid, summary: $summary, lines: $lines}'
    else
        echo "{}"
    fi
}

# Find all config sessions for a given path from sesh.toml
find_config_sessions_for_path() {
    local target_path="$1"
    local config_file="$HOME/.config/sesh/sesh.toml"
    local sessions=()
    
    # If config doesn't exist, return empty
    if [ ! -f "$config_file" ]; then
        return
    fi
    
    # Expand tilde in target path for comparison
    target_path="${target_path/#\~/$HOME}"
    target_path=$(readlink -f "$target_path" 2>/dev/null || echo "$target_path")
    
    # Parse TOML to find matching sessions
    local in_session=false
    local current_name=""
    local current_path=""
    
    while IFS= read -r line; do
        # Check for session start
        if [[ "$line" =~ ^\[\[session\]\] ]]; then
            in_session=true
            current_name=""
            current_path=""
        elif [ "$in_session" = true ]; then
            # Extract name
            if [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                current_name="${BASH_REMATCH[1]}"
            # Extract path
            elif [[ "$line" =~ ^path[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                current_path="${BASH_REMATCH[1]}"
                # Expand tilde in config path
                current_path="${current_path/#\~/$HOME}"
                current_path=$(readlink -f "$current_path" 2>/dev/null || echo "$current_path")
                
                # Check if paths match
                if [ "$current_path" = "$target_path" ] && [ -n "$current_name" ]; then
                    sessions+=("$current_name")
                fi
            # Check for next section or end of session
            elif [[ "$line" =~ ^\[\[ ]] || [ -z "$line" ]; then
                in_session=false
            fi
        fi
    done < "$config_file"
    
    # Return all matching sessions
    printf '%s\n' "${sessions[@]}"
}

# Get session icon based on directory
get_session_icon() {
    local dir="$1"
    
    # Check if it's a git repository
    if git -C "$dir" rev-parse --git-dir &>/dev/null 2>&1; then
        echo "🔸"  # Git repo
    elif [[ "$dir" == */nixos* ]] || [[ "$dir" == */nix* ]]; then
        echo "❄️"  # Nix
    elif [[ "$dir" == */.config* ]]; then
        echo "⚙️"  # Config
    elif [[ "$dir" == "$HOME" ]]; then
        echo "🏠"  # Home
    else
        echo "📁"  # Regular directory
    fi
}

# Convert directory path to sesh session name
dir_to_sesh_name() {
    local dir="$1"
    local interactive="${2:-true}"
    
    # First check if there's a config session for this path
    local config_session=$(select_session_for_path "$dir" true "$interactive")
    if [ -n "$config_session" ]; then
        echo "$config_session"
        return
    fi
    
    # Evaluate symlinks to get real path
    dir=$(readlink -f "$dir" 2>/dev/null || echo "$dir")
    
    # Check if it's a git repository
    if git -C "$dir" rev-parse --git-dir &>/dev/null 2>&1; then
        local toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$toplevel" ]; then
            local basename=$(basename "$toplevel")
            local relpath=${dir#$toplevel}
            if [ -n "$relpath" ]; then
                echo "${basename}${relpath}" | tr '.:' '__'
            else
                echo "$basename" | tr '.:' '__'
            fi
        else
            basename "$dir" | tr '.:' '__'
        fi
    else
        basename "$dir" | tr '.:' '__'
    fi
}

# Select session name for a path
select_session_for_path() {
    local dir="$1"
    local prefer_existing="${2:-true}"
    local interactive="${3:-true}"
    
    local config_sessions=($(find_config_sessions_for_path "$dir"))
    
    if [ ${#config_sessions[@]} -eq 0 ]; then
        return
    elif [ ${#config_sessions[@]} -eq 1 ]; then
        echo "${config_sessions[0]}"
    else
        if [ "$prefer_existing" = true ]; then
            for session in "${config_sessions[@]}"; do
                if tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -q "^${session}$"; then
                    echo "$session"
                    return
                fi
            done
        fi
        
        if [ "$interactive" = true ] && [ -t 0 ] && [ -t 1 ]; then
            # Use gum choose for interactive selection
            echo "${config_sessions[@]}" | tr ' ' '\n' | \
                gum choose --header "Multiple sesh configs available for $dir:"
        else
            echo "${config_sessions[0]}"
        fi
    fi
}

# Format session for display in fzf
format_session_display() {
    local metadata="$1"
    
    local session_id=$(echo "$metadata" | jq -r '.session_id // "unknown"')
    local cwd=$(echo "$metadata" | jq -r '.cwd // "unknown"')
    local message=$(echo "$metadata" | jq -r '.message // ""')
    local summary=$(echo "$metadata" | jq -r '.summary // ""')
    local timestamp=$(echo "$metadata" | jq -r '.timestamp // "unknown"')
    local lines=$(echo "$metadata" | jq -r '.lines // "0"')
    
    # Format timestamp
    if [ "$timestamp" != "unknown" ]; then
        timestamp=$(date -d "$timestamp" "+%m/%d %H:%M" 2>/dev/null || echo "")
    fi
    
    # Get session icon
    local icon=$(get_session_icon "$cwd")
    
    # Get sesh name
    local sesh_name=$(dir_to_sesh_name "$cwd" false)
    
    # Format display with fixed widths for alignment
    local display_msg=""
    if [ -n "$summary" ] && [ "$summary" != "null" ]; then
        display_msg="$summary"
    else
        display_msg="$message"
    fi
    
    # Truncate display message to fit
    display_msg="${display_msg:0:60}"
    
    # Format: icon | timestamp | sesh_name | message | session_id | cwd
    printf "%s\t%s\t%-15s\t%-60s\t%s\t%s\n" \
        "$icon" \
        "$timestamp" \
        "${sesh_name:0:15}" \
        "$display_msg" \
        "$session_id" \
        "$cwd"
}

# Format conversation for viewing
format_conversation() {
    local session_file="$1"
    local format_type="${2:-pretty}"  # pretty, markdown, plain, fast
    local max_lines="${3:-200}"  # Limit lines for performance
    
    if [ ! -f "$session_file" ]; then
        gum style --foreground 196 "Session file not found"
        return 1
    fi
    
    # Fast mode - just extract text quickly
    if [ "$format_type" = "fast" ]; then
        tail -n "$max_lines" "$session_file" | \
        jq -r 'select(.type == "message") | 
            "\(.timestamp | split("T")[0]) \(.timestamp | split("T")[1] | split(".")[0] // ""): [\(.message.role | ascii_upcase)] \(.message.content[0].text // .message.content // "")"' 2>/dev/null
        return 0
    fi
    
    # Get line count for progress
    local line_count=$(wc -l < "$session_file")
    
    # For large files, show only recent messages
    local input_cmd="cat"
    if [ "$line_count" -gt "$max_lines" ]; then
        gum style --foreground 214 "Showing last $max_lines of $line_count messages (for performance)"
        echo ""
        input_cmd="tail -n $max_lines"
    fi
    
    $input_cmd "$session_file" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        # Parse line once, extract all fields
        local parsed=$(echo "$line" | jq -r '
            [.type // "", 
             .timestamp // "", 
             (.message.role // ""),
             (if .message.content | type == "array" then 
                .message.content[0].text // ""
              elif .message.content | type == "string" then
                .message.content
              else 
                ""
              end),
             (.summary // "")
            ] | @tsv' 2>/dev/null)
        
        [ -z "$parsed" ] && continue
        
        IFS=$'\t' read -r msg_type timestamp role content summary <<< "$parsed"
        [ -z "$msg_type" ] && continue
        
        # Format timestamp if present
        if [ -n "$timestamp" ] && [ "$timestamp" != "null" ] && [ "$timestamp" != "" ]; then
            timestamp=$(date -d "$timestamp" "+%m/%d %H:%M" 2>/dev/null || echo "$timestamp")
        fi
        
        case "$msg_type" in
            "message")
                # Use role to determine user vs assistant
                if [ "$role" = "user" ]; then
                        if [ "$format_type" = "markdown" ]; then
                        echo "### 👤 USER [$timestamp]"
                        echo ""
                        echo "$content"
                        echo ""
                    elif [ "$format_type" = "plain" ]; then
                        echo "USER [$timestamp]:"
                        echo "$content"
                        echo ""
                    else
                        gum style --foreground 45 --bold "👤 USER [$timestamp]"
                        if [ -n "$content" ]; then
                            echo "$content" | gum style --margin "0 2" --foreground 250
                        fi
                        echo ""
                    fi
                elif [ "$role" = "assistant" ]; then
                    if [ "$format_type" = "markdown" ]; then
                        echo "### 🤖 CLAUDE [$timestamp]"
                        echo ""
                        echo "$content"
                        echo ""
                    elif [ "$format_type" = "plain" ]; then
                        echo "CLAUDE [$timestamp]:"
                        echo "$content"
                        echo ""
                    else
                        gum style --foreground 212 --bold "🤖 CLAUDE [$timestamp]"
                        if [ -n "$content" ]; then
                            echo "$content" | gum style --margin "0 2" --foreground 252
                        fi
                        echo ""
                    fi
                fi
                ;;
                
            "summary")
                if [ -n "$summary" ] && [ "$summary" != "null" ] && [ "$summary" != "" ]; then
                    if [ "$format_type" = "markdown" ]; then
                        echo "## 📝 Summary"
                        echo "$summary"
                        echo ""
                    elif [ "$format_type" = "plain" ]; then
                        echo "SUMMARY: $summary"
                        echo ""
                    else
                        gum style --foreground 214 --bold "📝 SUMMARY"
                        echo "$summary" | gum style --margin "0 2" --italic
                        echo ""
                    fi
                fi
                ;;
        esac
    done < "$session_file"
}

# View conversation with gum pager
view_conversation() {
    local session_id="$1"
    
    # Find session file
    local session_file=$(find "$PROJECTS_DIR" -name "*${session_id}*.jsonl" 2>/dev/null | head -1)
    
    if [ -z "$session_file" ] || [ ! -f "$session_file" ]; then
        gum style --foreground 196 --border rounded --padding "1 2" \
            "Session not found: ${session_id:0:12}..."
        return 1
    fi
    
    # Get session metadata
    local metadata=$(get_session_metadata "$session_file")
    local cwd=$(echo "$metadata" | jq -r '.cwd // "Unknown"')
    local lines=$(echo "$metadata" | jq -r '.lines // "0"')
    
    # Header
    gum style \
        --foreground 212 \
        --border double \
        --border-foreground 212 \
        --padding "1 2" \
        --align center \
        "Claude Session Viewer" \
        "" \
        "📍 $cwd" \
        "🆔 ${session_id:0:12}..." \
        "📝 $lines lines"
    
    echo ""
    
    # Show options
    local action=$(gum choose \
        "📖 View Conversation" \
        "📤 Export as Markdown" \
        "📋 Copy Session ID" \
        "🔙 Back")
    
    case "$action" in
        "📖 View Conversation")
            format_conversation "$session_file" "pretty" | gum pager
            ;;
        "📤 Export as Markdown")
            export_conversation "$session_id"
            ;;
        "📋 Copy Session ID")
            echo -n "$session_id" | clipboard 2>/dev/null || echo "$session_id"
            gum style --foreground 82 "✅ Session ID copied"
            ;;
        *)
            return 0
            ;;
    esac
}

# Export conversation to markdown
export_conversation() {
    local session_id="$1"
    
    # Find session file
    local session_file=$(find "$PROJECTS_DIR" -name "*${session_id}*.jsonl" 2>/dev/null | head -1)
    
    if [ -z "$session_file" ] || [ ! -f "$session_file" ]; then
        gum style --foreground 196 "Session not found: ${session_id:0:12}..."
        return 1
    fi
    
    local export_file="claude-session-${session_id:0:8}-$(date +%Y%m%d-%H%M%S).md"
    format_conversation "$session_file" "markdown" > "$export_file"
    gum style --foreground 82 "✅ Exported to $export_file"
    return 0
}

# Generate preview for a session
generate_session_preview() {
    local selection="$1"
    
    # Parse the selection using awk to get last two fields
    local session_id=$(echo "$selection" | awk '{print $(NF-1)}')
    local cwd=$(echo "$selection" | awk '{print $NF}')
    
    # Find the session file
    local file=$(find "$PROJECTS_DIR" -name "*${session_id}*.jsonl" 2>/dev/null | head -1)
    
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "Session file not found"
        return
    fi
    
    # Get metadata
    local metadata=$(get_session_metadata "$file")
    
    echo "╭─ Claude Session Preview ─────────────────────────────╮"
    echo "│"
    echo "│ 📍 Directory: $cwd"
    echo "│ 🆔 Session: $session_id"
    
    local branch=$(echo "$metadata" | jq -r '.branch // ""')
    if [ -n "$branch" ] && [ "$branch" != "null" ]; then
        echo "│ 🌿 Git Branch: $branch"
    fi
    
    local lines=$(echo "$metadata" | jq -r '.lines // "0"')
    echo "│ 📝 Lines: $lines"
    echo "│"
    echo "├─ Recent Messages ────────────────────────────────────┤"
    echo "│"
    
    # Show last few messages
    tail -5 "$file" 2>/dev/null | while IFS= read -r line; do
        local msg_type=$(echo "$line" | jq -r '.type // ""' 2>/dev/null)
        local msg_preview=""
        
        if [ "$msg_type" = "user" ]; then
            msg_preview=$(echo "$line" | jq -r '
                if .message.content | type == "array" then 
                    .message.content[0].text // ""
                elif .message.content | type == "string" then
                    .message.content
                else 
                    ""
                end | .[0:60]
            ' 2>/dev/null || echo "")
            [ -n "$msg_preview" ] && echo "│ 👤 ${msg_preview:0:50}..."
        elif [ "$msg_type" = "assistant" ]; then
            msg_preview=$(echo "$line" | jq -r '.message.content[0].text // "" | .[0:60]' 2>/dev/null || echo "")
            [ -n "$msg_preview" ] && echo "│ 🤖 ${msg_preview:0:50}..."
        fi
    done
    
    echo "│"
    echo "╰──────────────────────────────────────────────────────╯"
}

# Get all sessions formatted for fzf
get_all_sessions() {
    local max_sessions="${1:-50}"
    
    for file in $(find "$PROJECTS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' | \
                  sort -rn | head -"$max_sessions" | cut -d' ' -f2); do
        local metadata=$(get_session_metadata "$file")
        
        if [ "$metadata" != "{}" ]; then
            format_session_display "$metadata"
        fi
    done
}

# Get sessions by zoxide ranking
get_sessions_by_zoxide() {
    local found_sessions=()
    
    # Get top directories from zoxide
    while IFS= read -r dir; do
        # Find Claude sessions for this directory
        for file in $(find "$PROJECTS_DIR" -name "*.jsonl" -type f); do
            local metadata=$(get_session_metadata "$file")
            local cwd=$(echo "$metadata" | jq -r '.cwd // ""')
            
            if [ "$cwd" = "$dir" ] && [ "$metadata" != "{}" ]; then
                found_sessions+=("$(format_session_display "$metadata")")
            fi
        done
    done < <(zoxide query -l | head -30)
    
    printf '%s\n' "${found_sessions[@]}"
}

# Search sessions
search_sessions() {
    local search_term="$1"
    
    grep -l "$search_term" "${PROJECTS_DIR}"/*/*.jsonl 2>/dev/null | while IFS= read -r file; do
        local metadata=$(get_session_metadata "$file")
        if [ "$metadata" != "{}" ]; then
            format_session_display "$metadata"
        fi
    done
}

# Connect to session using sesh
connect_and_resume() {
    local session_id="$1"
    local cwd="$2"
    
    # Get sesh session name
    local sesh_name=$(dir_to_sesh_name "$cwd" true)
    
    # Show connection info with gum
    gum style \
        --foreground 212 \
        --border rounded \
        --border-foreground 212 \
        --padding "1 2" \
        --margin "1" \
        "Resuming Claude Session" \
        "" \
        "📍 Directory: $cwd" \
        "🏷️  Sesh Name: $sesh_name" \
        "🆔 Session ID: ${session_id:0:8}..."
    
    # Check if directory exists
    if [ ! -d "$cwd" ]; then
        if gum confirm "Directory $cwd does not exist. Create it?"; then
            mkdir -p "$cwd"
        else
            gum style --foreground 196 "Aborting..."
            exit 1
        fi
    fi
    
    # Create a unique window name for this Claude session
    local window_name="claude-${session_id:0:8}"
    
    # Check if tmux session exists
    if tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -q "^${sesh_name}$"; then
        # Session exists
        if [ -n "${TMUX:-}" ]; then
            # We're inside tmux - switch to the session first
            tmux switch-client -t "$sesh_name"
            # Create new window at the end with -a flag and unique name
            tmux new-window -a -t "$sesh_name" -c "$cwd" -n "$window_name" 2>/dev/null || {
                # Window might already exist, switch to it
                tmux select-window -t "$sesh_name:$window_name" 2>/dev/null || \
                tmux new-window -a -t "$sesh_name" -c "$cwd" -n "$window_name-$(date +%s)"
            }
            # Send the resume command to the current window
            tmux send-keys "claude --resume $session_id" C-m
        else
            # We're outside tmux - create window and attach
            tmux new-window -a -t "$sesh_name" -c "$cwd" -n "$window_name" 2>/dev/null || {
                # Window might already exist, create with timestamp
                window_name="$window_name-$(date +%s)"
                tmux new-window -a -t "$sesh_name" -c "$cwd" -n "$window_name"
            }
            tmux send-keys -t "$sesh_name:$window_name" "claude --resume $session_id" C-m
            tmux attach-session -t "$sesh_name" \; select-window -t "$window_name"
        fi
    else
        # Session doesn't exist, create it
        tmux new-session -d -s "$sesh_name" -c "$cwd" -n "$window_name"
        tmux send-keys -t "$sesh_name:$window_name" "claude --resume $session_id" C-m
        
        if [ -n "${TMUX:-}" ]; then
            tmux switch-client -t "$sesh_name"
        else
            tmux attach-session -t "$sesh_name"
        fi
    fi
}

# Interactive session selector with fzf
select_with_fzf() {
    local mode="${1:-all}"  # all, zoxide, search
    local search_term="${2:-}"
    
    # Get sessions based on mode
    local sessions
    case "$mode" in
        zoxide)
            sessions=$(get_sessions_by_zoxide)
            ;;
        search)
            sessions=$(search_sessions "$search_term")
            ;;
        *)
            sessions=$(get_all_sessions)
            ;;
    esac
    
    # Check if we have any sessions
    if [ -z "$sessions" ]; then
        gum style --foreground 196 "No sessions found"
        return 1
    fi
    
    # Build the fzf command with --expect for reliable key detection
    local result
    if [ -n "${TMUX:-}" ]; then
        # Inside tmux: use fzf-tmux for popup
        result=$(echo "$sessions" | column -t -s $'\t' | \
            fzf-tmux -p 85%,75% \
                --ansi \
                --no-sort \
                --layout=reverse \
                --info=inline \
                --border-label ' 🤖 Claude Sessions ' \
                --prompt '⚡ ' \
                --header $'Select session\n  F2: View  F3: Export  F4: Menu  Enter: Resume  ESC: Cancel' \
                --expect=f2,f3,f4 \
                --bind 'ctrl-p:toggle-preview' \
                --preview-window 'right:50%:wrap'
        )
    else
        # Outside tmux: use regular fzf
        result=$(echo "$sessions" | column -t -s $'\t' | \
            fzf \
                --height=90% \
                --ansi \
                --no-sort \
                --layout=reverse \
                --info=inline \
                --border=rounded \
                --border-label=' 🤖 Claude Sessions ' \
                --prompt='⚡ ' \
                --header=$'Select session\n  F2: View  F3: Export  F4: Menu  Enter: Resume  ESC: Cancel' \
                --expect=f2,f3,f4 \
                --bind 'ctrl-p:toggle-preview' \
                --preview-window 'right:50%:wrap'
        )
    fi
    
    # Parse the result
    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)
    
    if [ -n "$selected" ]; then
        # Extract session_id and cwd from selection
        local session_id=$(echo "$selected" | awk '{print $(NF-1)}')
        local cwd=$(echo "$selected" | awk '{print $NF}')
        
        # Handle different keys
        case "$key" in
            f2)
                # View conversation
                view_conversation "$session_id"
                # After viewing, ask what to do next
                if gum confirm "Resume this session?"; then
                    connect_and_resume "$session_id" "$cwd"
                else
                    # Recurse to show list again
                    select_with_fzf "$mode" "$search_term"
                fi
                ;;
            f3)
                # Export conversation
                export_conversation "$session_id"
                gum style --foreground 82 "✅ Export complete"
                # Ask what to do next
                if gum confirm "Resume this session?"; then
                    connect_and_resume "$session_id" "$cwd"
                else
                    select_with_fzf "$mode" "$search_term"
                fi
                ;;
            f4)
                # Show action menu in popup if in tmux
                if [ -n "${TMUX:-}" ]; then
                    tmux display-popup -E -w 70% -h 60% \
                        "export CLAUDE_SESSION_ID='$session_id'; \
                         export CLAUDE_SESSION_CWD='$cwd'; \
                         /home/vpittamp/claude-sesh-enhanced.sh --menu-only"
                else
                    show_action_menu "$session_id" "$cwd"
                fi
                ;;
            *)
                # Default: resume session
                connect_and_resume "$session_id" "$cwd"
                ;;
        esac
    fi
}

# Show action menu for a session
show_action_menu() {
    local session_id="$1"
    local cwd="$2"
    
    # Get session info for display
    local short_id="${session_id:0:8}"
    local dir_name=$(basename "$cwd")
    
    gum style \
        --foreground 212 \
        --border rounded \
        --border-foreground 212 \
        --padding "1 2" \
        --margin "1" \
        "Session: $short_id" \
        "Directory: $cwd"
    
    local action=$(gum choose \
        "▶️  Resume Session" \
        "📖 View Conversation" \
        "📤 Export to Markdown" \
        "📋 Copy Session ID" \
        "🗑️  Delete Session" \
        "🔙 Back to List" \
        "❌ Cancel")
    
    case "$action" in
        "▶️  Resume Session")
            connect_and_resume "$session_id" "$cwd"
            ;;
        "📖 View Conversation")
            view_conversation "$session_id"
            # After viewing, show menu again
            show_action_menu "$session_id" "$cwd"
            ;;
        "📤 Export to Markdown")
            export_conversation "$session_id"
            show_action_menu "$session_id" "$cwd"
            ;;
        "📋 Copy Session ID")
            echo -n "$session_id" | clipboard 2>/dev/null || echo "$session_id"
            gum style --foreground 82 "✅ Session ID copied"
            show_action_menu "$session_id" "$cwd"
            ;;
        "🗑️  Delete Session")
            if gum confirm "Delete session $short_id?"; then
                delete_session "$session_id"
                gum style --foreground 82 "✅ Session deleted"
                # Return to main list
                select_with_fzf
            else
                show_action_menu "$session_id" "$cwd"
            fi
            ;;
        "🔙 Back to List")
            select_with_fzf
            ;;
        *)
            # Cancel - do nothing
            ;;
    esac
}

# Create a centered, styled menu
show_styled_menu() {
    local header="$1"
    shift
    local options=("$@")
    
    # Use gum choose with consistent styling
    printf '%s\n' "${options[@]}" | gum choose \
        --header "$header" \
        --header.foreground 212 \
        --cursor.foreground 214 \
        --selected.foreground 82 \
        --height $((${#options[@]} + 2))
}

# Interactive conversation viewer using fzf with preview
view_conversation_interactive() {
    local session_file="$1"
    local session_id="$2"
    local cwd="$3"
    local short_id="${session_id:0:8}"
    
    # Debug: Check if we're being called
    # gum style --foreground 214 "Debug: Entering view_conversation_interactive"
    # sleep 1
    
    # Check if session file exists
    if [ ! -f "$session_file" ]; then
        gum style --foreground 196 "Error: Session file not found: $session_file"
        sleep 2
        return 1
    fi
    
    # Create action menu items
    local actions="🔙 Back to Actions Menu
📤 Export to Markdown
▶️  Resume Session
📖 View in Full Screen
❌ Exit Browser"
    
    # Show menu with conversation preview
    local selected
    
    # Use conditional execution instead of variable expansion
    if [ -n "${TMUX:-}" ]; then
        # Inside tmux - use fzf-tmux
        selected=$(echo "$actions" | fzf-tmux -p 90%,85% \
            --ansi \
            --header "═══ Session: $short_id | Directory: $cwd ═══
Navigate: ↑↓ arrows | Preview: Shift+↑↓ or PgUp/PgDn | Select: Enter | Back: ESC" \
            --preview "cat '$session_file' 2>/dev/null | jq -r 'select(.type == \"message\") | .message.content[0].text // empty' 2>/dev/null | head -500 || echo 'Loading conversation...'" \
            --preview-window "down:75%:wrap:border-top" \
            --bind "shift-up:preview-page-up" \
            --bind "shift-down:preview-page-down" \
            --bind "ctrl-u:preview-half-page-up" \
            --bind "ctrl-d:preview-half-page-down" \
            --no-info \
            --border double \
            --border-label " 📖 Conversation Viewer " \
            --margin "1,2" 2>/dev/null)
    else
        # Outside tmux - use regular fzf
        selected=$(echo "$actions" | fzf \
            --ansi \
            --header "═══ Session: $short_id | Directory: $cwd ═══
Navigate: ↑↓ arrows | Preview: Shift+↑↓ or PgUp/PgDn | Select: Enter | Back: ESC" \
            --preview "cat '$session_file' 2>/dev/null | jq -r 'select(.type == \"message\") | .message.content[0].text // empty' 2>/dev/null | head -500 || echo 'Loading conversation...'" \
            --preview-window "down:75%:wrap:border-top" \
            --bind "shift-up:preview-page-up" \
            --bind "shift-down:preview-page-down" \
            --bind "ctrl-u:preview-half-page-up" \
            --bind "ctrl-d:preview-half-page-down" \
            --no-info \
            --border double \
            --border-label " 📖 Conversation Viewer " \
            --margin "1,2" 2>/dev/null)
    fi
    
    # Debug: Check what was selected
    # if [ -z "$selected" ]; then
    #     gum style --foreground 214 "Debug: Nothing selected (ESC or error)"
    # else
    #     gum style --foreground 214 "Debug: Selected: $selected"
    # fi
    # sleep 1
    
    # Return the selected action (or empty if ESC was pressed)
    echo "$selected"
}

# Delete a session
delete_session() {
    local session_id="$1"
    local session_file=$(find "$PROJECTS_DIR" -name "*${session_id}*.jsonl" 2>/dev/null | head -1)
    
    if [ -n "$session_file" ] && [ -f "$session_file" ]; then
        rm "$session_file"
        return 0
    else
        gum style --foreground 196 "Session file not found"
        return 1
    fi
}

# Find session file by ID
find_session_file() {
    local session_id="$1"
    find "$PROJECTS_DIR" -name "*${session_id}*.jsonl" 2>/dev/null | head -1
}

# Browse mode - creates ephemeral tmux session inside popup
browse_mode() {
    if [ -n "${TMUX:-}" ]; then
        # Create ephemeral session name
        local session_name="claude-browser-$$"
        
        # Kill any existing session with same name
        tmux kill-session -t "$session_name" 2>/dev/null || true
        
        # Create detached tmux session
        tmux new-session -d -s "$session_name" -c "$PWD" \
            "CLAUDE_SESH_SUBPROCESS=1 CLAUDE_BROWSER_SESSION='$session_name' exec /home/vpittamp/claude-sesh-enhanced.sh --browse-internal"
        
        # Display the session in a popup (not switch to it)
        tmux display-popup -E -w 85% -h 75% \
            -d '#{pane_current_path}' \
            "tmux attach-session -t '$session_name'"
        
        # Clean up the session after popup closes
        tmux kill-session -t "$session_name" 2>/dev/null || true
    else
        # Not in tmux - just run directly
        browse_internal
    fi
}

# Menu-only mode for F4 popup calls
menu_only() {
    local session_id="${CLAUDE_SESSION_ID:-${1:-}}"
    local cwd="${CLAUDE_SESSION_CWD:-${2:-}}"
    
    # Check if we have required parameters
    if [ -z "$session_id" ] || [ -z "$cwd" ]; then
        gum style --foreground 196 "Error: Missing session information"
        echo "Usage: $0 --menu-only <session_id> <cwd>"
        exit 1
    fi
    
    local short_id="${session_id:0:8}"
    
    # Show session info in a centered box
    gum style \
        --foreground 212 \
        --border double \
        --border-foreground 212 \
        --padding "1 4" \
        --margin "2" \
        --align center \
        --width 60 \
        "Claude Session Actions" \
        "" \
        "📍 Session: $short_id" \
        "📂 Directory: $cwd"
    
    echo ""
    
    # Show action menu with better styling
    local action=$(show_styled_menu \
        "═══ Choose an Action ═══" \
        "▶️  Resume Session       " \
        "📖 View Conversation     " \
        "📤 Export to Markdown    " \
        "📋 Copy Session ID       " \
        "🗑️  Delete Session       " \
        "❌ Cancel                ")
    
    case "$(echo "$action" | xargs)" in
        "▶️  Resume Session"*)
            connect_and_resume "$session_id" "$cwd"
            ;;
        "📖 View Conversation"*)
            local session_file=$(find_session_file "$session_id")
            if [ -n "$session_file" ]; then
                local viewer_action
                viewer_action=$(view_conversation_interactive "$session_file" "$session_id" "$cwd")
                
                # Handle the selected action from the viewer
                case "$viewer_action" in
                    "🔙 Back to Actions Menu")
                        # Return to show the action menu again
                        menu_only "$session_id" "$cwd"
                        ;;
                    "📤 Export to Markdown")
                        export_conversation "$session_id"
                        gum style --foreground 82 "✅ Exported successfully"
                        sleep 2
                        menu_only "$session_id" "$cwd"
                        ;;
                    "▶️  Resume Session")
                        connect_and_resume "$session_id" "$cwd"
                        ;;
                    "📖 View in Full Screen")
                        # Fallback to full screen view with gum pager
                        format_conversation "$session_file" "pretty" | gum pager
                        menu_only "$session_id" "$cwd"
                        ;;
                    "❌ Exit Browser")
                        # Exit without recursion
                        ;;
                    *)
                        # ESC was pressed - go back to menu
                        menu_only "$session_id" "$cwd"
                        ;;
                esac
            else
                gum style --foreground 196 "Session file not found"
            fi
            ;;
        "📤 Export to Markdown"*)
            export_conversation "$session_id"
            gum style --foreground 82 "✅ Exported successfully"
            sleep 2
            ;;
        "📋 Copy Session ID"*)
            echo -n "$session_id" | clipboard 2>/dev/null || echo "$session_id"
            gum style --foreground 82 "✅ Session ID copied"
            sleep 2
            ;;
        "🗑️  Delete Session"*)
            if gum confirm "Delete session $short_id?"; then
                delete_session "$session_id"
                gum style --foreground 82 "✅ Session deleted"
            fi
            ;;
        *)
            # Cancel - do nothing
            ;;
    esac
}

# Browse internal - runs entirely within tmux popup or session
# This is the main browse interface that shows sessions and actions
browse_internal() {
    while true; do
        # Get all sessions with loading spinner
        local sessions
        sessions=$(gum spin --spinner dot --title "Loading Claude sessions..." -- /home/vpittamp/claude-sesh-enhanced.sh --get-sessions-only)
        
        if [ -z "$sessions" ]; then
            gum style --foreground 196 "No sessions found"
            sleep 2
            break
        fi
        
        # Count sessions for display
        local session_count=$(echo "$sessions" | wc -l)
        
        # Select session using gum filter (use more height)
        local selected=$(echo "$sessions" | column -t -s $'\t' | \
            gum filter \
                --placeholder "🔍 Select from $session_count sessions (ESC to exit)" \
                --indicator '▶' \
                --header 'Claude Session Browser')
        
        # Exit if nothing selected (ESC pressed)
        [ -z "$selected" ] && break
        
        # Extract session info
        local session_id=$(echo "$selected" | awk '{print $(NF-1)}')
        local cwd=$(echo "$selected" | awk '{print $NF}')
        local short_id="${session_id:0:8}"
        
        # Show session info in a centered box
        gum style \
            --foreground 212 \
            --border double \
            --border-foreground 212 \
            --padding "1 4" \
            --margin "2" \
            --align center \
            --width 60 \
            "Claude Session Selected" \
            "" \
            "📍 Session: $short_id" \
            "📂 Directory: $cwd"
        
        echo ""
        
        # Action menu loop - stay here until user chooses to go back or exit
        local done_with_session=false
        while [ "$done_with_session" = false ]; do
            # Show action menu with better styling
            local action=$(show_styled_menu \
                "═══ Choose an Action ═══" \
                "▶️  Resume Session       " \
                "🔙 Back to Sessions      " \
                "📖 View Conversation     " \
                "📤 Export to Markdown    " \
                "📋 Copy Session ID       " \
                "🗑️  Delete Session       " \
                "❌ Exit Browser          ")
            
            case "$(echo "$action" | xargs)" in
            *"Resume Session"*)
                # This will exit popup and resume in main terminal
                export CLAUDE_RESUME_ACTIVE=true
                connect_and_resume "$session_id" "$cwd"
                done_with_session=true
                break 2  # Break both loops
                ;;
            *"View Conversation"*)
                # Simplified: Just use gum pager for now
                local session_file=$(find_session_file "$session_id")
                if [ -n "$session_file" ]; then
                    # Show header
                    gum style \
                        --foreground 212 \
                        --border rounded \
                        --padding "1 2" \
                        "Viewing Session: $short_id" \
                        "Press q or ESC to return to menu"
                    
                    # View the conversation using fast mode for performance
                    # First show a loading message
                    echo "Loading conversation..." | gum style --foreground 214
                    format_conversation "$session_file" "fast" 500 | gum pager || true
                    
                    # Show a transition message
                    gum style --foreground 82 "Returning to action menu..."
                    sleep 0.5
                    
                    # Stay in the action menu loop
                else
                    gum style --foreground 196 "Session file not found"
                    sleep 2
                fi
                ;;
            *"Export to Markdown"*)
                export_conversation "$session_id"
                gum style --foreground 82 "✅ Exported successfully"
                sleep 2
                ;;
            *"Copy Session ID"*)
                echo -n "$session_id" | clipboard 2>/dev/null || {
                    echo "$session_id"
                    gum style --foreground 214 "Session ID: $session_id"
                    sleep 3
                }
                gum style --foreground 82 "✅ Session ID copied"
                sleep 1
                ;;
            *"Delete Session"*)
                if gum confirm "Delete session $short_id?"; then
                    delete_session "$session_id"
                    gum style --foreground 82 "✅ Session deleted"
                    sleep 2
                fi
                ;;
            *"Back to Sessions"*)
                done_with_session=true  # Exit action menu loop, return to session list
                ;;
            *"Exit Browser"*)
                done_with_session=true
                break 2  # Exit both loops
                ;;
            *)
                done_with_session=true
                break 2  # Exit on ESC or unknown selection
                ;;
            esac
        done  # End of action menu loop
    done
}

# Interactive selector with gum
select_with_gum() {
    # Get all sessions
    local all_sessions=$(get_all_sessions 30)
    
    if [ -z "$all_sessions" ]; then
        gum style --foreground 196 "No sessions found"
        return 1
    fi
    
    local sessions=()
    local session_map=()
    
    # Build session list
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Extract fields using tabs
            local icon=$(echo "$line" | cut -d$'\t' -f1)
            local timestamp=$(echo "$line" | cut -d$'\t' -f2)
            local sesh_name=$(echo "$line" | cut -d$'\t' -f3)
            local message=$(echo "$line" | cut -d$'\t' -f4)
            local display="$icon $timestamp [$sesh_name] $message"
            sessions+=("$display")
            session_map+=("$line")
        fi
    done <<< "$all_sessions"
    
    if [ ${#sessions[@]} -eq 0 ]; then
        gum style --foreground 196 "No sessions found"
        exit 1
    fi
    
    # Select with gum
    local selected=$(printf '%s\n' "${sessions[@]}" | \
        gum filter \
            --placeholder "Search for a Claude session..." \
            --indicator="▶" \
            --header="Select Claude session to resume:" \
            --height=20)
    
    if [ -n "$selected" ]; then
        # Find the matching session data
        for i in "${!sessions[@]}"; do
            if [ "${sessions[$i]}" = "$selected" ]; then
                local session_data="${session_map[$i]}"
                local session_id=$(echo "$session_data" | cut -d$'\t' -f5)
                local cwd=$(echo "$session_data" | cut -d$'\t' -f6)
                
                connect_and_resume "$session_id" "$cwd"
                break
            fi
        done
    fi
}

# List sessions in a nice format
list_sessions() {
    gum style \
        --foreground 212 \
        --border double \
        --border-foreground 212 \
        --padding "1 2" \
        --align center \
        "Claude Sessions"
    
    echo ""
    
    local sessions=$(get_all_sessions 20)
    if [ -z "$sessions" ]; then
        gum style --foreground 196 "No sessions found"
        return 1
    fi
    
    echo "$sessions" | while IFS=$'\t' read -r icon timestamp sesh_name message session_id cwd; do
        echo "$(gum style --foreground 214 "$icon $timestamp") $(gum style --foreground 45 "[$sesh_name]")"
        echo "  $(gum style --foreground 250 "$message")"
        echo "  $(gum style --foreground 240 "📁 $cwd")"
        echo ""
    done
}

# Resume directly by session ID
resume_direct() {
    local session_id="$1"
    
    # Find session file
    local file=$(find "$PROJECTS_DIR" -name "*${session_id}*.jsonl" 2>/dev/null | head -1)
    
    if [ -z "$file" ]; then
        gum style --foreground 196 "Session not found: $session_id"
        exit 1
    fi
    
    local metadata=$(get_session_metadata "$file")
    local cwd=$(echo "$metadata" | jq -r '.cwd // "."')
    
    connect_and_resume "$session_id" "$cwd"
}

# Show usage
usage() {
    gum style \
        --foreground 45 \
        --border rounded \
        --border-foreground 45 \
        --padding "1 2" \
        --margin "1" \
        "Claude + Sesh Enhanced Session Manager" \
        "" \
        "Resume Claude sessions with modern CLI tools" \
        "" \
        "Usage: $(basename "$0") [OPTIONS]" \
        "" \
        "OPTIONS:" \
        "  (none)          Quick resume mode (F-keys for actions)" \
        "  --browse        Browse mode (always shows action menu)" \
        "  --gum           Use gum filter interface" \
        "  --zoxide        Sort by zoxide frecency" \
        "  --search TERM   Search sessions" \
        "  --direct ID     Resume specific session" \
        "  --view ID       View conversation for session" \
        "  --export ID     Export conversation to markdown" \
        "  --list          List sessions nicely" \
        "  --help          Show this help" \
        "" \
        "FZF KEYBINDINGS:" \
        "  F2      View full conversation" \
        "  F3      Export to markdown" \
        "  F4      Show action menu" \
        "  Ctrl+P  Toggle preview pane" \
        "  Enter   Resume session (default)" \
        "  ESC     Cancel and exit" \
        "  Type    Filter sessions in real-time" \
        "" \
        "ACTION MENU (F4):" \
        "  • Resume session" \
        "  • View conversation" \
        "  • Export to markdown" \
        "  • Copy session ID" \
        "  • Delete session" \
        "  • Back to list"
}

# Main
main() {
    # Export functions for subshells
    export -f get_session_metadata
    export -f format_session_display
    export -f get_all_sessions
    export -f get_sessions_by_zoxide
    export -f search_sessions
    export -f generate_session_preview
    export -f get_session_icon
    export -f dir_to_sesh_name
    export -f find_config_sessions_for_path
    export -f select_session_for_path
    export -f format_conversation
    export -f view_conversation
    export -f view_conversation_interactive
    export -f export_conversation
    export -f show_action_menu
    export -f show_styled_menu
    export -f delete_session
    export -f browse_mode
    export -f find_session_file
    export -f browse_internal
    export -f menu_only
    
    # Export variables
    export CLAUDE_DIR PROJECTS_DIR
    
    check_dependencies
    
    case "${1:-}" in
        --browse)
            # Browse mode: always show action menu after selection
            browse_mode
            ;;
        --browse-internal)
            # Internal browse mode (runs inside popup - subprocess)
            export CLAUDE_SESH_SUBPROCESS=1
            browse_internal
            ;;
        --menu-only)
            # Menu-only mode for F4 popup
            shift
            menu_only "$@"
            ;;
        --gum)
            select_with_gum
            ;;
        --zoxide)
            select_with_fzf "zoxide"
            ;;
        --search)
            shift
            select_with_fzf "search" "${1:-}"
            ;;
        --direct)
            shift
            resume_direct "${1:-}"
            ;;
        --list)
            list_sessions
            ;;
        --view)
            shift
            view_conversation "${1:-}"
            ;;
        --export)
            shift
            export_conversation "${1:-}"
            ;;
        --get-sessions-only)
            # Just output sessions - for use with gum spin
            # This is a subprocess, don't run cleanup
            export CLAUDE_SESH_SUBPROCESS=1
            trap - EXIT INT TERM
            get_all_sessions
            exit 0
            ;;
        --debug)
            # Debug mode to test functions
            echo "Testing get_all_sessions (first 5):"
            get_all_sessions 5
            echo ""
            echo "Total sessions found: $(get_all_sessions | wc -l)"
            ;;
        --help|-h)
            usage
            ;;
        *)
            select_with_fzf "all"
            ;;
    esac
}

main "$@"