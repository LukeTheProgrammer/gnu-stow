#! /bin/bash

# export PS1="\[\033[0;33m\]\u\[\033[0m\]:\[\033[0;32m\]\h\[\033[0m\]:\[\033[0;31m\]\w/\[\033[0m\]$ "

if [ -f ~/.git_aliases ]; then
    . ~/.git_aliases
fi

alias ll='ls -lah'

alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'

alias rc.push='/mnt/b/DEV/RedCat/redcat-rsync.sh push'
alias rc.pull='/mnt/b/DEV/RedCat/redcat-rsync.sh pull'
