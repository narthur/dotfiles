#!/bin/bash
# Initialize Portfolio Registry from existing projects
# Scans /mnt/backup/ProgrammingProjects and creates registry with all projects disabled by default

set -euo pipefail

PROJECTS_DIR="/mnt/backup/ProgrammingProjects"
REGISTRY_FILE="${HOME}/.claude/portfolio-registry.json"

echo "Scanning projects in ${PROJECTS_DIR}..."

# Start building JSON
cat > "$REGISTRY_FILE" <<'EOF'
{
  "projects": [
EOF

first=true
for dir in "${PROJECTS_DIR}"/*; do
    if [[ ! -d "$dir" ]]; then
        continue
    fi

    project_name=$(basename "$dir")
    project_path="$dir"

    # Try to detect tech stack
    tech_stack="[]"
    if [[ -f "${dir}/package.json" ]]; then
        if [[ -f "${dir}/tsconfig.json" ]]; then
            tech_stack='["Node.js", "TypeScript"]'
        else
            tech_stack='["Node.js", "JavaScript"]'
        fi
    elif [[ -f "${dir}/Gemfile" ]]; then
        tech_stack='["Ruby", "Rails"]'
    elif [[ -f "${dir}/go.mod" ]]; then
        tech_stack='["Go"]'
    elif [[ -f "${dir}/composer.json" ]]; then
        tech_stack='["PHP"]'
    elif [[ -f "${dir}/requirements.txt" ]] || [[ -f "${dir}/setup.py" ]]; then
        tech_stack='["Python"]'
    fi

    # Try to detect GitHub repo
    github_repo=""
    if [[ -d "${dir}/.git" ]]; then
        remote_url=$(cd "$dir" && git remote get-url origin 2>/dev/null || echo "")
        if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^.]+) ]]; then
            github_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        fi
    fi

    # Try to detect product family
    # Customize these patterns for your own project families
    family=""
    if [[ "$project_name" =~ ^myapp ]]; then
        family="MyApp"
    elif [[ "$project_name" =~ ^utils ]]; then
        family="Utils"
    fi

    # Add comma before all but first entry
    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo "," >> "$REGISTRY_FILE"
    fi

    # Write project entry
    cat >> "$REGISTRY_FILE" <<ENTRY
    {
      "id": "${project_name}",
      "path": "${project_path}",
      "family": "${family}",
      "github_repo": "${github_repo}",
      "tech_stack": ${tech_stack},
      "orchestration": {
        "enabled": false,
        "priority": "medium",
        "auto_capture_todos": false,
        "auto_execute": false,
        "auto_execute_max_complexity": "medium",
        "require_tests": true,
        "blocked_keywords": []
      }
    }
ENTRY
done

# Close projects array and add families section
cat >> "$REGISTRY_FILE" <<'EOF'
  ],
  "families": {
    "ProjectA": {
      "projects": [],
      "release_coordination": "coordinated"
    },
    "ProjectB": {
      "projects": [],
      "release_coordination": "coordinated"
    },
    "ProjectC": {
      "projects": [],
      "release_coordination": "independent"
    },
    "ProjectD": {
      "projects": [],
      "release_coordination": "independent"
    },
    "ProjectE": {
      "projects": [],
      "release_coordination": "independent"
    }
  }
}
EOF

# Now populate family project lists
for family in "ProjectA" "ProjectB" "ProjectC" "ProjectD" "ProjectE"; do
    family_projects=$(jq -r --arg family "$family" '.projects[] | select(.family == $family) | .id' "$REGISTRY_FILE" | jq -R . | jq -s .)
    jq --arg family "$family" --argjson projects "$family_projects" \
        '.families[$family].projects = $projects' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"
done

echo "Portfolio registry created at ${REGISTRY_FILE}"
echo "Total projects: $(jq '.projects | length' "$REGISTRY_FILE")"
echo ""
echo "All projects are disabled by default."
echo "Use /orchestrate-config to enable projects for orchestration."
