
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

if [[ $SSH_TTY ]]; then
    function xterm_title_precmd () {
        vcs_info
        print -Pn -- '\e]2;%m: %(8~|…/%6~|%~)\a'
    }

    function xterm_title_preexec () {
        print -Pn -- "\e]2%m: "${(q)1}"\a"
    }
    PROMPT=$'${vcs_info_msg_0_}%b%(2j.%B%F{magenta}[%j]%f%b .)%B%m%b %(?.%F{cyan}.%F{red})%{\e[3m%}%(5~|…/%3~|%~)%{\e[0m%}%f '
else
    function xterm_title_precmd () {
        vcs_info
        print -Pn -- '\e]2;%(8~|…/%6~|%~)\a'
    }

    function xterm_title_preexec () {
        print -Pn -- "\e]2;%(5~|…/%3~|%~) – "${(q)1}"\a"
    }
    PROMPT=$'${vcs_info_msg_0_}%b%(?.%F{cyan}.%F{red})%{\e[3m%}%(5~|…/%3~|%~)%{\e[0m%}%f '
fi
