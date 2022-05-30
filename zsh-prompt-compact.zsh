activate() {
    if [[ $VIRTUAL_ENV ]]; then
        print "Deactivate your current environment first"
        return 1
    fi
    typeset -aU venvs
    if [[ "${#@}" -eq 1 ]]; then
        venvs+="${1%/*}"
    else
        local file
        for file in ./*/pyvenv.cfg; do
            if [[ -f "$file" ]]; then
                venvs+="${file%/*}"
            fi
        done
    fi
    if [[ "${#venvs}" -eq 1 ]]; then
        source "${venvs[@]:0}/bin/activate"
        return 0
    elif [[ "${#venvs}" -gt 1 ]]; then
        print "More than one venv: \e[3m${venvs[@]##*/}\e[0m"
        print "Use \`activate <venv>\` to activate it"
        return 1
    elif [[ "${#venvs}" -eq 0 ]]; then
        print -n "No venv found${_ROOTED:+ in $(_colorizer $VCS_STATUS_WORKDIR)}"
        if [[ $VCS_STATUS_RESULT == 'ok-async' ]] && [[ "$PWD" != $VCS_STATUS_WORKDIR ]]; then
            print ", trying git root dir"
            _ROOTED=true
            cd $VCS_STATUS_WORKDIR
            activate
            local ret=$?
            cd $OLDPWD
            unset _ROOTED
            return $ret
        else
            print
            return 1
        fi
    fi
}

