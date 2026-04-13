#!/usr/bin/env bash

# but-feedback.sh - Show resolvable PR feedback for GitButler branches
# Usage:
#   bash but-feedback.sh [--json] [--human] [--all] [--branch <branch-cli-id>]

set -euo pipefail

# Source shared functions
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/pr-feedback-common.sh"

FORMAT="human"
SHOW_ALL=false
DEBUG=false
LIMIT=0
BRANCH_FILTER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT="json"; shift;;
    --human) FORMAT="human"; shift;;
    --all) SHOW_ALL=true; shift;;
    --limit|-l) LIMIT="$2"; shift 2;;
    --branch|-b) BRANCH_FILTER="$2"; shift 2;;
    --debug) DEBUG=true; shift;;
    -h|--help)
      cat <<EOF
Usage: $0 [options]

Options:
  --json             JSON output format
  --human            Human-readable format (default)
  --all              Show all comments, including resolved ones
  --limit|-l N       Limit number of results
  --branch|-b ID     Show feedback for specific branch (by cliId)
  --debug            Show debug information
  -h, --help         Show this help

Examples:
  $0
  $0 --json
  $0 --all
  $0 --limit 10
  $0 --branch st
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

# Get GitButler status
STATUS_JSON=$(but status --json 2>&1) || {
  echo "Error: Failed to get GitButler status." >&2
  echo "Make sure you're in a GitButler workspace." >&2
  exit 1
}

# Debug output
if [[ "$DEBUG" == true ]]; then
  echo "Debug: Status JSON fetched" >&2
fi

