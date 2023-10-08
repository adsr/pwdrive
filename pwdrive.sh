#!/bin/bash
set -o pipefail

pwdrive_desc='GnuPG+GDrive-based password vault'
pwdrive_url='https://github.com/adsr/pwdrive'
pwdrive_version='0.5'
pwdrive_cmd=$1
shift

pwdrive_main() {
    _set_globals
    _check_reqs
    _maybe_init
    case "$pwdrive_cmd" in
        ls)         _require_access_token && pwdrive_ls "$@";;
        set)        _require_access_token && pwdrive_set "$@";;
        get)        _require_access_token && pwdrive_get "$@";;
        copy)       _require_access_token && pwdrive_copy "$@";;
        lget)       _require_access_token && pwdrive_lget "$@";;
        lcopy)      _require_access_token && pwdrive_lcopy "$@";;
        grep)       _require_access_token && pwdrive_grep "$@";;
        edit)       _require_access_token && pwdrive_edit "$@";;
        rm)         _require_access_token && pwdrive_rm "$@";;
        mv)         _require_access_token && pwdrive_mv "$@";;
        token)      _require_access_token && pwdrive_token "$@";;
        lsw)        ;&
        ls_write)   _require_access_token && pwdrive_ls >$ls_entries;;
        lsr)        ;&
        ls_read)    cat $ls_entries 2>/dev/null;;
        ls_exists)  test -f $ls_entries;;
        lsd)        ;&
        ls_diff)    diff <("$0" ls) <("$0" lsr);;
        gen)        pwdrive_gen "$@";;
        help)       pwdrive_usage 0;;
        *)          pwdrive_usage 1;;
    esac
}

pwdrive_usage() {
    _print_header
    echo "Usage:"
    echo "    pwdrive <command> [argv]"
    echo
    echo "Commands:"
    echo "    ls                    List all entries"
    echo "    ls <str>              List all entries prefixed by str"
    echo "    set <entry>           Set password for entry via prompt"
    echo "    set <entry> -         Set password for entry from stdin"
    echo "    set <entry> <pass>    Set password for entry (not preferred)"
    echo "    get <entry>           Print password for entry on stdout"
    echo "    copy <entry>          Copy password to clipboard (via \$PWDRIVE_COPY_CMD)"
    echo "    lget <str>            Get entry matching str, or ls if multiple"
    echo "    lcopy <str>           Copy entry matching str, or ls if multiple"
    echo "    grep <str>            Print entries matching str"
    echo "    edit <entry>          Edit password for entry (via \$EDITOR)"
    echo "    rm <entry>            Remove entry"
    echo "    mv <from> <to>        Rename entry"
    echo "    token                 Print an access token"
    echo "    gen                   Generate some random passwords"
    echo "    help                  Show pwdrive usage"
    echo
    echo "Environment:"
    echo "    EDITOR                Editor to use with edit (${EDITOR:-<unset>})"
    echo "    PWDRIVE_ACCESS_TOKEN  Use this access token instead of fetching one"
    echo "    PWDRIVE_HOME          Home dir of pwdrive ($home_dir)"
    echo "    PWDRIVE_GPG_ARGS      Extra args for get/set (${gpg_args:-<none>})"
    echo "    PWDRIVE_COPY_CMD      Copy command (${copy_cmd:-<none>})"
    echo "    PWDRIVE_PORT          Port to listen on for OAuth callback (${listen_port})"
    exit $1
}

pwdrive_ls() {
    query=''
    [ -n "$1" ] && query="q=name contains '$1'"
    response=$(curl -sf 'https://www.googleapis.com/drive/v3/files' \
        -G -X GET \
        -H "Authorization: Bearer $access_token" \
        -d 'spaces=appDataFolder' \
        -d 'pageSize=1000' \
        --data-urlencode "$query")
    [ "$?" -eq 0 ] || _die "Query failed: www.googleapis.com/drive/v3/files (pwdrive_ls)"
    echo $response | grep -Po '(?<="name": ").+?(?=")' | sort
}

