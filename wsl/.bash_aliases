#! /bin/bash

if [ -f ~/.git_aliases ]; then
    . ~/.git_aliases
fi

alias ll='ls -lah'

alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias pint='./vendor/bin/pint'
alias phpstan='./vendor/bin/phpstan -b --allow-empty-baseline'
alias phpunit='./vendor/bin/phpunit --testdox --stop-on-error --stop-on-failure --display-deprecations'

rsync-tui() {
    local program="$HOME/Dev/scripts/rsync-tui/rsync-tui"
    if [ -x "$program" ]; then
        "$program" "$@"
    else
        echo "Error: rsync-tui not found or not executable at $program" >&2
        return 1
    fi
}
