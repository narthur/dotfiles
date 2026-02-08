---
userInvocable: true
---

# orchestrate-config

Manage orchestration settings for projects in the portfolio registry.

## Usage

```bash
# Enable a project for orchestration
/orchestrate-config enable <project-id>

# Disable a project
/orchestrate-config disable <project-id> [reason]

# Set project priority (high, medium, low)
/orchestrate-config priority <project-id> <priority>

# Enable auto-execute for a project
/orchestrate-config auto-execute <project-id> on

# Disable auto-execute for a project
/orchestrate-config auto-execute <project-id> off

# Enable all projects in a family
/orchestrate-config enable-family <family-name>

# Disable all projects in a family
/orchestrate-config disable-family <family-name>

# List all projects
/orchestrate-config list [--enabled-only]

# Show project details
/orchestrate-config show <project-id>

# Count enabled projects
/orchestrate-config count
```

## Examples

```bash
# Enable example-api for orchestration
/orchestrate-config enable example-api

# Set high priority for example-api
/orchestrate-config priority example-api high

# Enable auto-execution for example-api
/orchestrate-config auto-execute example-api on

# Enable all ProjectA projects
/orchestrate-config enable-family ProjectA

# List only enabled projects
/orchestrate-config list --enabled-only

# Disable an old project
/orchestrate-config disable old-experiment "Project abandoned"
```

## Priority Levels

- **high**: Process every cycle, auto-execute issues
- **medium**: Process every cycle, but no auto-execute (default)
- **low**: Process every 3rd cycle, capture TODOs only

## Families

Recognized product families:
- ProjectA
- ProjectB
- ProjectE
- ProjectC
- ProjectD
