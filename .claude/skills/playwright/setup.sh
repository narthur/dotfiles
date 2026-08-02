#!/usr/bin/env bash
# Setup/repair script for the playwright-cli skill.
# Run this to install or upgrade @playwright/cli and regenerate the wrapper.
set -euo pipefail

NODE_VERSION="22.16.0"
NODE_INSTALL="$HOME/.asdf/installs/nodejs/$NODE_VERSION"
NODE_BIN="$NODE_INSTALL/bin/node"
NPM_CLI="$NODE_INSTALL/lib/node_modules/npm/bin/npm-cli.js"
WRAPPER="$HOME/.local/bin/playwright-cli"

echo "==> Checking node $NODE_VERSION install..."
if [[ ! -x "$NODE_BIN" ]]; then
  echo "ERROR: Node $NODE_VERSION not found at $NODE_BIN"
  echo "Install it with: asdf install nodejs $NODE_VERSION"
  exit 1
fi

echo "==> Installing @playwright/cli into node $NODE_VERSION..."
"$NODE_BIN" "$NPM_CLI" install -g @playwright/cli@latest \
  --prefix "$NODE_INSTALL"

PLAYWRIGHT_CLI_JS="$NODE_INSTALL/lib/node_modules/@playwright/cli/playwright-cli.js"

if [[ ! -f "$PLAYWRIGHT_CLI_JS" ]]; then
  echo "ERROR: playwright-cli.js not found after install — check npm output above."
  exit 1
fi

echo "==> Writing wrapper to $WRAPPER..."
mkdir -p "$(dirname "$WRAPPER")"
cat > "$WRAPPER" <<WRAPPER_EOF
#!/usr/bin/env bash
# Pinned playwright-cli wrapper — uses node $NODE_VERSION directly,
# bypassing asdf version selection so this works from any project
# regardless of that project's .tool-versions node setting.
#
# Re-run ~/.claude/skills/playwright/setup.sh if you upgrade the
# @playwright/cli package or switch to a different node install.

# \$HOME is escaped so it stays literal in the generated wrapper -- the wrapper is
# tracked in the public dotfiles repo, and an expanded path would bake in the
# username. \$NODE_VERSION is deliberately NOT escaped: the pin is the point.
NODE=\$HOME/.asdf/installs/nodejs/$NODE_VERSION/bin/node
PLAYWRIGHT_CLI=\$HOME/.asdf/installs/nodejs/$NODE_VERSION/lib/node_modules/@playwright/cli/playwright-cli.js

if [[ ! -x "\$NODE" ]]; then
  echo "ERROR: Node not found at \$NODE" >&2
  echo "Run ~/.claude/skills/playwright/setup.sh to fix." >&2
  exit 1
fi

if [[ ! -f "\$PLAYWRIGHT_CLI" ]]; then
  echo "ERROR: @playwright/cli not found at \$PLAYWRIGHT_CLI" >&2
  echo "Run ~/.claude/skills/playwright/setup.sh to fix." >&2
  exit 1
fi

exec "\$NODE" "\$PLAYWRIGHT_CLI" "\$@"
WRAPPER_EOF

chmod +x "$WRAPPER"

echo "==> Reshimming asdf to register playwright-cli shim..."
asdf reshim nodejs "$NODE_VERSION" 2>/dev/null || true

echo ""
echo "Done! playwright-cli is available at $WRAPPER"
"$WRAPPER" --version
