    activate() {
        typeset -aU venvs
        if [[ "${#@}" -eq 1 ]]; then
            venvs+="${1%/*}"
        else
            for file in ./**/pyvenv.cfg; do
                if [[ -f "$file" ]]; then
                    venvs+="${file%/*}"
                fi
            done
        fi
        if [[ "${#venvs}" -eq 1 ]]; then
            source "${venvs[@]:0}/bin/activate"
            _OLD_VIRTUAL_PS1="$PROMPT"
            export VIRTUAL_ENV_PROMPT="(${VIRTUAL_ENV##/*/}) "
            export PROMPT="%2F%B$VIRTUAL_ENV_PROMPT%b$PROMPT"
        elif [[ "${#venvs}" -gt 1 ]]; then
            print "More than one venv: \x1b[3m${venvs[@]##*/}\e[0m"
            print "Use \`activate <venv>\` to activate it"
            return 1
        elif [[ "${#venvs}" -eq 0 ]]; then
            print "No venv: \x1b[3m${venvs[@]##*/}\e[0m"
            return 1
        fi
    }

# disable python's built in manipulation of the prompt in favor of our own
export VIRTUAL_ENV_DISABLE_PROMPT=1

function set_termtitle_preexec() {
    first_arg=${2%% *}
    if command -v ${first_arg} > /dev/null 2>&1 && [[ ! ${first_arg} =~ ^(_file_opener|_zlua|cd|clear|exa|ls|stat|rmdir|mkdir)$ ]]; then
        comm=${(q)1}
        # (( $#comm > 30 )) && comm[13,-13]="…"  # truncate long command names
        # print -Pn -- "\e]2;$m$_short_path – "$comm"\a"
    fi
}

function set_termtitle_precmd() {
    # we also reset the cursor to bar. Useful if coming from Neovim

    if [[ $? != 0 ]]; then
        set_global_short_path
        print -Pn -- '\e]2;$m$_short_path ERR\a\e[6 q'
    else
        set_global_short_path
        print -Pn -- '\e]2;$m$_short_path\a\e[6 q'
    fi
}

function set_global_short_path() {
    typeset -g _short_path
    typeset -a parts

    if [[ "$PWD" == $HOME* ]]; then
        _short_path="~"
        pd="${PWD/${HOME}/}"
    else
        _short_path=""
        pd="$PWD"
    fi

    length=${pd//\//}
    parts=("${(@s[/])pd}")
    num_elems=$(( ${#parts} - 1 ))
    # we truncate the path when it is longer than 40 chars but always keep at least two dirs
    while (( ${#length} + ${#parts} > 40 )) && (( $num_elems > 2 )); do
        parts[$num_elems]="…"
        printf -v length '%s' "${parts[@]}"
        num_elems=$(( $num_elems - 1 ))
    done

    for part in "${parts[@]:1}"; do
        _short_path+=/"$part"
    done
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
    [[ "$VCS_STATUS_WORKDIR" == $(git rev-parse --show-toplevel 2> /dev/null)  ]] || return 0
    write_git_status
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
    p+="%B${branch}${where//\%/%%}"             # escape %

    (( VCS_STATUS_COMMITS_BEHIND )) && p+=" ${clean}⇣${VCS_STATUS_COMMITS_BEHIND}"
    (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && p+=" "
    (( VCS_STATUS_COMMITS_AHEAD  )) && p+="${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" ${clean}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" "
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && p+="${clean}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    (( VCS_STATUS_STASHES        )) && p+=" ${clean}*${VCS_STATUS_STASHES}"
    [[ -n $VCS_STATUS_ACTION     ]] && p+=" ${conflicted}${VCS_STATUS_ACTION}"
    (( VCS_STATUS_NUM_CONFLICTED )) && p+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    (( VCS_STATUS_NUM_STAGED     )) && p+=" ${added}+${VCS_STATUS_NUM_STAGED}"
    (( VCS_STATUS_NUM_UNSTAGED   )) && p+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    (( VCS_STATUS_NUM_UNTRACKED  )) && p+=" ${untracked}?${VCS_STATUS_NUM_UNTRACKED}"

    print -Pn -- '\x1B[s\x1B[F\x1B[$(( ${VIRTUAL_ENV:+${#VIRTUAL_ENV_PROMPT}} + ${#RO_DIR} + ${#EXEC_TIME} + ${#${PWD}/${HOME}/~} ))C\x1B[0K ${p}%b\x1B[u'
    GITSTATUS=" $p%b"
}

typeset -gA _last_checks
typeset -gA _git_fetch_pwds
typeset -gA _repo_up_to_date

GIT_FETCH_RESULT_VALID_FOR=${GIT_FETCH_RESULT_VALID_FOR:-60}
(( $GIT_FETCH_RESULT_VALID_FOR < 2 )) && GIT_FETCH_RESULT_VALID_FOR=2
GIT_CONNECT_TIMEOUT=$((GIT_FETCH_RESULT_VALID_FOR -1))
READ_ONLY_ICON="${READ_ONLY_ICON:-RO}"

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
preprompt() {
    check_cmd_exec_time
    unset cmd_exec_timestamp RO_DIR GITSTATUS
    [ ! -w "$PWD" ] && RO_DIR=" %18F${READ_ONLY_ICON}"
    gitstatus_query -t -0 -c update_git_status 'MY'
    PROMPT_PWD=%F{$DIR_COLOR}${${PWD/${HOME}/\~}//\//%F{$DIR_SEPARATOR_COLOR}\/%F{$DIR_COLOR}}
}

# Start gitstatusd instance with name "MY". The same name is passed to
# gitstatus_query in gitstatus_update_changes_only. The flags with -1 as values
# enable staged, unstaged, conflicted and untracked counters.
gitstatus_stop 'MY' && gitstatus_start -s -1 -u -1 -c -1 -d -1 'MY'

autoload -Uz add-zsh-hook
add-zsh-hook preexec control_git_sideeffects_preexec
[[ -z $PROHIBIT_TERM_TITLE ]] && add-zsh-hook preexec set_termtitle_preexec
[[ -z $PROHIBIT_TERM_TITLE ]] && add-zsh-hook precmd set_termtitle_precmd
add-zsh-hook precmd preprompt

# Enable/disable the right prompt options.
setopt no_prompt_bang prompt_percent prompt_subst

PROMPT=$'${PROMPT_PWD}\e[0m'
PROMPT+='${RO_DIR}%5F${EXEC_TIME}${GITSTATUS}%f'
PROMPT+=$'\n'
[ $SSH_TTY ] && PROMPT+="%B[%b%m%B]%b " m="%m: "
PROMPT+=$'%(?.$.%F{red}🞮%f) '