function set_termtitle_preexec() {
    first_arg=${2%% *}
    if command -v ${first_arg} > /dev/null 2>&1 && [[ ! ${first_arg} =~ ^(${PROMPT_NO_SET_TITLE//,/|})$ ]]; then
        comm=${1}
        if [[ "$PWD" != "$HOME" ]]; then
            if (( ${#${PWD/#$HOME/~}} + ${#comm} >= $PROMPT_TRUNCATE_AT )); then
                if (( $#comm > ${PROMPT_TRUNCATE_AT} / 2 )); then
                    local _left_half _right_half
                    if (( ${PROMPT_TRUNCATE_AT} % 2 != 0 )); then
                        (( _left_half = ( ${PROMPT_TRUNCATE_AT} + 1 ) / 4  ))
                        (( _right_half = ( ${PROMPT_TRUNCATE_AT} - 1 ) / 4 ))
                    else
                        (( _right_half = _left_half = ${PROMPT_TRUNCATE_AT} / 4 ))
                    fi
                    comm[(( $_left_half + 1 )),-$_right_half]="…"
                fi
                _short_path_old=$_short_path
                set_termtitle_pwd $(( $PROMPT_TRUNCATE_AT - ${#comm} - 3 ))
            fi
            print -n -- "\e]2;$_ssh$_short_path | ${(q)comm}\a"
        else
            if (( $#comm > ${PROMPT_TRUNCATE_AT} )); then
                local _left_half _right_half
                if (( ${PROMPT_TRUNCATE_AT} % 2 != 0 )); then
                    (( _left_half = ( ${PROMPT_TRUNCATE_AT} + 1 ) / 2  ))
                    (( _right_half = ( ${PROMPT_TRUNCATE_AT} - 1 ) / 2 ))
                else
                    (( _right_half = _left_half = ${PROMPT_TRUNCATE_AT} / 2 ))
                fi
                comm[(( $_left_half + 1 )),-$_right_half]="…"
            fi
            print -n -- '\e]2;'$_ssh${(q)comm}'\a'
        fi
    fi
}

function set_termtitle_precmd() {
    local __res=$?

    if [[ $_short_path_old ]]; then
        _short_path=$_short_path_old
        unset _short_path_old
    fi

    if [[ $__oldres != $__res ]]; then
        if [[ $__res != 0 ]]; then
            set_termtitle_pwd $(( $PROMPT_TRUNCATE_AT - ${#PROMPT_ERR_ICON} - 1 ))
        else
            set_termtitle_pwd
        fi
    fi

    if [[ $__res != 0 ]]; then
        print -n -- "\e]2;$_ssh${_short_path} ${PROMPT_ERR_ICON}\a"
    else
        print -n -- "\e]2;$_ssh${_short_path}\a"
    fi

    __oldres=$__res
}

function unset_short_path_old() {
    if [[ "$PWD" != "$OLDPWD" ]]; then
        [[ $PWD == ${VCS_STATUS_WORKDIR}* ]] || unset GITSTATUS
        unset _short_path_old PROMPT_READ_ONLY_DIR
        [[ -w "$PWD" ]] || export PROMPT_READ_ONLY_DIR=" %F{18}${PROMPT_READ_ONLY_ICON}%f"
        PROMPT_PWD=${${PWD/#$HOME/${PROMPT_DIR_COLOR}\~}//\//%{$reset_color%}${PROMPT_PATH_SEP_COLOR}\/${PROMPT_DIR_COLOR}}%b%f
    fi
}

function set_termtitle_pwd() {
    typeset -gx _short_path
    typeset -a parts

    if [[ "$PWD" == $HOME* ]]; then
        _short_path="~"
        pd="${PWD/#$HOME/~}"
    else
        _short_path=""
        pd="$PWD"
    fi

    parts=("${(@s[/])pd}")
    num_of_elems=${#parts}

    integer max_trunc
    if [[ ${#parts} -le 2 ]]; then
        (( max_trunc = 2 * num_of_elems + ${#parts[-1]} + 1  ))
    else
        (( max_trunc = 2 * num_of_elems + ${#parts[2]} + ${#parts[-1]} + 1  ))
    fi

    # If the maximum prompt truncation is still to long, we just truncate the middle of the string
    # not regarding the individual dirs
    if (( max_trunc > ${1:-$PROMPT_TRUNCATE_AT} )); then

        if (( ${1:-$PROMPT_TRUNCATE_AT} % 2 != 0 )); then
            (( _left_half = ( ${1:-$PROMPT_TRUNCATE_AT} + 1 ) / 2 - 2 ))
            (( _right_half = ( ${1:-$PROMPT_TRUNCATE_AT} - 1 ) / 2 - 2 ))
        else
            (( _right_half = ${1:-$PROMPT_TRUNCATE_AT} / 2 - 2 ))
            (( _left_half = ${1:-$PROMPT_TRUNCATE_AT} / 2 - 2 ))
        fi

        pd[$_left_half,-$_right_half]="……"
        _short_path=$pd
        return
    else
        # total length is the length of the strings themselves, the number of slashes,
        # the length of _short_path + 1 because we always need to add at least one slash
        length=${pd//\//}
        (( _num_of_chars_too_long = ${#length} + $num_of_elems + ${#_short_path} + 1 - ${1:-$PROMPT_TRUNCATE_AT} ))
        _index_of_elem_to_truncate=$(( num_of_elems - 1 ))
        while (( $_num_of_chars_too_long > 0 )) && (( $_index_of_elem_to_truncate > 2 )); do

            (( _cur_part_len = ${#parts[$_index_of_elem_to_truncate]} ))

            if (( $_num_of_chars_too_long > $_cur_part_len )); then
                parts[$_index_of_elem_to_truncate]="…"
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

                parts[$_index_of_elem_to_truncate]="${parts[$_index_of_elem_to_truncate]:0:$_we_need_this_left}…${parts[$_index_of_elem_to_truncate]:$_we_need_this_right}"
            fi

            printf -v length '%s' "${parts[@]}"
            _index_of_elem_to_truncate=$(( $_index_of_elem_to_truncate - 1 ))
            (( _num_of_chars_too_long = ${#length} + $num_of_elems + ${#_short_path} + 1 - ${1:-$PROMPT_TRUNCATE_AT} ))
        done
    fi
    local part
    for part in "${parts[@]:1}"; do
        _short_path+=/"$part"
    done

}

function control_git_sideeffects_preexec() {
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
        typeset -g exec_time=" %F{5}${human}"
    }
}

write_git_status_after_fetch() {
    _repo_up_to_date[$VCS_STATUS_WORKDIR]=true
    _git_fetch_pwds[${VCS_STATUS_WORKDIR}]=0
    # $VCS_STATUS_WORKDIR refers to the git dir of the time the call
    # chain was started and might differ from the current git dir
    if [[ "$VCS_STATUS_WORKDIR" == $(git rev-parse --show-toplevel 2> /dev/null)  ]]; then
        write_git_status
    else
        unset VCS_STATUS_WORKDIR
        return 0
    fi
}

write_git_status() {
    emulate -L zsh

    if [[ $_repo_up_to_date[$VCS_STATUS_WORKDIR] == true ]]; then
        local      branch='%F{2}'   # green foreground
    else
        local      branch='%F{6}'   # cyan foreground
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

    if [[ -z $GITSTATUS ]] || zle is_buffer_empty; then
        export GITSTATUS="$p"
        prompt_split_lines
        zle reset-prompt
        return 0
    fi

    # 3 is the prompt char itself plus two spaces
    (( right_distance= ${#${(S%%)${(e)PROMPT}//$~__zero/}} - ${#${(S%%)${(e)GITSTATUS}//$~__zero/}} - 3 ))
    # the unicode snake has a length of two
    [[ ${prompt_virtual_env} ]] && right_distance+=1

    if [[ "${PROMPT_WS_SEP}" == ' ' ]]; then
        # gitstatus might bleed into prompt; in that case, we print the old with a different color
        if (( ${#p} != ${#GITSTATUS} )); then
            print -Pn -- '\e7\r\e[${right_distance}C%B%F{250}${GITSTATUS[8,${#GITSTATUS}]}\e8'
        else
            print -Pn -- '\e7\r\e[${right_distance}C${p}\e8'
        fi
    else
        print -Pn -- '\e7\e[F\e[${right_distance}C\e[0K${p}\e8'
    fi

    export GITSTATUS="$p"
}

is_buffer_empty() { return $#BUFFER }
zle -N is_buffer_empty

update_git_status() {
    [[ $VCS_STATUS_RESULT == 'ok-async' ]] || return 0
    [[ $(($EPOCHSECONDS - ${_last_checks[$VCS_STATUS_WORKDIR]:-0})) -gt ${_git_fetch_result_valid_for} ]] && \
    _repo_up_to_date[$VCS_STATUS_WORKDIR]=false local out_of_date=1
    write_git_status
    (( ${+PROMPT_GIT_PROHIBIT_REMOTE} )) && return 0
    [[ $out_of_date ]] || return 0
    _last_checks[$VCS_STATUS_WORKDIR]="$EPOCHSECONDS"
    { env GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o ConnectTimeout=$_git_connect_timeout -o BatchMode=yes" GIT_TERMINAL_PROMPT=0 /usr/bin/git -c gc.auto=0 -C "${VCS_STATUS_WORKDIR}" fetch --recurse-submodules=no > /dev/null 2>&1 &&\
    gitstatus_query -t -0 -c write_git_status_after_fetch "MY" } &!
    _git_fetch_pwds[${VCS_STATUS_WORKDIR}]="$!"
}

preprompt() {
    [[ -w "$PWD" ]] || PROMPT_READ_ONLY_DIR=" %F{18}${PROMPT_READ_ONLY_ICON}%f"
    [[ "$PWD" != "$HOME" ]] && gitstatus_query -t -0 -c update_git_status 'MY' 2> /dev/null
    [[ $NVM_BIN ]] && prompt_nvm=" %F{3}⬢ ${${NVM_BIN##*node/v}//\/bin/}"
    [[ $VIRTUAL_ENV ]] && prompt_virtual_env=" 🐍%F{2}${VIRTUAL_ENV##/*/}"
    PROMPT_EOL_MARK="$prompt_eol"

    preprompt() {
        check_cmd_exec_time
        unset cmd_exec_timestamp prompt_nvm prompt_virtual_env
        gitstatus_query -t -0 -c update_git_status 'MY'
        [[ $NVM_BIN ]] && prompt_nvm=" %F{3}⬢ ${${NVM_BIN##*node/v}//\/bin/}"
        [[ $VIRTUAL_ENV ]] && prompt_virtual_env=" 🐍%F{2}${VIRTUAL_ENV##/*/}"
        prompt_split_lines
    }
}

function ssh() {
    if [[ "${#@}" -eq 1 ]] && [[ ! $1 =~ [0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$ ]]; then
        /usr/bin/ssh "$1" -t "if type zsh > /dev/null 2>&1; then exec env PROMPT_SSH_NAME=$1 EXTRA_SSH_ENV=${(q)EXTRA_SSH_ENV} zsh -l; else exec \$SHELL -l; fi"
    else
        /usr/bin/ssh "$@"
    fi
}

# On limited space we use a two line prompt, else one line
# returns 0 if prompt should change, 2 if value of PROMPT_WS_SEP is unchanged
typeset -g __zero='%([BSUbfksu]|([FK]|){*})'
prompt_split_lines() {
    if (( ${#${(S%%)${(e)PROMPT}//$~__zero/}} > COLUMNS / 3 )); then
        [[ -n $PROMPT_WS_SEP ]] && local ret=2
        PROMPT_WS_SEP=$'\n'
    else
        [[ -z $PROMPT_WS_SEP ]] && local ret=2
        unset PROMPT_WS_SEP
    fi
    return ${ret:-0}
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

    PROMPT_NO_SET_TITLE="${PROMPT_NO_SET_TITLE:-cd,clear,ls,stat,rmdir,mkdir,which,where,echo,print,true,false,_zlua,time,_file_opener}"
    PROMPT_TRUNCATE_AT="${PROMPT_TRUNCATE_AT:-40}"

    # set fancy icons
    if (( ! ${+NO_PROMPT_FANCY_ICONS} )) && [[ $TERM != 'linux' ]]; then
        PROMPT_READ_ONLY_ICON="${PROMPT_READ_ONLY_ICON:-}"
        PROMPT_ERR_ICON="${PROMPT_ERR_ICON:-🞮}"
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
    (( ${+functions[_raw_to_zsh_color]} )) && PROMPT_DIR_COLOR=$(_raw_to_zsh_color $_di_color_raw) ||\
    PROMPT_DIR_COLOR=${PROMPT_DIR_COLOR:-'%F{4}'}
    PROMPT_PATH_SEP_COLOR=${PROMPT_PATH_SEP_COLOR:-'%F{7}'}
    PROMPT_PWD=${${PWD/#$HOME/${PROMPT_DIR_COLOR}\~}//\//%{$reset_color%}${PROMPT_PATH_SEP_COLOR}\/${PROMPT_DIR_COLOR}}%b%f

    autoload -Uz add-zsh-hook

    if [[ -z $PROHIBIT_TERM_TITLE ]]; then
        add-zsh-hook preexec set_termtitle_preexec
        add-zsh-hook precmd set_termtitle_precmd
        add-zsh-hook chpwd set_termtitle_pwd
        set_termtitle_pwd
    fi

    add-zsh-hook chpwd unset_short_path_old
    add-zsh-hook preexec control_git_sideeffects_preexec
    add-zsh-hook precmd preprompt

    # Enable/disable the right prompt options.
    setopt no_prompt_bang prompt_percent prompt_subst

    # Start gitstatusd instance with name "MY". The same name is passed to
    # gitstatus_query in gitstatus_update_changes_only. The flags with -1 as values
    # enable staged, unstaged, conflicted and untracked counters.
    gitstatus_stop 'MY' && gitstatus_start -s -1 -u -1 -c -1 -d -1 'MY'

    PROMPT=
    if [[ $SSH_CONNECTION ]]; then
        if [[ -z "$PROMPT_SSH_NAME" ]]; then
            PROMPT_SSH_NAME="${HOST}"
        fi
        PROMPT+="%B[%b$PROMPT_SSH_NAME%B]%b "
        if (( $#PROMPT_SSH_NAME > 15 )); then
            typeset -gx _ssh="[${PROMPT_SSH_NAME:0:7}…${PROMPT_SSH_NAME: -7}] "
        else
            typeset -gx _ssh="[${PROMPT_SSH_NAME}] "
        fi
    fi
    PROMPT+='$PROMPT_PWD'
    PROMPT+='$PROMPT_READ_ONLY_DIR'
    PROMPT+='$exec_time'
    PROMPT+='$prompt_virtual_env'
    PROMPT+='$prompt_nvm'
    PROMPT+='${GITSTATUS}'
    PROMPT+='${PROMPT_WS_SEP:- }'
    PROMPT+='%(?.%F{magenta}${PROMPT_SUCCESS_ICON}%f.%F{red}${PROMPT_ERR_ICON}%f) '
    prompt_split_lines
}
