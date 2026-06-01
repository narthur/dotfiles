# Source environment variables
if [ -f ~/.env ]; then
    . ~/.env
fi

# Dotfiles management
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias dotprivate='git --git-dir=$HOME/.dotfiles-private --work-tree=$HOME'

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
