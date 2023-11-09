__activater_recursive() {
    [[ "$1" != '/' ]] && [[ "$1" != "$HOME" ]] || return

    if [[ $__venv_name ]]; then
        [[ -f "${1}/${__venv_name}/pyvenv.cfg" ]] && venvs+="${1}/${__venv_name}"
    else
        local file ___dir
        for ___dir in ${1}/*(D); do
            for file in ${___dir}/*; do
                [[ "${file##*/}" == "pyvenv.cfg" ]] && venvs+="${file%/*}"
            done
        done
    fi

    (( ${#venvs} == 0 )) && __activater_recursive "${1%/*}"
}

activate() {
    [[ ! -z "$1" ]] && local __venv_name="$1"

    typeset -aU venvs
    __activater_recursive "$PWD"

    case ${#venvs} in
        1) [[ $VIRTUAL_ENV ]] && [[ "$VIRTUAL_ENV" == "${venvs[@]:0}" ]] && print "Already using $(_colorizer_abs_path ${venvs})" && return 1
            print "Found venv in $(_colorizer ${venvs})"
           [[ $VIRTUAL_ENV ]] && deactivate
           type pyenv > /dev/null 2>&1 && typeset -g PROMPT_PYENV_PYTHON_VERSION="$(pyenv version-name)"
           source "${venvs[@]:0}/bin/activate" ;;
        0) print "No venv found" ;;
        *) print -l "Found more than one venv. Use \`activate <venv>\` to activate it." "\e[1m\e[32m${venvs[@]##*/}\e[0m" ;;
    esac
    return $(( ${#venvs} -1 ))
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
                export _short_path="$(truncate_dir_path $(( $PROMPT_TRUNCATE_AT - ${#comm} - 3 )))"
            fi
            print -n -- "\e]2;$_short_path | ${(q)comm}\a"
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
            print -n -- '\e]2;'${(q)comm}'\a'
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
            export _short_path="$(truncate_dir_path $(($PROMPT_TRUNCATE_AT - ${#PROMPT_ERR_ICON} - 1)))"
        else
            export _short_path="$(truncate_dir_path)"
        fi
    fi

    if [[ $__res != 0 ]]; then
        print -n -- "\e]2;${_short_path} ${PROMPT_ERR_ICON}\a"
    else
        print -n -- "\e]2;${_short_path}\a"
    fi

    __oldres=$__res
}

typeset -g __zero='%([BSUbfksu]|([FK]|){*})'
function truncate_prompt() {
    unset PROMPT_WS_SEP
    local __prompt_non_truncated=
    __prompt_non_truncated+='${SSH_CONNECTION:+%B[%b$PROMPT_SSH_NAME%B]%b }'
    __prompt_non_truncated+='$PROMPT_READ_ONLY_DIR'
    __prompt_non_truncated+='$exec_time'
    __prompt_non_truncated+='$current_time'

    if [[ -n $prompt_virtual_env ]]; then
        __prompt_non_truncated+='$prompt_virtual_env'
        __prompt_non_truncated+=' '
    fi

    __prompt_non_truncated+='$prompt_nvm'
    __prompt_non_truncated+='${GITSTATUS}'
    typeset -i __prompt_non_truncated_len=${#${(S%%)${(e)__prompt_non_truncated}//$~__zero/}}
    typeset -i surplus=$(( COLUMNS - $__prompt_non_truncated_len ))

    if [[ ! -z $__git_dir ]]; then
        typeset -a full_path=(${(@s[/])PWD})
        typeset -a git_dir=(${(@s[/])__git_dir})
        full_path[${#git_dir}]="%B${full_path[${#git_dir}]}%b"
        local modified_pwd="/${full_path[*]// //}"
        local truncated_dirs="$(truncate_dir_path $surplus $modified_pwd)"
    else
        local truncated_dirs="$(truncate_dir_path $surplus)"
    fi
    export PROMPT_PWD=${${truncated_dirs/\~/${PROMPT_DIR_COLOR:-}~}//\//%{$reset_color%}${PROMPT_PATH_SEP_COLOR}\/${PROMPT_DIR_COLOR:-}}%b%f

    if (( ${#${(S%%)${(e)PROMPT}//$~__zero/}} > COLUMNS / 3 )); then
        export PROMPT_WS_SEP=$'\n'
    fi
}

function unset_short_path_old() {
    typeset -gx _short_path=$(truncate_dir_path)
    unset _short_path_old

    if [[ $PWD == ${VCS_STATUS_WORKDIR}* ]]; then
        export __git_dir="${VCS_STATUS_WORKDIR}"
    else
        unset GITSTATUS
        unset __git_dir
    fi
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
        __short_path+=/"$part"
    done

    print -n $__short_path
}

function control_git_sideeffects_preexec() {
    (( ${+__PROMPT_NEWLINE} )) && typeset -g __prompt_newline
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
    fi
}

write_git_status() {
    emulate -L zsh

    export __git_dir="${VCS_STATUS_WORKDIR}"

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
    print -Pn "\e]133;A\e\\" # foot
    unset PROMPT_READ_ONLY_DIR
    [[ -w "$PWD" ]] || export PROMPT_READ_ONLY_DIR=" %F{18}${PROMPT_READ_ONLY_ICON}%f"
    check_cmd_exec_time
    unset cmd_exec_timestamp prompt_nvm prompt_virtual_env current_time
    gitstatus_query -t -0 -c update_git_status 'MY'
    [[ $NVM_BIN ]] && prompt_nvm=" %F{3}⬢ ${${NVM_BIN##*node/v}//\/bin/}"
    [[ $VIRTUAL_ENV ]] && prompt_virtual_env=" 🐍%F{2}${PROMPT_PYENV_PYTHON_VERSION:+%B$PROMPT_PYENV_PYTHON_VERSION%b }${VIRTUAL_ENV##/*/}"
    (( ${+__prompt_newline} )) && print && unset __prompt_newline
    truncate_prompt
}

_zsh_autosuggest_helper() { gitstatus_query -t -0 -c update_git_status 'MY' }

accept-line() {
    local current_time
    [[ -n $exec_time ]] && current_time="%f|" || current_time=" "
    current_time+="%F{3}%D{%T}%f"
    truncate_prompt
    zle reset-prompt
    zle .accept-line
}
zle -N accept-line


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

    PROMPT_NO_SET_TITLE="${PROMPT_NO_SET_TITLE:-cd,clear,ls,stat,rmdir,mkdir,which,where,echo,print,true,false,_zlua,time,file_opener,exa}"
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
    PROMPT+='${SSH_CONNECTION:+%B[%b${PROMPT_SSH_NAME:-$HOST}%B]%b }'
    PROMPT+='$PROMPT_PWD'
    PROMPT+='$PROMPT_READ_ONLY_DIR'
    PROMPT+='$exec_time'
    PROMPT+='$current_time'
    PROMPT+='$prompt_virtual_env'
    PROMPT+='$prompt_nvm'
    PROMPT+='${GITSTATUS}'
    PROMPT+='${PROMPT_WS_SEP- }'
    PROMPT+='%(?.%F{magenta}${PROMPT_SUCCESS_ICON}%f.%F{red}${PROMPT_ERR_ICON}%f) '
    truncate_prompt
}
