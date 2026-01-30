#!/bin/bash
# Track Claude Code token usage per repository

# Read JSON input from stdin
input=$(cat)

# Extract fields from JSON
session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // "unknown"' 2>/dev/null)
reason=$(echo "$input" | jq -r '.reason // "unknown"' 2>/dev/null)
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null)

# If no transcript path, exit
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    exit 0
fi

# Calculate total token usage from transcript
usage=$(jq -s 'map(select(.message.usage != null) | .message.usage) | {input_tokens: (map(.input_tokens // 0) | add // 0), output_tokens: (map(.output_tokens // 0) | add // 0), cache_creation_tokens: (map(.cache_creation_input_tokens // 0) | add // 0), cache_read_tokens: (map(.cache_read_input_tokens // 0) | add // 0)}' "$transcript_path")

# Get model name (take the first model used in the session)
model=$(jq -r 'select(.message.model != null) | .message.model' "$transcript_path" | head -n 1)
if [ -z "$model" ]; then
    model="unknown"
fi

input_tokens=$(echo "$usage" | jq -r '.input_tokens // 0')
output_tokens=$(echo "$usage" | jq -r '.output_tokens // 0')
cache_creation_tokens=$(echo "$usage" | jq -r '.cache_creation_tokens // 0')
cache_read_tokens=$(echo "$usage" | jq -r '.cache_read_tokens // 0')

# Default to 0 if empty
input_tokens=${input_tokens:-0}
output_tokens=${output_tokens:-0}
cache_creation_tokens=${cache_creation_tokens:-0}
cache_read_tokens=${cache_read_tokens:-0}

# Only proceed if we have token data
if [ "$input_tokens" -eq 0 ] && [ "$output_tokens" -eq 0 ] && [ "$cache_creation_tokens" -eq 0 ] && [ "$cache_read_tokens" -eq 0 ]; then
    exit 0
fi

# Calculate total tokens
total_tokens=$((input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens))

# Determine repository path (use cwd or fall back to unknown)
repo_path="$cwd"

# Get client name from mapping file
client="unknown"
if [ -f "$HOME/.claude/client-mapping.json" ]; then
    client=$(jq -r --arg repo "$repo_path" '.clients[$repo] // "unknown"' "$HOME/.claude/client-mapping.json" 2>/dev/null)
    # Normalize to lowercase
    client=$(echo "$client" | tr '[:upper:]' '[:lower:]')
fi

# Create log directory if it doesn't exist
log_dir="$HOME/.claude/token-usage"
mkdir -p "$log_dir"

# Create timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Log to repository-specific file
repo_slug=$(echo "$repo_path" | sed 's|/|_|g' | sed 's|^_||')
repo_log="$log_dir/${repo_slug}.jsonl"

# Create one log entry per model used in the session
echo "$usage_by_model" | jq -c '.[]' | while read -r model_usage; do
    model=$(echo "$model_usage" | jq -r '.model')
    input_tokens=$(echo "$model_usage" | jq -r '.tokens.input')
    output_tokens=$(echo "$model_usage" | jq -r '.tokens.output')
    cache_creation_tokens=$(echo "$model_usage" | jq -r '.tokens.cache_creation')
    cache_read_tokens=$(echo "$model_usage" | jq -r '.tokens.cache_read')
    total_tokens=$((input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens))
    
    # Create log entry
    log_entry=$(jq -n \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg repo_path "$repo_path" \
        --arg client "$client" \
        --arg reason "$reason" \
        --arg model "$model" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson cache_creation "$cache_creation_tokens" \
        --argjson cache_read "$cache_read_tokens" \
        --argjson total "$total_tokens" \
        '{
            timestamp: $timestamp,
            session_id: $session_id,
            repo_path: $repo_path,
            client: $client,
            reason: $reason,
            model: $model,
            tokens: {
                input: $input_tokens,
                output: $output_tokens,
                cache_creation: $cache_creation,
                cache_read: $cache_read,
                total: $total
            }
        }')
    
    # Append to log file
    echo "$log_entry" >> "$repo_log"
    
    # Also append to global log
    echo "$log_entry" >> "$log_dir/all-repos.jsonl"
done

exit 0
