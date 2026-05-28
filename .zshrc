# Source environment variables
if [ -f ~/.env ]; then
    . ~/.env
fi

# Dotfiles management
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias dotprivate='git --git-dir=$HOME/.dotfiles-private --work-tree=$HOME'

# PATH
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# zoxide - must be last
eval "$(zoxide init zsh)"
