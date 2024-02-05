function set_termtitle_preexec() {
    local prompt_padding=" | "
    first_arg=${2%% *}
    ! command -v ${first_arg} > /dev/null 2>&1 && return
    [[ ${first_arg} =~ ^(${PROMPT_NO_SET_TITLE//,/|})$ ]] && return

    comm=${1}
    local _short_path
    integer surplus dir_surplus cmd_surplus
    surplus=$(( ( ${#${PWD/#$HOME/~}} + ${#comm} ) - $PROMPT_TRUNCATE_AT ))

    (( cmd_surplus = dir_surplus = surplus / 2 ))
    # zsh rounds down by default
    (( surplus % 2 != 0 )) && dir_surplus+=1

    local title_string="\e]2;%D{%T}$prompt_padding"
    if [[ "$PWD" != "$HOME" ]]; then
        _short_path="$(truncate_dir_path $(( $PROMPT_TRUNCATE_AT - dir_surplus - ${#prompt_padding} )))"
        title_string+="$_short_path${prompt_padding}"
    fi

    if (( cmd_surplus > 0 )); then
        integer left_cmd_surplus right_cmd_surplus
        (( right_cmd_surplus = left_cmd_surplus = cmd_surplus / 2 ))
        (( cmd_surplus % 2 != 0 )) && right_cmd_surplus+=1
        integer halfclength=$(( ${#comm} / 2 ))
        comm[$(( halfclength - left_cmd_surplus + 1 )),$(( halfclength + right_cmd_surplus ))]="…"
    fi
    title_string+="${(q)comm}\a"
    print -nP -- "$title_string"
}

function set_termtitle_precmd() {
    if [[ $? != 0 ]]; then
        local _short_path="$(truncate_dir_path $(($PROMPT_TRUNCATE_AT - ${#PROMPT_ERR_ICON} - 1)))"
        print -n -- "\e]2;${_short_path} ${PROMPT_ERR_ICON}\a"
    else
        local _short_path="$(truncate_dir_path)"
        print -n -- "\e]2;${_short_path}\a"
    fi
}

typeset -g __zero='%([BSUbfksu]|([FK]|){*})'

function truncate_prompt() {
    unset PROMPT_WS_SEP
    local __prompt_non_truncated=
    # __prompt_non_truncated+='${SSH_CONNECTION:+%B[%b$PROMPT_SSH_NAME%B]%b }'
    # __prompt_non_truncated+='$PROMPT_READ_ONLY_DIR'
    # __prompt_non_truncated+='$exec_time'

    # __prompt_non_truncated+='${GITSTATUS}'
    # typeset -i surplus=$(( COLUMNS - ${#${(S%%)${(e)__prompt_non_truncated}//$~__zero/}} ))

    if (( ${#${(S%%)${(e)PROMPT}//$~__zero/}} > COLUMNS / 3 )); then
        export PROMPT_WS_SEP=$'\n'
    fi
}

function chpwd_hook() {
    unset GITSTATUS
    (( ZSH_SUBSHELL )) || osc7-pwd
    [[ -w "$PWD" ]] && unset PROMPT_READ_ONLY_DIR || export PROMPT_READ_ONLY_DIR=" %F{18}${PROMPT_READ_ONLY_ICON}%f"
}

function truncate_dir_path() {
    typeset __truncate_at=${1:-$PROMPT_TRUNCATE_AT}
    typeset truncate_path="${2:-$PWD}"
    typeset -a parts
    local pd

    if [[ "${truncate_path}/" == ${HOME}/* ]]; then
        __short_path="~"
        pd="${truncate_path/#$HOME/~}"
    else
        __short_path=""
        pd="$truncate_path"
    fi

    typeset -a parts=(${(@s[/])pd})
    local clean_pd="${${(S%%)${(e)pd}//$~__zero/}}"
    typeset -a clean_parts=(${(@s[/])clean_pd})

    local num_of_elems=${#parts}
    typeset -i slashes=$(($num_of_elems - 1 ))

    local length=${clean_pd//\//}
    typeset -i _num_of_chars_too_long=$(( ${#clean_pd} - $__truncate_at ))

    (( _num_of_chars_too_long < 0 )) && print -n $pd && return

    _index_of_elem_to_truncate=$(( num_of_elems - 1 ))
    while (( $_num_of_chars_too_long > 0 )) && (( _index_of_elem_to_truncate > 0 )); do

        (( _cur_part_len = ${#clean_parts[$_index_of_elem_to_truncate]} ))

        local clean_elem=${clean_parts[$_index_of_elem_to_truncate]}
        if (( $_num_of_chars_too_long >= $_cur_part_len )); then
            parts[$_index_of_elem_to_truncate]="${parts[$_index_of_elem_to_truncate]/$clean_elem/…}"
            clean_parts[$_index_of_elem_to_truncate]="…"
        else

            if (( _cur_part_len % 2 != 0 )); then
                (( _divide_at = ( _cur_part_len + 1 ) / 2 ))
            else
                (( _divide_at = _cur_part_len / 2 ))
            fi

            if (( _num_of_chars_too_long % 2 != 0 )); then
                (( _eat_this_many_left = ( _num_of_chars_too_long - 1 ) / 2 ))
                (( _eat_this_many_right = ( _num_of_chars_too_long + 1 ) / 2 ))
            else
                (( _eat_this_many_left = _num_of_chars_too_long / 2 ))
                (( _eat_this_many_right = _num_of_chars_too_long / 2 ))
            fi

            (( _we_need_this_left = $_divide_at - _eat_this_many_left - 1 ))
            (( _we_need_this_right = $_divide_at + _eat_this_many_right ))
            local truncated_clean="${clean_parts[$_index_of_elem_to_truncate]:0:$_we_need_this_left}…${clean_parts[$_index_of_elem_to_truncate]:$_we_need_this_right}"

            parts[$_index_of_elem_to_truncate]="${parts[$_index_of_elem_to_truncate]/$clean_elem/$truncated_clean}"
            clean_parts[$_index_of_elem_to_truncate]="$truncated_clean"
        fi

        (( _index_of_elem_to_truncate == num_of_elems )) && break # pwd is last folder to get truncated

        printf -v length '%s' "${clean_parts[@]}"
        _index_of_elem_to_truncate=$(( $_index_of_elem_to_truncate - 1 ))
        (( _num_of_chars_too_long = ${#length} + $slashes - $__truncate_at))

        if (( _index_of_elem_to_truncate == 1 )); then
            _index_of_elem_to_truncate=$num_of_elems
            continue
        fi

    done

    local part
    for part in "${parts[@]:1}"; do
        __short_path+=/$part
    done

    print -n $__short_path
}

function preexec_hook() {
    unset exec_time
    typeset -g cmd_exec_timestamp=$EPOCHSECONDS
    if [[ ${_git_fetch_pwds[${VCS_STATUS_WORKDIR}]:-0} != 0 ]]\
    && [[ $2 =~ git\ (.*\ )?(pull|push|fetch)(\ .*)?$ ]]
    then
        kill -SIGTERM -- -$_git_fetch_pwds[${VCS_STATUS_WORKDIR}] 2> /dev/null
        _git_fetch_pwds[${VCS_STATUS_WORKDIR}]=0
    fi
}

# Stores (into exec_time) the execution
# time of the last command if set threshold was exceeded.
# taken from Sindre Sorhus
# https://github.com/sindresorhus/pretty-time-zsh
check_cmd_exec_time() {
    integer elapsed
    (( elapsed = EPOCHSECONDS - ${cmd_exec_timestamp:-$EPOCHSECONDS} ))
    (( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
        local human total_seconds=$elapsed
        local days=$(( total_seconds / 60 / 60 / 24 ))
        local hours=$(( total_seconds / 60 / 60 % 24 ))
        local minutes=$(( total_seconds / 60 % 60 ))
        local seconds=$(( total_seconds % 60 ))
        (( days > 0 )) && human+="${days}d "
        (( hours > 0 )) && human+="${hours}h "
        (( minutes > 0 )) && human+="${minutes}m "
        human+="${seconds}s"
        typeset -g exec_time=" %F{3}${human}"
    }
    unset cmd_exec_timestamp
}

write_git_status_after_fetch() {
    _repo_up_to_date[$VCS_STATUS_WORKDIR]=true
    _git_fetch_pwds[${VCS_STATUS_WORKDIR}]=0
    # $VCS_STATUS_WORKDIR refers to the git dir of the time the call
    # chain was started and might differ from the current git dir
    if [[ "$VCS_STATUS_WORKDIR" == $(git rev-parse --show-toplevel 2> /dev/null)  ]]; then
        build_git_status
    else
        unset VCS_STATUS_WORKDIR
    fi
}

build_git_status() {
    [[ $PWD != $VCS_STATUS_WORKDIR* ]] && unset GITSTATUS && return
    emulate -L zsh

    if [[ $_repo_up_to_date[$VCS_STATUS_WORKDIR] == true ]]; then
        local      branch='%F{2}'   # green foreground
    else
        local      branch='%F{4}'   # cyan foreground
    fi

    local      clean='%F{4}'  # cyan foreground
    local   modified='%F{3}'  # yellow foreground
    local      added='%F{10}'  # green foreground
    local  untracked='%F{18}' # grey foreground
    local conflicted='%F{2}'  # red foreground

    local p="%B"

    local where  # branch name, tag or commit
    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
        where=$VCS_STATUS_LOCAL_BRANCH
    elif [[ -n $VCS_STATUS_TAG ]]; then
        p+='%f#'
        where=$VCS_STATUS_TAG
    else
        p+='%f@'
        where=${VCS_STATUS_COMMIT[1,8]}
    fi

    (( $#where > 32 )) && where[13,-13]="…"  # truncate long branch names and tags
    p+="${branch} ${where//\%/%%}"             # escape %

    (( VCS_STATUS_COMMITS_BEHIND )) && p+=" ${clean}⇣${VCS_STATUS_COMMITS_BEHIND}"
    (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && p+=" "
    (( VCS_STATUS_COMMITS_AHEAD  )) && p+="${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" ${clean}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" "
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && p+="${clean}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    (( VCS_STATUS_STASHES        )) && p+=" ${clean}≡${VCS_STATUS_STASHES}"
    [[ -n $VCS_STATUS_ACTION     ]] && p+=" ${conflicted}${VCS_STATUS_ACTION}"
    (( VCS_STATUS_NUM_CONFLICTED )) && p+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    (( VCS_STATUS_NUM_STAGED     )) && p+=" ${added}+${VCS_STATUS_NUM_STAGED}"
    (( VCS_STATUS_NUM_UNSTAGED   )) && p+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    (( VCS_STATUS_NUM_UNTRACKED  )) && p+=" ${untracked}?${VCS_STATUS_NUM_UNTRACKED}"

    p+="%b%f"
    [[ "$GITSTATUS" == "$p" ]] && return 0

    export GITSTATUS="$p"
    truncate_prompt
    zle reset-prompt
}

update_git_status() {
    [[ $VCS_STATUS_RESULT != 'ok-async' ]] && unset GITSTATUS && return 0
    build_git_status
    (( ${+PROMPT_GIT_PROHIBIT_REMOTE} )) && return 0
    if [[ $(($EPOCHSECONDS - ${_last_checks[$VCS_STATUS_WORKDIR]:-0})) -gt ${_git_fetch_result_valid_for} ]]; then
        _repo_up_to_date[$VCS_STATUS_WORKDIR]=false
    else
        return 0
    fi
    _last_checks[$VCS_STATUS_WORKDIR]="$EPOCHSECONDS"
    { env GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o ConnectTimeout=$_git_connect_timeout -o BatchMode=yes" GIT_TERMINAL_PROMPT=0 /usr/bin/git -c gc.auto=0 -C "${VCS_STATUS_WORKDIR}" fetch --recurse-submodules=no > /dev/null 2>&1 &&\
    gitstatus_query -t -0 -c write_git_status_after_fetch "MY" } &!
    _git_fetch_pwds[${VCS_STATUS_WORKDIR}]="$!"
}

precmd_hook() {
    print -Pn "\e]133;A\e\\" # foot
    check_cmd_exec_time
    truncate_prompt
    gitstatus_query -t -0 -c update_git_status 'MY'
}


function osc7-pwd() {
    emulate -L zsh # also sets localoptions for us
    setopt extendedglob
    local LC_ALL=C
    printf '\e]7;file://%s%s\e\' $HOST ${PWD//(#m)([^@-Za-z&-;_~])/%${(l:2::0:)$(([##16]#MATCH))}}
}

() {
    # disable python's built in manipulation of the prompt in favor of our own
    unset VIRTUAL_ENV
    unset NVM_BIN
    export VIRTUAL_ENV_DISABLE_PROMPT=1

    typeset -gx PROMPT_READ_ONLY_DIR
    typeset -gA _last_checks
    typeset -gA _git_fetch_pwds
    typeset -gA _repo_up_to_date

    _git_fetch_result_valid_for=${_git_fetch_result_valid_for:-60}
    (( $_git_fetch_result_valid_for < 2 )) && _git_fetch_result_valid_for=2
    _git_connect_timeout=$((_git_fetch_result_valid_for -1))

    PROMPT_NO_SET_TITLE="${PROMPT_NO_SET_TITLE:-cd,..,clear,ls,stat,rmdir,mkdir,which,where,echo,print,rm,true,false,_zlua,time,file_opener,exa}"
    PROMPT_TRUNCATE_AT="${PROMPT_TRUNCATE_AT:-40}"

    # set fancy icons
    if (( ! ${+NO_PROMPT_FANCY_ICONS} )) && [[ $TERM != 'linux' ]]; then
        PROMPT_READ_ONLY_ICON="${PROMPT_READ_ONLY_ICON:-}"
        PROMPT_ERR_ICON="${PROMPT_ERR_ICON:-🞬}"
        PROMPT_SUCCESS_ICON="${PROMPT_SUCCESS_ICON:-❯}"
        prompt_eol='%F{1}❮❮❮%f'
    else
        PROMPT_READ_ONLY_ICON="${PROMPT_READ_ONLY_ICON:-RO}"
        PROMPT_ERR_ICON="${PROMPT_ERR_ICON:-X}"
        PROMPT_SUCCESS_ICON="${PROMPT_SUCCESS_ICON:-%%}"
        prompt_eol='%%'
    fi
    PROMPT_EOL_MARK=''

    # this has an optional dependency, namely the _raw_to_zsh_color function from
    # trobjo/zsh-common-functions that will color the path in the same colors as
    # the directory color set in LS_COLORS.
    (( ${+functions[_raw_to_zsh_color]} )) && PROMPT_DIR_COLOR=$(_raw_to_zsh_color ${_di_color_raw:-34}) ||\
    PROMPT_DIR_COLOR=${PROMPT_DIR_COLOR:-'%F{4}'}
    PROMPT_PATH_SEP_COLOR=${PROMPT_PATH_SEP_COLOR:-'%F{7}'}

    autoload -Uz add-zsh-hook

    if [[ -z $PROHIBIT_TERM_TITLE ]]; then
        add-zsh-hook preexec set_termtitle_preexec
        add-zsh-hook precmd set_termtitle_precmd
    fi

    add-zsh-hook chpwd chpwd_hook
    add-zsh-hook preexec preexec_hook
    add-zsh-hook precmd precmd_hook

    # Enable/disable the right prompt options.
    setopt no_prompt_bang prompt_percent prompt_subst

    # Start gitstatusd instance with name "MY". The same name is passed to
    # gitstatus_query in gitstatus_update_changes_only. The flags with -1 as values
    # enable staged, unstaged, conflicted and untracked counters.
    gitstatus_stop 'MY' && gitstatus_start -s -1 -u -1 -c -1 -d -1 'MY'

    typeset -gx _PROMPT=
    _PROMPT+='${SSH_CONNECTION:+%B[%b${PROMPT_SSH_NAME:-$HOST}%B]%b }'
    _PROMPT+='$(colorpath)'
    _PROMPT+='$PROMPT_READ_ONLY_DIR'
    _PROMPT+='$exec_time'
    _PROMPT+='${GITSTATUS}'
    _PROMPT+='${PROMPT_WS_SEP- }'
    PROMPT=$_PROMPT
    PROMPT+='%(?.%F{magenta}${PROMPT_SUCCESS_ICON}%f.%F{red}${PROMPT_ERR_ICON}%f) '
}