pwdrive_get() {
    [ -n "$1" ] || _die "Expected entry param (pwdrive_get)"
    _fetch_file_id_by_name "$1"
    [ -n "$file_id" ] || _die "Nothing found for '$1' (pwdrive_get)"
    response=$(curl -sf "https://www.googleapis.com/drive/v3/files/$file_id" \
        -G -X GET \
        -H "Authorization: Bearer $access_token" \
        -d "alt=media")
    [ "$?" -eq 0 ] || _die "Query failed: www.googleapis.com/drive/v3/files/$file_id (pwdrive_get)"
    echo $response | base64 -w0 -d | gpg $gpg_args --decrypt
    echo
}

pwdrive_copy() {
    { out=$(pwdrive_get "$1" 2>&$err); } {err}>&2
    [ "$?" -eq 0 ] || exit 1
    echo -n "$out" | $copy_cmd
}

pwdrive_lget() {
    [ -n "$1" ] || _die "Expected str param (pwdrive_lget)"
    entries=$(pwdrive_ls | grep "$1")
    if [ -z "$entries" ]; then
        _die "Nothing found for '$1'"
    elif [ $(echo "$entries" | wc -l) -eq 1 -a -n "$entries" ]; then
        pwdrive_get $entries
    else
        echo "$entries"
    fi
}

pwdrive_lcopy() {
    [ -n "$1" ] || _die "Expected str param (pwdrive_lcopy)"
    entries=$(pwdrive_ls | grep "$1")
    if [ -z "$entries" ]; then
        _die "Nothing found for '$1'"
    elif [ $(echo "$entries" | wc -l) -eq 1 -a -n "$entries" ]; then
        pwdrive_copy $entries
    else
        echo "$entries"
    fi
}

pwdrive_grep() {
    [ -n "$1" ] || _die "Expected str param (pwdrive_grep)"
    pwdrive_ls | grep "$1"
}

pwdrive_set() {
    name="$1"
    [ -n "$name" ] || _die "Expected entry param (pwdrive_set)"
    [ "$stdin_is_pipe" -eq 1 -o "$2" = '-' ] && pass="$(cat)"
    [ -z "$pass" -a -n "$2" ] && pass="$2"
    if [ -z "$pass" ]; then
        read -sp 'Enter password:' pass1; echo
        read -sp 'Enter password again:' pass2; echo
        [ "$pass1" = "$pass2" ] || _die "Passwords do not match (pwdrive_set)"
        pass=$pass1
    fi
    [ -n "$pass" ] || _die "Expected pass as stdin, param, or input (pwdrive_set)"
    _fetch_file_id_by_name "$name"
    if [ -n "$file_id" ]; then
        method='PATCH'
        uri="/$file_id"
    else
        method='POST'
        uri=''
    fi
    post_data=$(mktemp /tmp/pwdrive.XXXXXX)
    echo -en "--$boundary\r\n" >$post_data
    echo -en "Content-Type: application/json; charset=UTF-8\r\n\r\n" >>$post_data
    if [ $method == "POST" ]; then
        echo -en "{\"parents\":[\"appDataFolder\"],\"name\":\"$name\"}\r\n" >>$post_data
    else
        echo -en "{\"name\":\"$name\"}\r\n" >>$post_data
    fi
    echo -en "--$boundary\r\n" >>$post_data
    echo -en "Content-Type: application/octet-stream\r\n\r\n" >>$post_data
    echo -n "$pass" | gpg $gpg_args --encrypt | base64 -w0 >>$post_data
    echo -en "\r\n--$boundary--" >>$post_data
    curl -sf "https://www.googleapis.com/upload/drive/v3/files$uri?uploadType=multipart" \
       -X $method \
       -H "Content-Type: multipart/related; boundary=$boundary" \
       -H "Authorization: Bearer $access_token" \
       --data-binary "@$post_data" >/dev/null
    curlec="$?"
    rm -f $post_data
    [ "$curlec" -eq 0 ] || _die "Query failed: www.googleapis.com/upload/drive/v3/files (pwdrive_set)"
}

