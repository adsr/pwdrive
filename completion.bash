#!/bin/bash

_pwdrive_completion() {
    local c0; c0=${COMP_WORDS[COMP_CWORD]}
    local c1; c1=${COMP_WORDS[COMP_CWORD-1]}

    case ${COMP_CWORD} in
        1) COMPREPLY=($(compgen -W "ls lsw lsr lsd set get copy lget lcopy grep edit rm mv token gen help" -- ${c0})) ;;
        2) case ${c1} in
            set|get|copy|edit|rm|mv) COMPREPLY=($(compgen -W "$(_pwdrive_entries)" -- ${c0})) ;;
            *) COMPREPLY=() ;;
        esac ;;
        *) COMPREPLY=() ;;
    esac
}

_pwdrive_entries() {
    pwdrive lse || pwdrive lsw
    pwdrive lsr | tr '\n' ' '
}

complete -F _pwdrive_completion pwdrive
