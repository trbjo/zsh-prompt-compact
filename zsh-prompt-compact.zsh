activate() {

    if [[ $VIRTUAL_ENV ]]; then
        print "Deactivate your current environment first"
        return 1
    fi

    typeset -aU venvs

    if [[ "${#@}" -eq 1 ]]; then
        venvs+="${1%/*}"
    else
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
        print "More than one venv: \x1b[3m${venvs[@]##*/}\e[0m"
        print "Use \`activate <venv>\` to activate it"
        return 1
    elif [[ "${#venvs}" -eq 0 ]]; then
        print -n "No venv found"
        if [[ $VCS_STATUS_RESULT == 'ok-async' ]] && [[ "$PWD" != $VCS_STATUS_WORKDIR ]]; then
            print -n ", trying git root dir"
            cd $VCS_STATUS_WORKDIR
            activate
            cd $OLDPWD
            print
            return 0
        else
            print
            return 1
        fi

    fi
}

# disable python's built in manipulation of the prompt in favor of our own
export VIRTUAL_ENV_DISABLE_PROMPT=1

function set_termtitle_preexec() {
    first_arg=${2%% *}
    if command -v ${first_arg} > /dev/null 2>&1 && [[ ! ${first_arg} =~ ^(${PROMPT_NO_HIJACK_TITLE//,/|})$ ]]; then
        comm=${(q)1}

        if (( $#comm > ${PROMPT_TRUNCATE_AT} )); then
            local val
            val=$(( PROMPT_TRUNCATE_AT / 2 - 4 ))
            comm[$val,-$val]="…"
        fi

        if (( ${#_short_path} + ${#comm} >= $PROMPT_TRUNCATE_AT )); then
            _short_path_old=$_short_path
            set_termtitle_pwd (( $PROMPT_TRUNCATE_AT - $#comm - ${#m} - 3 ))
        fi

        if [[ "$PWD" != "$HOME" ]]; then
            print -Pn -- "\e]2;$m$_short_path | $comm\a"
        else
            print -Pn -- "\e]2;$m$comm\a"
        fi
    fi
}

function set_termtitle_precmd() {
    local res=$?

    if [[ $_short_path_old ]]; then
        _short_path=$_short_path_old
        unset _short_path_old
    fi

    if [[ $res != 0 ]]; then
        print -Pn -- "\e]2;$m${_short_path} ${PROMPT_ERR_ICON}\a"
    else
        print -Pn -- "\e]2;$m${_short_path}\a"
    fi
}

function unset_short_path_old() {
    unset _short_path_old
}

function set_termtitle_pwd() {
    typeset -g _short_path
    typeset -a parts

    if [[ "$PWD" == $HOME* ]]; then
        _short_path="~"
        pd="${PWD/#$HOME/~}"
    else
        _short_path=""
        pd="$PWD"
    fi

    length=${pd//\//}
    parts=("${(@s[/])pd}")
    num_elems=$(( ${#parts} - 1 ))
    # we truncate the path when it is longer than $PROMPT_TRUNCATE_AT chars but always keep at least one dir
    while (( ${#length} + ${#parts} > ${1:-$PROMPT_TRUNCATE_AT} )) && (( $num_elems > 2 )); do

        (( cur_part = ${#parts[$num_elems]} ))

        # the + 2 is because it does not make sense to change the path representation
        # if only one char is to be changed. We therefore make sure that when we do it,
        # there is at least three parts to be replaced.
        if (( ${#length} + ${#parts} - ${1:-$PROMPT_TRUNCATE_AT} + 2 > $cur_part )); then
            parts[$num_elems]="…"
        else
            (( too_long = ${#length} + ${#parts} - ${1:-$PROMPT_TRUNCATE_AT} ))
            (( we_need_this_left = $cur_part / 2 - $too_long /2 -1 ))
            (( we_need_this_right = $cur_part - $we_need_this_left ))
            parts[$num_elems]="${parts[$num_elems]:0:$we_need_this_left}…${parts[$num_elems]:$we_need_this_right}"
        fi

        printf -v length '%s' "${parts[@]}"
        num_elems=$(( $num_elems - 1 ))
    done

    for part in "${parts[@]:1}"; do
        _short_path+=/"$part"
    done

    if (( ${1:-$PROMPT_TRUNCATE_AT} < ${#_short_path} )); then
        local half val
        half=$(( ${1:-$PROMPT_TRUNCATE_AT} / 2 ))
        val=$(( half > 4 ? half : 4 ))
        _short_path[$val,-$val]="…"
    fi

}

function control_git_sideeffects_preexec() {
    typeset -g cmd_exec_timestamp=$EPOCHSECONDS
    if [[ ${_git_fetch_pwds[${VCS_STATUS_WORKDIR}]:-0} != 0 ]]\
    && [[ $2 =~ git\ (.*\ )?(pull|push|fetch)(\ .*)?$ ]]
    then
        kill -SIGTERM -- -$_git_fetch_pwds[${VCS_STATUS_WORKDIR}] 2> /dev/null
        _git_fetch_pwds[${VCS_STATUS_WORKDIR}]=0
    fi
}

# taken from Sindre Sorhus
# https://github.com/sindresorhus/pretty-time-zsh
human_time_to_var() {
    local human total_seconds=$1 var=$2
    local days=$(( total_seconds / 60 / 60 / 24 ))
    local hours=$(( total_seconds / 60 / 60 % 24 ))
    local minutes=$(( total_seconds / 60 % 60 ))
    local seconds=$(( total_seconds % 60 ))
    (( days > 0 )) && human+="${days}d "
    (( hours > 0 )) && human+="${hours}h "
    (( minutes > 0 )) && human+="${minutes}m "
    human+="${seconds}s"

    # Store human readable time in a variable as specified by the caller
    typeset -g "${var}"=" ${human}"
}

# Stores (into EXEC_TIME) the execution
# time of the last command if set threshold was exceeded.
check_cmd_exec_time() {
    integer elapsed
    (( elapsed = EPOCHSECONDS - ${cmd_exec_timestamp:-$EPOCHSECONDS} ))
    typeset -g EXEC_TIME=
    (( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
        human_time_to_var $elapsed "EXEC_TIME"
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
        local      branch='%2F'   # green foreground
    else
        local      branch='%6F'   # cyan foreground
    fi

    local      clean='%4F'  # cyan foreground
    local   modified='%3F'  # yellow foreground
    local      added='%10F'  # green foreground
    local  untracked='%18F' # grey foreground
    local conflicted='%2F'  # red foreground

    local p

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
    p+="${branch}${where//\%/%%}"             # escape %

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

    GITSTATUS_PROMPT_LEN="${(m)#${${p//\%\%/x}//\%(f|<->F)}}"
    # print $GITSTATUS_PROMPT_LEN
    (( PROMPT_LENGTH=${VIRTUAL_ENV:+(( ${#PROMPT_VIRTUAL_ENV} + 1))} + ${#PROMPT_NVM} + ${#RO_DIR} + ${#EXEC_TIME} + ${#${PWD}/${HOME}/~}))
    if (( PROMPT_LENGTH + GITSTATUS_PROMPT_LEN  > COLUMNS )); then
        ((PROMPT_LENGTH= COLUMNS - GITSTATUS_PROMPT_LEN - 1))
        GITSTATUS=" %B$p%b"
        print -Pn -- '\x1B[s\x1B[F\x1B[${PROMPT_LENGTH}C\x1B[0K${GITSTATUS}%b\x1B[u'
        # PROMPT_PWD=""
    else
        GITSTATUS=" %B$p%b"
        print -Pn -- '\x1B[s\x1B[F\x1B[${PROMPT_LENGTH}C\x1B[0K${GITSTATUS}%b\x1B[u'

    fi

}

typeset -gA _last_checks
typeset -gA _git_fetch_pwds
typeset -gA _repo_up_to_date

GIT_FETCH_RESULT_VALID_FOR=${GIT_FETCH_RESULT_VALID_FOR:-60}
(( $GIT_FETCH_RESULT_VALID_FOR < 2 )) && GIT_FETCH_RESULT_VALID_FOR=2
GIT_CONNECT_TIMEOUT=$((GIT_FETCH_RESULT_VALID_FOR -1))

READ_ONLY_ICON="${READ_ONLY_ICON:-RO}"
PROMPT_ERR_ICON="${PROMPT_ERR_ICON:-X}"
PROMPT_SUCCESS_ICON="${PROMPT_SUCCESS_ICON:-$}"
PROMPT_TRUNCATE_AT="${PROMPT_TRUNCATE_AT:-40}"

update_git_status() {
    [[ $VCS_STATUS_RESULT == 'ok-async' ]] || return 0
    [[ $(($EPOCHSECONDS - ${_last_checks[$VCS_STATUS_WORKDIR]:-0})) -gt ${GIT_FETCH_RESULT_VALID_FOR} ]] && \
    _repo_up_to_date[$VCS_STATUS_WORKDIR]=false local out_of_date=1
    write_git_status
    [[ $GIT_FETCH_REMOTE == true ]] || return 0
    [[ $out_of_date ]] || return 0
    _last_checks[$VCS_STATUS_WORKDIR]="$EPOCHSECONDS"
    { env GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o ConnectTimeout=$GIT_CONNECT_TIMEOUT -o BatchMode=yes" GIT_TERMINAL_PROMPT=0 /usr/bin/git -c gc.auto=0 -C "${VCS_STATUS_WORKDIR}" fetch --recurse-submodules=no > /dev/null 2>&1 &&\
    gitstatus_query -t -0 -c write_git_status_after_fetch "MY" } &!
    _git_fetch_pwds[${VCS_STATUS_WORKDIR}]="$!"
}

update_git_status_wrapper() {
    gitstatus_query -t -0 -c update_git_status 'MY'
}

DIR_SEPARATOR_COLOR=${DIR_SEPARATOR_COLOR:-7}
DIR_COLOR=${DIR_COLOR:-6}
[[ $PROMPT_NEWLINE_SEPARATOR != 0 ]] && PROMPT_NEWLINE_SEPARATOR=1 || unset PROMPT_NEWLINE_SEPARATOR

preprompt() {
    [ ! -w "$PWD" ] && RO_DIR=" ${READ_ONLY_ICON}"
    gitstatus_query -t -0 -c update_git_status 'MY'
    PROMPT_PWD=%F{$DIR_COLOR}${${PWD/#$HOME/\~}//\//%F{$DIR_SEPARATOR_COLOR}\/%F{$DIR_COLOR}}
    [[ $NVM_BIN ]] && PROMPT_NVM=" ⬢ ${${NVM_BIN##*node/v}//\/bin/}"
    [[ $VIRTUAL_ENV ]] && PROMPT_VIRTUAL_ENV=" 🐍${VIRTUAL_ENV##/*/}"

    preprompt() {
        check_cmd_exec_time
        unset cmd_exec_timestamp RO_DIR GITSTATUS PROMPT_NVM PROMPT_VIRTUAL_ENV
        [ ! -w "$PWD" ] && RO_DIR=" ${READ_ONLY_ICON}"
        gitstatus_query -t -0 -c update_git_status 'MY'
        PROMPT_PWD=%F{$DIR_COLOR}${${PWD/#$HOME/\~}//\//%F{$DIR_SEPARATOR_COLOR}\/%F{$DIR_COLOR}}
        [[ $NVM_BIN ]] && PROMPT_NVM=" ⬢ ${${NVM_BIN##*node/v}//\/bin/}"
        [[ $VIRTUAL_ENV ]] && PROMPT_VIRTUAL_ENV=" 🐍${VIRTUAL_ENV##/*/}"
        [[ $PROMPT_NEWLINE_SEPARATOR ]] && print
    }
}

# Start gitstatusd instance with name "MY". The same name is passed to
# gitstatus_query in gitstatus_update_changes_only. The flags with -1 as values
# enable staged, unstaged, conflicted and untracked counters.
gitstatus_stop 'MY' && gitstatus_start -s -1 -u -1 -c -1 -d -1 'MY'

autoload -Uz add-zsh-hook
add-zsh-hook preexec control_git_sideeffects_preexec
add-zsh-hook precmd preprompt

if [[ -z $PROHIBIT_TERM_TITLE ]]; then
    add-zsh-hook preexec set_termtitle_preexec
    add-zsh-hook precmd set_termtitle_precmd
    add-zsh-hook chpwd set_termtitle_pwd
    add-zsh-hook chpwd unset_short_path_old
    set_termtitle_pwd
fi


# Enable/disable the right prompt options.
setopt no_prompt_bang prompt_percent prompt_subst

export PROMPT_EOL_MARK='%F{1}❮❮❮%f'

PROMPT=$'${PROMPT_PWD}\e[0m'
PROMPT+=$'${RO_DIR:+\x1b[38;5;18m$RO_DIR}${EXEC_TIME:+\x1b[35m$EXEC_TIME}'
PROMPT+=$'${VIRTUAL_ENV:+\x1b[32m${PROMPT_VIRTUAL_ENV}}'
PROMPT+=$'${NVM_BIN:+\x1b[33m${PROMPT_NVM}}'
PROMPT+='${GITSTATUS:+$GITSTATUS}%f'
PROMPT+=$'\n'
[ $SSH_TTY ] && PROMPT+="%B[%b%m%B]%b " m="%m: "
PROMPT+='%(?.%F{magenta}${PROMPT_SUCCESS_ICON}%f.%F{red}${PROMPT_ERR_ICON}%f) '