pwdrive_edit() {
    [ -n "$EDITOR" ] || _die "Expected EDITOR env var (pwdrive_edit)"
    edit_content=$(pwdrive_get "$@")
    [ "$?" -eq 0 ] || _die "Get failed (pwdrive_edit)"
    edit_file=$(mktemp /tmp/pwdrive.XXXXXX)
    echo "$edit_content" >$edit_file
    $EDITOR $edit_file
    [ "$?" -eq 0 ] || { rm -f $edit_file; _die "EDITOR exited non-zero (pwdrive_edit)"; }
    (stdin_is_pipe=1; pwdrive_set "$@" <$edit_file)
    rm -f $edit_file
    [ "$?" -eq 0 ] || _die "Set failed (pwdrive_edit)"
}

pwdrive_rm() {
    _fetch_file_id_by_name "$1"
    [ -n "$file_id" ] || _die "Nothing found for '$1' (pwdrive_rm)"
    curl -sf "https://www.googleapis.com/drive/v3/files/$file_id" \
        -X DELETE \
        -H "Authorization: Bearer $access_token"
    [ "$?" -eq 0 ] || _die "Query failed: www.googleapis.com/drive/v3/files/$file_id (pwdrive_rm)"
}

pwdrive_mv() {
    local target=$1
    local rename=$2
    [ -n "$target" ] || _die "Expected target param (pwdrive_mv)"
    [ -n "$rename" ] || _die "Expected rename param (pwdrive_mv)"
    { pwdrive_get "$target" | pwdrive_set "$rename" -; } && pwdrive_rm "$target"
}

pwdrive_token() {
    echo $access_token
}

pwdrive_gen() {
    _pwdrive_gen_rand
    _pwdrive_gen_words
}

_pwdrive_gen_words() {
    command -v shuf &>/dev/null  || return
    command -v paste &>/dev/null || return
    [ -f /usr/share/dict/words ] || return
    local tweak_odds=50
    local p=0; while [ $p -lt 8 ]; do
        local pw=''
        local q=0; while [ $q -lt 3 ]; do
            pw+=$(_pwdrive_gen_word $tweak_odds)
            pw+=' '
            q=$((q+1))
        done
        echo $pw
        p=$((p+1))
        tweak_odds=$((tweak_odds / 2))
    done
}

