#!/usr/bin/env bash
# <xbar.title>Buzz Next</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.desc>Shows the next buzz task in the menu bar.</xbar.desc>
# <xbar.dependencies>buzz</xbar.dependencies>

export PATH="$HOME/.local/bin:$PATH"

result=$(buzz next 2>/dev/null)

if [ -z "$result" ]; then
    echo "✓ no tasks"
else
    echo "$result"
fi

# Dropdown: goals due today, each linking to bm.taskratchet.com.
today=$(buzz today 2>/dev/null)
if [ -n "$today" ]; then
    echo "---"
    echo "Due today | color=#888888"
    printf '%s\n' "$today" | while read -r slug rest; do
        [ -z "$slug" ] && continue
        echo "$slug  $rest | href=https://bm.taskratchet.com/goal/$slug"
    done
fi
