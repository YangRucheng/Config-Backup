prompt() {
    export black="\[\033[0;38;5;0m\]"
    export red="\[\033[0;38;5;1m\]"
    export orange="\[\033[0;38;5;130m\]"
    export green="\[\033[0;38;5;2m\]"
    export yellow="\[\033[0;38;5;3m\]"
    export blue="\[\033[0;38;5;4m\]"
    export bblue="\[\033[0;38;5;12m\]"
    export magenta="\[\033[0;38;5;55m\]"
    export cyan="\[\033[0;38;5;6m\]"
    export white="\[\033[0;38;5;7m\]"
    export coldblue="\[\033[0;38;5;33m\]"
    export smoothblue="\[\033[0;38;5;111m\]"
    export iceblue="\[\033[0;38;5;45m\]"
    export turqoise="\[\033[0;38;5;50m\]"
    export smoothgreen="\[\033[0;38;5;42m\]"

    PS1="$green\u@\h$white:$blue\w$white: "
}

set_bin() {
    export PATH="$PATH:/usr/local/go/bin"
    export PATH="$PATH:/usr/local/node/bin"
}

exports() {
    export all_proxy=http://127.0.0.1:520
    export http_proxy=$all_proxy
    export https_proxy=$all_proxy
}

ali() {
    alias ll='ls -l --color=auto'
}

default() {
    shopt -s histappend
    HISTSIZE=100000
    HISTFILESIZE=2000000
    if [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
}

ali;
prompt;
# exports;
default;
# set_bin;

if [[ $- == *i* ]]; then
    echo -ne "Hi, Sakana! Weclome, 今天是 "; date '+%A, %B %-d %Y'
fi