_pwdrive_gen_word() {
    local tweak_odds=$1
    [ $tweak_odds -lt 8 ] && tweak_odds=8
    local nums='0123456789'
    local syms='!#$%&*+-=?@^_'
    local w=$(shuf -n1 /usr/share/dict/words)
    local word=''
    for ((i=0; i<${#w}; i++)); do
        c=${w:i:1}
        [ "$c" == "'" ] && continue
        [ $i -eq 0 ] && word+=$c && continue
        case $((RANDOM % tweak_odds)) in
            0) word+=${c^} ;;
            1) word+=${nums:$(($RANDOM % ${#nums})):1} ;;
            2) word+=${syms:$(($RANDOM % ${#syms})):1} ;;
            *) word+=$c ;;
        esac
    done
    echo $word
}

_pwdrive_gen_rand() {
    local chars='abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#$%&*+-=?@^_'
    local nchars=${#chars}
    local p=0; while [ $p -lt 8 ]; do
        local pw=''
        local q=0; while [ $q -lt 24 ]; do
            r=$((RANDOM % nchars))
            c=${chars:r:1}
            pw+=$c
            q=$((q+1))
        done
        echo $pw
        p=$((p+1))
    done
}

_die() {
    echo "$@" >&2
    exit 1
}

_set_globals() {
    home_dir="${PWDRIVE_HOME:-$HOME/.pwdrive}"
    client_id='118479055818-svi4vafeo8g5ka4dbauopo1o4s9j7qra.apps.googleusercontent.com'
    # TODO Figure out if Google offers a way to do OAuth without a secret
    client_secret='86Ev0arsPbBlp6J5v9IZU4Rq'
    scope='https://www.googleapis.com/auth/drive.appdata+https://www.googleapis.com/auth/drive.file'
    listen_port="${PWDRIVE_PORT:-49871}"
    redirect_uri="http://localhost:$listen_port/"
    refresh_token_path="$home_dir/refresh_token"
    ls_entries="$home_dir/entries"
    boundary='925a89b43f3caff507db0a86d20a2428007f10b6'
    gpg_args="${PWDRIVE_GPG_ARGS:---no-options --default-recipient-self --quiet}"
    copy_cmd="${PWDRIVE_COPY_CMD:-xclip -sel c}"
    _set_netcat_prog
    stdin_is_pipe=0;  [ -t 0 ] || stdin_is_pipe=1
    stdout_is_pipe=0; [ -t 1 ] || stdout_is_pipe=1
}

_set_netcat_prog() {
    for netcat_prog in nc ncat netcat; do
        command -v $netcat_prog &>/dev/null && return
    done
    _die "Expected nc, ncat, or netcat in PATH (_set_netcat_prog)"
}

_check_reqs() {
    for req in gpg curl grep mktemp mkdir cat base64; do
        command -v $req &>/dev/null || _die "Expected $req in PATH (_check_reqs)"
    done
}

_print_header() {
    echo -en '\xe2\x94\x8f'
    printf   '\xe2\x94\x81%.0s' {1..40}
    echo -e  '\xe2\x94\x93'
    printf   '\xe2\x94\x83 %-38s \xe2\x94\x83\n' "pwdrive v${pwdrive_version}"
    printf   '\xe2\x94\x83 %-38s \xe2\x94\x83\n' ""
    printf   '\xe2\x94\x83 %-38s \xe2\x94\x83\n' "$pwdrive_desc"
    printf   '\xe2\x94\x83 %-38s \xe2\x94\x83\n' "$pwdrive_url"
    echo -en '\xe2\x94\x97'
    printf   '\xe2\x94\x81%.0s' {1..40}
    echo -e  '\xe2\x94\x9b\n'
}

_maybe_init() {
    [ -d "$home_dir" ] || mkdir -p $home_dir
}

_require_access_token() {
    if [ -n "$PWDRIVE_ACCESS_TOKEN" ]; then
        access_token="$PWDRIVE_ACCESS_TOKEN"
        return
    elif [ -s "$refresh_token_path" ]; then
        refresh_token=$(cat $refresh_token_path)
    else
        _fetch_refresh_token
        [ -n "$refresh_token" ] || _die "Failed to get refresh token (_require_access_token)"
        echo -n "$refresh_token" >$refresh_token_path
    fi
    _fetch_access_token
    [ -n "$access_token" ] || _die "Failed to get access token. Run 'rm -f $refresh_token_path' and try again. (_require_access_token)"
}

_fetch_refresh_token() {
    local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=$client_id&scope=$scope&redirect_uri=$redirect_uri&response_type=code"
    echo 'Visit the following auth URL:'
    echo
    echo "    $auth_url"
    echo
    echo 'and allow access. This will timeout in 60 seconds.'
    local code=$(echo -en "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n" | \
        $netcat_prog -w60 -v -l -p $listen_port | \
        grep -m1 -Po '(?<=code=).+(?=&)')
    [ -n "$code" ] || _die "Empty auth code (_fetch_refresh_token)"
    response=$(curl -sf 'https://accounts.google.com/o/oauth2/token' \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "redirect_uri=$redirect_uri" \
        -d 'grant_type=authorization_code' \
        -d "code=$code")
    [ "$?" -eq 0 ] || _die "Query failed: accounts.google.com/o/oauth2/token (_fetch_refresh_token)"
    refresh_token=$(echo $response | grep -Po '(?<="refresh_token")\s*:\s*".+?(?=")' | grep -Po '(?<=").+')
}

_fetch_access_token() {
    response=$(curl -s 'https://accounts.google.com/o/oauth2/token' \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d 'grant_type=refresh_token' \
        -d "refresh_token=$refresh_token")
    [ "$?" -eq 0 ] || _die "Query failed: accounts.google.com/o/oauth2/token (_fetch_access_token)"
    access_token=$(echo $response | grep -Po '(?<="access_token")\s*:\s*".+?(?=")' | grep -Po '(?<=").+')
}

_fetch_file_id_by_name() {
    response=$(curl -sf 'https://www.googleapis.com/drive/v3/files' \
        -G -X GET \
        -H "Authorization: Bearer $access_token" \
        -d 'spaces=appDataFolder' \
        --data-urlencode "q=name = '$1'")
    [ "$?" -eq 0 ] || _die "Query failed: www.googleapis.com/drive/v3/files (_fetch_file_id_by_name)"
    file_id=$(echo $response | grep -Po '(?<="id": ").+?(?=")')
}

pwdrive_main "$@"
