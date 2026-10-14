
# Vite+ bin (https://viteplus.dev)
. "$HOME/.vite-plus/env"

# ggshield: python keyring can't reach the login keychain inside Claude Code's
# sandbox, but the `security` CLI can. Export the PAT so the pre-commit hook works.
: ${GITGUARDIAN_API_KEY:=$(security find-generic-password -s ggshield -w 2>/dev/null)}
export GITGUARDIAN_API_KEY
