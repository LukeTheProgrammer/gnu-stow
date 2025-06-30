# Homebrew
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"

# Windsurf
export PATH="/Users/luke/.codeium/windsurf/bin:$PATH"

# Import aliases
if [ -f ~/.zsh_aliases ]; then
    source $HOME/.zsh_aliases
fi

if [ -f ~/.git_aliases ]; then
    source $HOME/.git_aliases
fi

# alias ll='ls -lah'

export PATH="/usr/local/sbin:$PATH"

# ===================== #

# zinit 
# https://github.com/zdharma-continuum/zinit

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"

source "${ZINIT_HOME}/zinit.zsh"

# zinit plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions 

# ===================== #

# starship (theme)
# https://starship.rs/ 

eval "$(starship init zsh)"

# ===================== #

# Development directory home
export DEV_HOME="$HOME/Dev" 

# Android Dev 
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_SDK_ROOT=~/Library/Android/sdk

# nvm 
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm
export PNPM_HOME="/Users/luke/Library/pnpm"

case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
