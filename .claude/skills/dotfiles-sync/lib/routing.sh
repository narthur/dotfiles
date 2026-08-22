#!/bin/bash
# lib/routing.sh - Shared utilities for dotfiles routing checks and corrections

# Get all tracked files in a repo (using git --git-dir without --work-tree)
get_tracked_files() {
    local git_dir="$1"
    git --git-dir="$git_dir" ls-tree -r --name-only HEAD 2>/dev/null || echo ""
}

# Files untracked in BOTH repos, one per line.
#
# ponytail: `ls-files -o`, not `status -u` — both repos set
# status.showUntrackedFiles=no, which silently empties the status form. It also
# applies real gitignore semantics instead of hand-rolled glob matching.
#
# Bounded to the top-level paths the repos actually manage, derived from what is
# tracked, so a newly managed directory is picked up with no edit here. Unbounded
# it walks all of $HOME (~786k files) and the output is unusable.
#
# Each repo reports the other's tracked files as "other", so intersect the two
# lists: a file absent from both is genuinely untracked.
get_untracked_both() {
    local dotfiles_dir="${1:-$HOME/.dotfiles}"
    local dotprivate_dir="${2:-$HOME/.dotfiles-private}"
    local paths
    paths=$(printf '%s\n%s\n' "$(get_tracked_files "$dotfiles_dir")" \
                                "$(get_tracked_files "$dotprivate_dir")" \
            | awk -F/ 'NF{print $1}' | sort -u)
    [[ -z "$paths" ]] && return 0
    comm -12 \
      <(git -C ~ --git-dir="$dotfiles_dir"   --work-tree="$HOME" ls-files -o --exclude-standard -- $paths | sort) \
      <(git -C ~ --git-dir="$dotprivate_dir" --work-tree="$HOME" ls-files -o --exclude-standard -- $paths | sort)
}

# Check if a file is tracked in a repo
is_tracked() {
    local git_dir="$1"
    local file="$2"
    git --git-dir="$git_dir" ls-tree -r --name-only HEAD -- "$file" 2>/dev/null | grep -q "^$file\$"
}

# Suggest routing categories for a file based on patterns and naming
# Returns a space-separated list of possible categories with reasoning
# Example: "dotfiles (generic tool config) or review-needed (contains 'skill')"
#
# WARNING: This is keyword-based heuristic matching, not semantic analysis.
# A keyword match (e.g., "narthbugz") indicates a RISK SIGNAL that requires
# human review. It does NOT determine the answer:
# - A helper script that integrates with a client service ≠ client-specific
# - A reusable skill that references a service ≠ needs to be private
# Always read the actual file and understand its purpose vs. its naming.
suggestion_for_file() {
    local file="$1"
    local -a suggestions=()
    local -a reasons=()
    
    # Check for obvious never-commit patterns
    if [[ "$file" =~ (^|/)(\.cache|\.venv|\.idea|__pycache__|node_modules|\.DS_Store) ]]; then
        suggestions+=("never-commit")
        reasons+=("build artifact or cache")
    fi
    
    if [[ "$file" =~ (^|/)(\.env|\.env\.local) ]]; then
        suggestions+=("never-commit")
        reasons+=("secrets file")
    fi
    
    # Check for obvious gitignore patterns
    if [[ "$file" =~ \.(log|swp|swo)$ ]] || [[ "$file" =~ ~$ ]]; then
        suggestions+=("gitignore")
        reasons+=("temp/editor file")
    fi
    
    # Check for generic tool configs (strong dotfiles signal)
    if [[ "$file" =~ \.(bashrc|zshrc|vimrc|gitconfig|tmux\.conf)$ ]] || [[ "$file" =~ (^|\.)(bash|zsh|vim|git|tmux|fish|nvim)/ ]]; then
        if [[ ! "$file" =~ /skills/ ]]; then
            suggestions+=("dotfiles")
            reasons+=("generic tool config")
        fi
    fi
    
    # Check for explicit client/personal keywords (strong dotprivate signal)
    if [[ "$file" =~ (client|crm|ynab|memberstack|surge|billable|invoice|contract) ]]; then
        suggestions+=("dotprivate")
        reasons+=("client/business keyword")
    fi
    
    if [[ "$file" =~ (\.config/(aws|gcp|azure|kubectl|heroku|netlify|vercel|stripe|slack)|slack-webhook|api-key|oauth|credentials) ]]; then
        suggestions+=("dotprivate")
        reasons+=("service account or secret")
    fi
    
    # Skills need review (never auto-route)
    if [[ "$file" =~ /skills/ ]]; then
        suggestions+=("review-needed")
        reasons+=("skill directory")
    fi
    
    # If no clear signal, suggest review
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        suggestions+=("review-needed")
        reasons+=("no clear routing signal")
    fi
    
    # Format output
    local output=""
    for i in "${!suggestions[@]}"; do
        if [[ -n "$output" ]]; then
            output+=" | "
        fi
        output+="${suggestions[$i]} (${reasons[$i]})"
    done
    echo "$output"
}

# Add a file to a repo's index (use git -C ~ to preserve context)
git_add() {
    local git_dir="$1"
    shift
    git -C ~ --git-dir="$git_dir" --work-tree=~ add "$@"
}

# Remove a file from a repo's index only (not from disk)
git_rm_cached() {
    local git_dir="$1"
    shift
    git -C ~ --git-dir="$git_dir" --work-tree=~ rm --cached "$@"
}

# Get the status of tracked files in a repo (concise view)
get_tracked_status() {
    local git_dir="$1"
    git -C ~ --git-dir="$git_dir" --work-tree=~ status --short | grep -v '^\?\?'
}

# Export functions for sourcing
export -f get_tracked_files get_untracked_both is_tracked suggestion_for_file git_add git_rm_cached get_tracked_status