# Extract branches with review IDs (PRs)
BRANCHES=$(echo "$STATUS_JSON" | jq -c '
  [.stacks[].branches[] | 
   select(.reviewId != null and .reviewId != "") | 
   {
     cliId: .cliId,
     name: .name,
     reviewId: .reviewId,
     branchStatus: .branchStatus
   }]
')

# Filter by branch if specified
if [[ -n "$BRANCH_FILTER" ]]; then
  BRANCHES=$(echo "$BRANCHES" | jq --arg cliId "$BRANCH_FILTER" '[.[] | select(.cliId == $cliId)]')
fi

BRANCH_COUNT=$(echo "$BRANCHES" | jq 'length')

if [[ "$BRANCH_COUNT" -eq 0 ]]; then
  if [[ -n "$BRANCH_FILTER" ]]; then
    echo "Error: No branch found with cliId '$BRANCH_FILTER' that has a PR." >&2
  else
    echo "No branches with pull requests found in the workspace." >&2
  fi
  exit 1
fi

if [[ "$DEBUG" == true ]]; then
  echo "Debug: Found $BRANCH_COUNT branch(es) with PRs" >&2
fi

# Get repository owner and name
REPO_INFO=$(gh repo view --json owner,name 2>&1) || {
  echo "Error: Could not determine repository information." >&2
  exit 1
}

OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO=$(echo "$REPO_INFO" | jq -r '.name')

if [[ "$DEBUG" == true ]]; then
  echo "Debug: Repository: $OWNER/$REPO" >&2
fi

# Get current user login (used for snooze auto-unsnooze logic)
ME=$(gh api user --jq '.login' 2>/dev/null || echo "")

# Function to fetch review threads with pagination, stopping early if limit is reached
# Parameters: pr_number, show_all (true/false), limit (0 = no limit)
fetch_threads_with_limit() {
  local pr_number="$1"
  local show_all="$2"
  local limit="$3"
  local all_comments="[]"
  local cursor=""
  local has_next_page=true
  local comment_count=0
  
  while [[ "$has_next_page" == true ]]; do
    # Stop if we've reached the limit
    if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
      break
    fi
    local query='query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          reviewThreads(first: 100, after: $cursor) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              isResolved
              isOutdated
              isCollapsed
              comments(first: 100) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                nodes {
                  id
                  body
                  author {
                    login
                  }
                  createdAt
                  path
                  line
                  startLine
                  diffHunk
                  url
                }
              }
            }
          }
        }
      }
    }'
    
    local response
    # Build the GraphQL request - only include cursor if it's not empty
    if [[ -n "$cursor" ]]; then
      response=$(gh api graphql -f query="$query" \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -F prNumber="$pr_number" \
        -f cursor="$cursor" 2>&1) || {
        echo "Error: Failed to fetch review threads for PR #$pr_number." >&2
        exit 1
      }
    else
      # First page - don't pass cursor
      response=$(gh api graphql -f query="$query" \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -F prNumber="$pr_number" 2>&1) || {
        echo "Error: Failed to fetch review threads for PR #$pr_number." >&2
        exit 1
      }
    fi
    
    # Extract page info and nodes
    has_next_page=$(echo "$response" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false')
    # Handle null or invalid hasNextPage
    if [[ "$has_next_page" != "true" ]]; then
      has_next_page=false
    fi
    cursor=$(echo "$response" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // ""')
    # Handle null cursor
    if [[ "$cursor" == "null" ]] || [[ -z "$cursor" ]]; then
      cursor=""
      if [[ "$has_next_page" == true ]]; then
        has_next_page=false
      fi
    fi
    local nodes=$(echo "$response" | jq -c '.data.repository.pullRequest.reviewThreads.nodes[]')
    
    # For each thread, extract comments and stop early if limit reached
    while IFS= read -r thread; do
      # Stop if we've reached the limit
      if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
        break
      fi
      
      local thread_id=$(echo "$thread" | jq -r '.id')
      local is_resolved=$(echo "$thread" | jq -r '.isResolved')
      local is_collapsed=$(echo "$thread" | jq -r '.isCollapsed')

      # Skip threads based on filters
      if [[ "$is_collapsed" == "true" ]]; then
        continue
      fi
      if [[ "$show_all" != "true" ]] && [[ "$is_resolved" == "true" ]]; then
        continue
      fi
      # Skip snoozed threads (unless --all is passed)
      if [[ "$show_all" != "true" ]] && check_thread_snoozed "$thread_id" "$thread" "$ME"; then
        continue
      fi

      local thread_comments=$(echo "$thread" | jq -c '.comments.nodes[]')
      
      # Process initial comments from thread
      while IFS= read -r comment; do
        # Stop if we've reached the limit
        if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
          break
        fi
        
        local body=$(echo "$comment" | jq -r '.body // ""')
        if [[ -z "$body" ]] || [[ "$body" == "null" ]]; then
          continue
        fi
        
        # Extract comment data
        local comment_data=$(echo "$comment" | jq --arg thread_id "$thread_id" --arg is_resolved "$is_resolved" --arg pr_number "$pr_number" '{
          id: .id,
          type: "review_thread",
          threadId: $thread_id,
          prNumber: ($pr_number | tonumber),
          body: .body,
          author: .author.login,
          createdAt: .createdAt,
          path: .path,
          line: (.line // .startLine),
          diffHunk: .diffHunk,
          url: .url,
          isResolved: ($is_resolved == "true")
        }')
        
        all_comments=$(echo "$all_comments" | jq --argjson comment "$comment_data" '. + [$comment]')
        comment_count=$((comment_count + 1))
      done <<< "$thread_comments"
      
      # Stop outer loop if we've reached the limit
      if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
        break
      fi
    done <<< "$nodes"
    
    # Stop outer pagination loop if we've reached the limit
    if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
      has_next_page=false
    fi
  done
  
  echo "$all_comments"
}

# Function to calculate relative time
relative_time() {
  local timestamp="$1"
  local now=$(date +%s)
  local then=$(date -d "$timestamp" +%s 2>/dev/null || echo "$now")
  local diff=$((now - then))
  
  if [[ $diff -lt 3600 ]]; then
    echo "$((diff / 60))m ago"
  elif [[ $diff -lt 86400 ]]; then
    echo "$((diff / 3600))h ago"
  elif [[ $diff -lt 604800 ]]; then
    echo "$((diff / 86400))d ago"
  else
    echo "$((diff / 604800))w ago"
  fi
}

# Function to fetch issue comments (generic PR comments) with pagination
# Parameters: pr_number, show_all (true/false), limit (0 = no limit)
fetch_issue_comments_with_limit() {
  local pr_number="$1"
  local show_all="$2"
  local limit="$3"
  local all_comments="[]"
  local cursor=""
  local has_next_page=true
  local comment_count=0

  while [[ "$has_next_page" == true ]]; do
    if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
      break
    fi

    local query='query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          comments(first: 100, after: $cursor) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              body
              author {
                login
              }
              createdAt
              url
              isMinimized
            }
          }
        }
      }
    }'

    local response
    if [[ -n "$cursor" ]]; then
      response=$(gh api graphql -f query="$query" \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -F prNumber="$pr_number" \
        -f cursor="$cursor" 2>&1) || {
        if [[ "$DEBUG" == true ]]; then
          echo "Debug: Failed to fetch issue comments for PR #$pr_number: $response" >&2
        fi
        break
      }
    else
      response=$(gh api graphql -f query="$query" \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -F prNumber="$pr_number" 2>&1) || {
        if [[ "$DEBUG" == true ]]; then
          echo "Debug: Failed to fetch issue comments for PR #$pr_number: $response" >&2
        fi
        break
      }
    fi

    has_next_page=$(echo "$response" | jq -r '.data.repository.pullRequest.comments.pageInfo.hasNextPage // false')
    if [[ "$has_next_page" != "true" ]]; then
      has_next_page=false
    fi
    cursor=$(echo "$response" | jq -r '.data.repository.pullRequest.comments.pageInfo.endCursor // ""')
    if [[ "$cursor" == "null" ]] || [[ -z "$cursor" ]]; then
      cursor=""
      if [[ "$has_next_page" == true ]]; then
        has_next_page=false
      fi
    fi

    local nodes
    nodes=$(echo "$response" | jq -c '.data.repository.pullRequest.comments.nodes[]' 2>/dev/null) || nodes=""

    [[ -z "$nodes" ]] && continue

    while IFS= read -r comment; do
      if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
        break
      fi

      local is_minimized=$(echo "$comment" | jq -r '.isMinimized')
      if [[ "$is_minimized" == "true" ]]; then
        continue
      fi

      local comment_id=$(echo "$comment" | jq -r '.id')

      if [[ "$show_all" != "true" ]]; then
        if is_comment_dismissed "$comment_id" || check_comment_snoozed "$comment_id"; then
          continue
        fi
      fi

      local body=$(echo "$comment" | jq -r '.body // ""')
      if [[ -z "$body" ]] || [[ "$body" == "null" ]]; then
        continue
      fi

      if [[ "$show_all" != "true" ]] && is_bot_command "$body"; then
        continue
      fi

      local comment_data=$(echo "$comment" | jq --arg pr_number "$pr_number" '{
        id: .id,
        commentId: .id,
        type: "issue_comment",
        prNumber: ($pr_number | tonumber),
        body: .body,
        author: .author.login,
        createdAt: .createdAt,
        url: .url,
        path: "general",
        line: null,
        diffHunk: null,
        threadId: null,
        isResolved: false
      }')

      all_comments=$(echo "$all_comments" | jq --argjson comment "$comment_data" '. + [$comment]')
      comment_count=$((comment_count + 1))
    done <<< "$nodes"

    if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
      has_next_page=false
    fi
  done

  echo "$all_comments"
}

