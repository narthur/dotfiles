#!/usr/bin/env bash
# Fetch all data needed for a client activity report.
#
# Usage: fetch-client-data.sh <github_org> --days <N> \
#          --member <github_user>[:<narthbugz_id>] [...] \
#          [--client-name <narthbugz_client_name>]
#
# Outputs labeled JSON sections to stdout.
#
# Output sections:
#   === META ===                     — period_start, period_end, days
#   === <user> GITHUB EVENTS ===     — one JSON object per line (actions the user performed)
#   === <user> OPEN PRS ===          — one JSON object per line (open PRs authored by user)
#   === <user> MERGED PRS ===        — one JSON object per line (PRs merged within the period)
#   === <user> ASSIGNED ISSUES ===   — one JSON object per line (open issues assigned to user)
#   === <user> ISSUE EDITS ===       — one JSON object per line (issues edited by user in period)
#   === <user> TIME ===              — JSON array of time entries (or [] if unavailable)

set -euo pipefail

GITHUB_ORG="${1:?Usage: fetch-client-data.sh <github_org> --days <N> --member <user>[:<nb_id>] ...}"
shift

DAYS=7
MEMBERS_GITHUB=()
MEMBERS_NB_IDS=()
NARTHBUGZ_CLIENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      DAYS="$2"
      shift 2
      ;;
    --member)
      IFS=':' read -r gh_user nb_id <<< "${2}:"
      MEMBERS_GITHUB+=("$gh_user")
      MEMBERS_NB_IDS+=("${nb_id:-}")
      shift 2
      ;;
    --client-name)
      NARTHBUGZ_CLIENT_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

PERIOD_END=$(date +%Y-%m-%d)
PERIOD_START=$(python3 -c "from datetime import date, timedelta; print(date.today() - timedelta(days=${DAYS}))")

echo "=== META ==="
echo "{\"period_start\":\"${PERIOD_START}\",\"period_end\":\"${PERIOD_END}\",\"days\":${DAYS}}"

source ~/.env 2>/dev/null || true

AUTH_HEADER=""
if [[ -n "${NARTHBUGZ_EMAIL:-}" && -n "${NARTHBUGZ_TOKEN:-}" ]]; then
  AUTH_HEADER="Basic $(echo -n "${NARTHBUGZ_EMAIL}:${NARTHBUGZ_TOKEN}" | base64 | tr -d '\n')"
fi

TMPDIR_DATA=$(mktemp -d)
trap 'rm -rf "$TMPDIR_DATA"' EXIT

