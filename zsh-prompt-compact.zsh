function set_termtitle_preexec() {
    first_arg=${2%% *}
    if command -v ${first_arg} > /dev/null 2>&1 && [[ ! ${first_arg} =~ ^(_file_opener|_zlua|cd|clear|exa|ls|stat)$ ]]; then
        print -Pn -- "\e]2;$m%(5~|…/%3~|%~) – "${(q)2}"\a"
    fi
}

function set_termtitle_precmd() {
    print -Pn -- '\e]2;$m %(8~|…/%6~|%~)\a'
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

# Stores (into exec_time) the execution
# time of the last command if set threshold was exceeded.
check_cmd_exec_time() {
    integer elapsed
    (( elapsed = EPOCHSECONDS - ${cmd_exec_timestamp:-$EPOCHSECONDS} ))
    typeset -g exec_time=
    (( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
        human_time_to_var $elapsed "exec_time"
    }
}

write_git_status_after_fetch() {
    _repo_up_to_date[$VCS_STATUS_WORKDIR]=true
    _git_fetch_pwds[${VCS_STATUS_WORKDIR}]=0
    [[ "$VCS_STATUS_WORKDIR" == $PWD  ]] || return 0
    write_git_status
}

write_git_status() {
    emulate -L zsh

    if [[ $_repo_up_to_date[$VCS_STATUS_WORKDIR] == true ]]; then
        local      branch='%2F'   # green foreground
    else
        local      branch='%6F'   # cyan foreground
    fi

    local      clean='%6F'   # cyan foreground
    local   modified='%3F'  # yellow foreground
    local  untracked='%12F'   # blue foreground
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

    # ⇣42 if behind the remote.
    (( VCS_STATUS_COMMITS_BEHIND )) && p+=" ${clean}⇣${VCS_STATUS_COMMITS_BEHIND}"
    # ⇡42 if ahead of the remote; no leading space if also behind the remote: ⇣42⇡42.
    (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && p+=" "
    (( VCS_STATUS_COMMITS_AHEAD  )) && p+="${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"
    # ⇠42 if behind the push remote.
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" ${clean}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" "
    # ⇢42 if ahead of the push remote; no leading space if also behind: ⇠42⇢42.
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && p+="${clean}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    # *42 if have stashes.
    (( VCS_STATUS_STASHES        )) && p+=" ${clean}*${VCS_STATUS_STASHES}"
    # 'merge' if the repo is in an unusual state.
    [[ -n $VCS_STATUS_ACTION     ]] && p+=" ${conflicted}${VCS_STATUS_ACTION}"
    # ~42 if have merge conflicts.
    (( VCS_STATUS_NUM_CONFLICTED )) && p+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    # +42 if have staged changes.
    (( VCS_STATUS_NUM_STAGED     )) && p+=" ${modified}+${VCS_STATUS_NUM_STAGED}"
    # !42 if have unstaged changes.
    (( VCS_STATUS_NUM_UNSTAGED   )) && p+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    # ?42 if have untracked files. It's really a question mark, your font isn't broken.
    (( VCS_STATUS_NUM_UNTRACKED  )) && p+=" ${untracked}?${VCS_STATUS_NUM_UNTRACKED}"

    print -Pn -- '\x1B[s\x1B[F\x1B[$(( ${#_is_read_only_dir} + ${#exec_time} + ${#${PWD}/${HOME}/~} ))C\x1B[0K ${p}%f\x1B[u'
    GITSTATUS=$p
}

typeset -gA _last_checks
typeset -gA _git_fetch_pwds
typeset -gA _repo_up_to_date

GIT_FETCH_RESULT_VALID_FOR=${GIT_FETCH_RESULT_VALID_FOR:-60}
(( $GIT_FETCH_RESULT_VALID_FOR < 2 )) && GIT_FETCH_RESULT_VALID_FOR=2
GIT_CONNECT_TIMEOUT=$((GIT_FETCH_RESULT_VALID_FOR -1))
READ_ONLY_ICON="${READ_ONLY_ICON:-RO} "

update_git_status() {
    [[ $VCS_STATUS_RESULT == 'ok-async' ]] || return 0
    [[ $(($EPOCHSECONDS - ${_last_checks[$VCS_STATUS_WORKDIR]:-0})) -gt ${GIT_FETCH_RESULT_VALID_FOR} ]] && _repo_up_to_date[$VCS_STATUS_WORKDIR]=false local out_of_date=1
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

preprompt() {
    check_cmd_exec_time
    unset cmd_exec_timestamp _is_read_only_dir GITSTATUS
    [ ! -w "$PWD" ] && _is_read_only_dir="${READ_ONLY_ICON}"
    gitstatus_query -t -0 -c update_git_status 'MY'
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

PROMPT='${_is_read_only_dir}'
PROMPT+=$'%4F\x1b[3m%~\e[0m'
PROMPT+='%5F${exec_time} $GITSTATUS%f'
PROMPT+=$'\n'
[ $SSH_TTY ] && PROMPT+="%B[%b%m%B]%b " m="%m: "
PROMPT+=$'%(?.$.%F{red}🞮%f) '