# Function to fetch review summaries (top-level review body comments) with pagination
# Parameters: pr_number, show_all (true/false), limit (0 = no limit)
fetch_reviews_with_limit() {
  local pr_number="$1"
  local show_all="$2"
  local limit="$3"
  local all_comments="[]"
  local cursor=""
  local has_next_page=true
  local comment_count=0

  while [[ "$has_next_page" == true ]]; do
    if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
      break
    fi

    local query='query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          reviews(first: 100, after: $cursor) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              state
              body
              author {
                login
              }
              createdAt
              url
            }
          }
        }
      }
    }'

    local response
    if [[ -n "$cursor" ]]; then
      response=$(gh api graphql -f query="$query" \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -F prNumber="$pr_number" \
        -f cursor="$cursor" 2>&1) || {
        if [[ "$DEBUG" == true ]]; then
          echo "Debug: Failed to fetch reviews for PR #$pr_number: $response" >&2
        fi
        break
      }
    else
      response=$(gh api graphql -f query="$query" \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -F prNumber="$pr_number" 2>&1) || {
        if [[ "$DEBUG" == true ]]; then
          echo "Debug: Failed to fetch reviews for PR #$pr_number: $response" >&2
        fi
        break
      }
    fi

    has_next_page=$(echo "$response" | jq -r '.data.repository.pullRequest.reviews.pageInfo.hasNextPage // false')
    if [[ "$has_next_page" != "true" ]]; then
      has_next_page=false
    fi
    cursor=$(echo "$response" | jq -r '.data.repository.pullRequest.reviews.pageInfo.endCursor // ""')
    if [[ "$cursor" == "null" ]] || [[ -z "$cursor" ]]; then
      cursor=""
      if [[ "$has_next_page" == true ]]; then
        has_next_page=false
      fi
    fi

    local nodes
    nodes=$(echo "$response" | jq -c '.data.repository.pullRequest.reviews.nodes[]' 2>/dev/null) || nodes=""

    [[ -z "$nodes" ]] && continue

    while IFS= read -r review; do
      if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
        break
      fi

      local body=$(echo "$review" | jq -r '.body // ""')
      if [[ -z "$body" ]] || [[ "$body" == "null" ]]; then
        continue
      fi

      local state=$(echo "$review" | jq -r '.state')
      # Skip pending (draft) reviews
      if [[ "$state" == "PENDING" ]]; then
        continue
      fi

      local review_id=$(echo "$review" | jq -r '.id')

      # Skip dismissed or snoozed reviews (unless --all)
      if [[ "$show_all" != "true" ]]; then
        if is_comment_dismissed "$review_id" || check_comment_snoozed "$review_id"; then
          continue
        fi
      fi

      local comment_data=$(echo "$review" | jq --arg state "$state" --arg pr_number "$pr_number" '{
        id: .id,
        commentId: .id,
        type: "review_comment",
        prNumber: ($pr_number | tonumber),
        body: .body,
        author: .author.login,
        createdAt: .createdAt,
        url: .url,
        state: $state,
        path: "general",
        line: null,
        diffHunk: null,
        threadId: null,
        isResolved: false
      }')

      all_comments=$(echo "$all_comments" | jq --argjson comment "$comment_data" '. + [$comment]')
      comment_count=$((comment_count + 1))
    done <<< "$nodes"

    if [[ "$limit" -gt 0 ]] && [[ "$comment_count" -ge "$limit" ]]; then
      has_next_page=false
    fi
  done

  echo "$all_comments"
}

