autoload -Uz promptinit
promptinit
setopt prompt_subst

# Load vcs
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr '%F{green}'
zstyle ':vcs_info:*' unstagedstr '%F{yellow}'
zstyle ':vcs_info:*' formats '%{%F{blue}%B%}(%%b%f%u%c%b%F{blue}%B)%f '
zstyle ':vcs_info:*' actionformats '%{%F{blue}%B%}(%%b%f%u%c%b%F{blue}%B)%f '


autoload -Uz add-zsh-hook
add-zsh-hook -Uz precmd xterm_title_precmd
add-zsh-hook -Uz preexec xterm_title_preexec

[ $SSH_TTY ] && _ssh="%B%m%b " m="%m:"

function xterm_title_precmd () {
    vcs_info
    print -Pn -- '\e]2;$m %(8~|…/%6~|%~)\a'
}

function xterm_title_preexec () {
    print -Pn -- "\e]2;$m %(5~|…/%3~|%~) – "${(q)1}"\a"
}

PROMPT=$'${_ssh}${vcs_info_msg_0_}%b%(?.%F{blue}.%F{red})%{\e[3m%}%(5~|%-1~/…/%3~|%~)%{\e[0m%}%f '
