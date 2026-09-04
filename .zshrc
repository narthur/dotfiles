# Source environment variables
if [ -f ~/.env ]; then
    . ~/.env
fi

# Dotfiles management
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias dotprivate='git --git-dir=$HOME/.dotprivate --work-tree=$HOME'

# PATH
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# asdf shims
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

# pnpm
export PNPM_HOME="/Users/narthur/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Colima as Docker host
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"

# zoxide - must be last
autoload -Uz compinit && compinit
eval "$(zoxide init zsh)"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Vite+ bin (https://viteplus.dev)
[ -f "$HOME/.vite-plus/env" ] && . "$HOME/.vite-plus/env"

# Starship prompt - must be last
eval "$(starship init zsh)"

# --- Interactive shell upgrades (fzf-tab, fzf, zsh-autosuggestions, atuin) ---
# order matters: fzf-tab needs compinit first; atuin after fzf so it wins Ctrl-R
source /opt/homebrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh
source <(fzf --zsh)
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
eval "$(atuin init zsh)"

# Disable Claude Code mouse click capture (stops accidental prompt submits; keeps scroll + restores terminal link/text selection)
export CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1