# Collect all comments from all branches
ALL_COMMENTS="[]"

while IFS= read -r branch_json; do
  BRANCH_CLI_ID=$(echo "$branch_json" | jq -r '.cliId')
  BRANCH_NAME=$(echo "$branch_json" | jq -r '.name')
  REVIEW_ID=$(echo "$branch_json" | jq -r '.reviewId')
  
  # Extract PR number from reviewId (format: "(#84)")
  PR_NUMBER=$(echo "$REVIEW_ID" | sed 's/[^0-9]//g')
  
  if [[ -z "$PR_NUMBER" ]]; then
    continue
  fi
  
  if [[ "$DEBUG" == true ]]; then
    echo "Debug: Fetching feedback for branch $BRANCH_NAME (PR #$PR_NUMBER)" >&2
  fi
  
  # Fetch review thread comments for this PR
  BRANCH_COMMENTS=$(fetch_threads_with_limit "$PR_NUMBER" "$SHOW_ALL" "$LIMIT")

  # Also fetch issue comments (generic PR comments) for this PR
  BRANCH_REVIEW_COUNT=$(echo "$BRANCH_COMMENTS" | jq 'length')
  BRANCH_REMAINING=0
  if [[ "$LIMIT" -gt 0 ]]; then
    BRANCH_REMAINING=$((LIMIT - BRANCH_REVIEW_COUNT))
  fi
  if [[ "$LIMIT" -eq 0 ]] || [[ "$BRANCH_REMAINING" -gt 0 ]]; then
    BRANCH_ISSUE_COMMENTS=$(fetch_issue_comments_with_limit "$PR_NUMBER" "$SHOW_ALL" "$BRANCH_REMAINING")
    BRANCH_IC_COUNT=$(echo "$BRANCH_ISSUE_COMMENTS" | jq 'length')
    if [[ "$BRANCH_IC_COUNT" -gt 0 ]]; then
      BRANCH_COMMENTS=$(echo "$BRANCH_COMMENTS" | jq --argjson new "$BRANCH_ISSUE_COMMENTS" '. + $new')
    fi
  fi

  # Also fetch review summaries (top-level review body comments)
  BRANCH_CURRENT_COUNT=$(echo "$BRANCH_COMMENTS" | jq 'length')
  BRANCH_REMAINING=0
  if [[ "$LIMIT" -gt 0 ]]; then
    BRANCH_REMAINING=$((LIMIT - BRANCH_CURRENT_COUNT))
  fi
  if [[ "$LIMIT" -eq 0 ]] || [[ "$BRANCH_REMAINING" -gt 0 ]]; then
    BRANCH_REVIEW_COMMENTS=$(fetch_reviews_with_limit "$PR_NUMBER" "$SHOW_ALL" "$BRANCH_REMAINING")
    BRANCH_RC_COUNT=$(echo "$BRANCH_REVIEW_COMMENTS" | jq 'length')
    if [[ "$BRANCH_RC_COUNT" -gt 0 ]]; then
      BRANCH_COMMENTS=$(echo "$BRANCH_COMMENTS" | jq --argjson new "$BRANCH_REVIEW_COMMENTS" '. + $new')
    fi
  fi

  # Add branch info to each comment
  BRANCH_COMMENTS=$(echo "$BRANCH_COMMENTS" | jq --arg branch_name "$BRANCH_NAME" --arg branch_id "$BRANCH_CLI_ID" '
    [.[] | . + {branchName: $branch_name, branchCliId: $branch_id}]
  ')
  
  # Merge with all comments
  ALL_COMMENTS=$(echo "$ALL_COMMENTS" | jq --argjson new "$BRANCH_COMMENTS" '. + $new')
done < <(echo "$BRANCHES" | jq -c '.[]')

# Count comments
COMMENT_COUNT=$(echo "$ALL_COMMENTS" | jq 'if . == null or . == [] then 0 elif type == "array" then length else 0 end')

# Output based on format
if [[ "$FORMAT" == "json" ]]; then
  echo "$ALL_COMMENTS" | jq '.'
else
  # Human-readable format
  echo "GitButler Workspace Feedback"
  echo ""
  
  if [[ "$COMMENT_COUNT" -eq 0 ]]; then
    if [[ "$SHOW_ALL" == true ]]; then
      echo "No feedback found."
    else
      echo "No unresolved feedback found."
      echo ""
      echo "Use --all to show all feedback including resolved and dismissed."
    fi
    exit 0
  fi

  if [[ "$LIMIT" -gt 0 ]]; then
    echo "Found $COMMENT_COUNT feedback item(s) (showing up to $LIMIT):"
  else
    echo "Found $COMMENT_COUNT feedback item(s):"
  fi
  echo ""
  
  # Get terminal width (default to 80 if not available)
  TERM_WIDTH=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  
  # Print comments - process each comment as JSON to handle special characters
  echo "$ALL_COMMENTS" | jq -c '.[]' | while IFS= read -r comment_json; do
    id=$(echo "$comment_json" | jq -r '.id')
    type=$(echo "$comment_json" | jq -r '.type // "review_thread"')
    thread_id=$(echo "$comment_json" | jq -r '.threadId // .id')
    pr_number=$(echo "$comment_json" | jq -r '.prNumber')
    branch_name=$(echo "$comment_json" | jq -r '.branchName')
    branch_cli_id=$(echo "$comment_json" | jq -r '.branchCliId')
    author=$(echo "$comment_json" | jq -r '.author')
    created=$(echo "$comment_json" | jq -r '.createdAt')
    path=$(echo "$comment_json" | jq -r '.path // "general"')
    line=$(echo "$comment_json" | jq -r '.line // "N/A"')
    body=$(echo "$comment_json" | jq -r '.body')
    url=$(echo "$comment_json" | jq -r '.url')

    relative=$(relative_time "$created")

    # Color formatting
    color_reset=$'\033[0m'
    color_author=$'\033[36m'  # Cyan
    color_path=$'\033[33m'    # Yellow
    color_line=$'\033[90m'    # Gray
    color_id=$'\033[35m'      # Magenta
    color_branch=$'\033[32m'  # Green

    if [[ "$type" == "issue_comment" ]]; then
      echo -e "${color_branch}[$branch_name (PR #$pr_number)]${color_reset} ${color_id}[Comment: ${id}]${color_reset} ${color_author}@${author}${color_reset} (${relative})"
    elif [[ "$type" == "review_comment" ]]; then
      review_state=$(echo "$comment_json" | jq -r '.state // ""')
      echo -e "${color_branch}[$branch_name (PR #$pr_number)]${color_reset} ${color_id}[Review: ${id}]${color_reset} ${color_author}@${author}${color_reset} ${color_path}${review_state}${color_reset} (${relative})"
    else
      echo -e "${color_branch}[$branch_name (PR #$pr_number)]${color_reset} ${color_id}[Thread: ${thread_id}]${color_reset} ${color_author}@${author}${color_reset} ${color_path}${path}${color_reset}:${color_line}${line}${color_reset} (${relative})"
    fi
    echo ""
    
    # Format body with word wrapping
    echo "$body" | fold -w $((TERM_WIDTH - 2)) -s | sed 's/^/  /'
    echo ""
    echo -e "  ${color_line}→ ${url}${color_reset}"
    echo ""
    echo "$(printf '%*s' $TERM_WIDTH '' | tr ' ' '-')"
    echo ""
  done
  
  # Show tools documentation
  # print_pr_tools_help
fi