# jq filter: extract and normalize relevant event types from a repo's event stream.
# Only includes events the user actually performed within the date range.
JQ_EVENTS='.[]
  | select(.created_at[:10] >= "'"${PERIOD_START}"'" and .created_at[:10] <= "'"${PERIOD_END}"'")
  | select(.type | IN(
      "IssuesEvent","IssueCommentEvent",
      "PullRequestEvent","PullRequestReviewEvent","PullRequestReviewCommentEvent",
      "PushEvent","CreateEvent"
    ))
  | {actor: .actor.login, type, action: .payload.action, repo: .repo.name, created_at}
  + if .type == "PushEvent" then
      {ref: .payload.ref, commits: [.payload.commits[]? | {message, sha}]}
    elif .type == "CreateEvent" then
      {ref: .payload.ref, ref_type: .payload.ref_type}
    elif (.type | test("PullRequest")) then
      {
        title: (.payload.pull_request.title // null),
        number: (.payload.pull_request.number // .payload.number // null),
        html_url: (.payload.pull_request.html_url // null),
        is_pr: true,
        item_created_at: (.payload.pull_request.created_at // null)
      }
    else
      {
        title: (.payload.issue.title // null),
        number: (.payload.issue.number // null),
        html_url: (.payload.issue.html_url // null),
        is_pr: (if .payload.issue.pull_request then true else false end),
        item_created_at: (.payload.issue.created_at // null)
      }
    end'

# --- Phase A: fetch repo list, open PRs, merged PRs, assigned issues, time entries in parallel ---

# Fetch recently-pushed repos from the org (up to 100)
gh api "/orgs/${GITHUB_ORG}/repos?sort=pushed&per_page=100" \
  --jq '.[].full_name' \
  > "$TMPDIR_DATA/repos" 2>/dev/null &

for i in "${!MEMBERS_GITHUB[@]}"; do
  gh_user="${MEMBERS_GITHUB[$i]}"
  nb_id="${MEMBERS_NB_IDS[$i]:-}"

  # Open PRs authored by user in this org
  gh api search/issues -X GET \
    -f q="author:${gh_user} is:pr is:open org:${GITHUB_ORG}" \
    -f per_page=50 \
    --jq '.items[] | {title, number, html_url, created_at, updated_at, repository_url, draft}' \
    > "$TMPDIR_DATA/${gh_user}_open_prs" 2>&1 &

  # PRs merged within the reporting period
  gh api search/issues -X GET \
    -f q="author:${gh_user} is:pr is:merged merged:>=${PERIOD_START} org:${GITHUB_ORG}" \
    -f per_page=50 \
    --jq '.items[] | {title, number, html_url, created_at, updated_at, closed_at, repository_url}' \
    > "$TMPDIR_DATA/${gh_user}_merged_prs" 2>&1 &

  # Open issues assigned to user in this org
  gh api search/issues -X GET \
    -f q="assignee:${gh_user} is:issue is:open org:${GITHUB_ORG}" \
    -f per_page=50 \
    --jq '.items[] | {title, number, html_url, created_at, updated_at, repository_url}' \
    > "$TMPDIR_DATA/${gh_user}_assigned_issues" 2>&1 &

  # Narthbugz time entries (only if user has an ID and client name is configured)
  if [[ -n "$nb_id" && -n "$NARTHBUGZ_CLIENT_NAME" && -n "$AUTH_HEADER" ]]; then
    curl -s --max-time 60 --compressed \
      -H "Authorization: ${AUTH_HEADER}" \
      "https://api.narthbugz.com/users/${nb_id}/entries?sort=-start&size=200" \
      | jq "[.data[]?
          | select(.startTime[:10] >= \"${PERIOD_START}\" and .startTime[:10] <= \"${PERIOD_END}\")
          | select(.clientName == \"${NARTHBUGZ_CLIENT_NAME}\")
          | {taskName, projectName, clientName, hours, notes, date: .startTime[:10]}]" \
      > "$TMPDIR_DATA/${gh_user}_time" 2>&1 &
  else
    echo '[]' > "$TMPDIR_DATA/${gh_user}_time"
  fi
done

wait

# --- Phase B: fetch events and updated issues from each repo in parallel ---

while IFS= read -r repo; do
  [[ "$repo" == */* ]] || continue
  safe_name="${repo//\//_}"

  # Events (for activity tracking)
  gh api "/repos/${repo}/events?per_page=100" \
    --jq "$JQ_EVENTS" \
    > "$TMPDIR_DATA/events_${safe_name}" 2>/dev/null &

  # Issues updated in the period (candidates for edit detection)
  gh api "/repos/${repo}/issues?since=${PERIOD_START}T00:00:00Z&state=all&per_page=100" \
    --jq '.[] | select(.pull_request == null) | .number' \
    > "$TMPDIR_DATA/updated_issues_${safe_name}" 2>/dev/null &
done < "$TMPDIR_DATA/repos"

wait

# --- Phase C: detect issue body edits via GraphQL ---
# The Events API doesn't capture issue body edits. We check lastEditedAt and
# userContentEdits on issues that were updated during the period.

while IFS= read -r repo; do
  [[ "$repo" == */* ]] || continue
  safe_name="${repo//\//_}"
  updated_file="$TMPDIR_DATA/updated_issues_${safe_name}"
  [[ -s "$updated_file" ]] || continue

  owner="${repo%%/*}"
  name="${repo#*/}"

  # Build batched GraphQL query (max 50 issues per query to stay within size limits)
  query="{ repository(owner:\"${owner}\", name:\"${name}\") {"
  count=0
  while read -r num; do
    query+=" i${num}: issue(number:${num}) { number title url lastEditedAt userContentEdits(last:10) { nodes { editedAt editor { login } } } }"
    count=$((count + 1))
    [[ $count -ge 50 ]] && break
  done < "$updated_file"
  query+=" } }"

  gh api graphql -f query="$query" \
    --jq ".data.repository | to_entries[] | .value
      | select(. != null)
      | select(.lastEditedAt != null)
      | select(.lastEditedAt >= \"${PERIOD_START}\")
      | {repo: \"${repo}\", number, title, url, lastEditedAt,
         edits: [.userContentEdits.nodes[]
           | select(.editedAt >= \"${PERIOD_START}\")
           | {editedAt, editor: (.editor.login // null)}]
        }
      | select(.edits | length > 0)" \
    > "$TMPDIR_DATA/issue_edits_${safe_name}" 2>/dev/null &
done < "$TMPDIR_DATA/repos"

wait

# --- Output per member ---

for i in "${!MEMBERS_GITHUB[@]}"; do
  gh_user="${MEMBERS_GITHUB[$i]}"

  echo "=== ${gh_user} GITHUB EVENTS ==="
  if compgen -G "$TMPDIR_DATA/events_*" > /dev/null 2>&1; then
    jq -s --arg user "$gh_user" \
      '[.[] | select(.actor == $user)] | del(.[].actor) | .[]' \
      "$TMPDIR_DATA"/events_* 2>/dev/null || true
  fi

  echo "=== ${gh_user} OPEN PRS ==="
  cat "$TMPDIR_DATA/${gh_user}_open_prs" 2>/dev/null || true

  echo "=== ${gh_user} MERGED PRS ==="
  cat "$TMPDIR_DATA/${gh_user}_merged_prs" 2>/dev/null || true

  echo "=== ${gh_user} ASSIGNED ISSUES ==="
  cat "$TMPDIR_DATA/${gh_user}_assigned_issues" 2>/dev/null || true

  echo "=== ${gh_user} ISSUE EDITS ==="
  if compgen -G "$TMPDIR_DATA/issue_edits_*" > /dev/null 2>&1; then
    jq -s --arg user "$gh_user" \
      '[.[] | select(.edits | any(.editor == $user))]
       | .[]
       | .edits = [.edits[] | select(.editor == $user)]' \
      "$TMPDIR_DATA"/issue_edits_* 2>/dev/null || true
  fi

  echo "=== ${gh_user} TIME ==="
  cat "$TMPDIR_DATA/${gh_user}_time" 2>/dev/null || echo '[]'
done
