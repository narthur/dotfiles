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
