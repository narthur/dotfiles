#!/bin/bash
# PreToolUse(Edit|Write|NotebookEdit) hook: re-inserts a human approval step
# before modifying a security-sensitive file (CI workflows, .env, auth/secret
# files), regardless of permission mode. Complements the egress guard: that one
# stops data leaving the machine; this one stops untrusted-content-steered edits
# from planting a persistent attack (e.g. a malicious GitHub Actions workflow
# that exfiltrates secrets on the next push) or tampering with credentials.
#
# Pairs with ~/bin/sensitive-file-check (the detector). Maps its exit code to a
# Claude Code permission decision:
#   not sensitive -> stay silent (exit 0): normal permission flow continues
#   sensitive     -> permissionDecision "ask": forces a confirmation prompt
#
# "ask" (not "deny") is intentional: legitimate edits proceed with one keystroke.
#
# Known gap: this guards the Edit/Write/NotebookEdit tools, not file writes done
# via Bash redirection (echo > .github/workflows/x.yml). The egress guard is the
# backstop for the worst outcome (exfil); Bash-redirect writes to sensitive paths
# are an accepted residual risk to avoid parsing every shell redirection.

input=$(cat)
# Edit/Write use file_path; NotebookEdit uses notebook_path.
path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

[[ -z "$path" ]] && exit 0

reason=$(sensitive-file-check "$path")
rc=$?

[[ $rc -eq 0 ]] && exit 0

jq -n --arg reason "Sensitive-file guard — confirm this edit.
Target: ${path}
Category: ${reason}

An autonomous edit here (e.g. steered by untrusted issue/PR content) could plant a persistent attack or tamper with credentials. Confirm you intend this change." '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $reason
  }
}'
exit 0
