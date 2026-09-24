# ~/.bashrc — colored bash prompt + convenience aliases for the ML workspace.

# If not running interactively, don't do anything past here.
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar 2>/dev/null

# Color support for ls, grep, etc.
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
alias ip='ip --color=auto'

# Quick navigation / misc
alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias -- -='cd -'
alias cls='clear'
alias h='history'
alias ports='sudo netstat -tulpn 2>/dev/null || sudo ss -tulpn'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -n 20'
alias gd='git diff'

# Python
alias py='python'
alias pipi='pip install'
alias pir='pip install -r requirements.txt'

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# make less more friendly for non-text input files (manpages, etc.)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# enable programmable completion features
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# User-local bin on PATH
export PATH="$HOME/.local/bin:$PATH"
export WORKSPACE_HOME="${WORKSPACE_HOME:-/workspace}"

# --- Fcitx 5 / Rime input method environment ---
# fcitx5 keeps the "fcitx" im-module name for GTK/Qt/XIM.
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"

# --- Colored prompt ---
# Green user@host, blue cwd, magenta git branch, reset. Works on dark VNC terminals.
# The git branch is resolved at prompt-display time via $(...) inside PS1.

if [ "$color_prompt" != "no" ]; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\[\033[35m\]$(__git_branch_ps1)\[\033[00m\]\$ '
else
    PS1='\u@\h:\w\$ '
fi

__git_branch_ps1() {
    local b
    b=$(git symbolic-ref --short HEAD 2>/dev/null) || b=$(git rev-parse --short HEAD 2>/dev/null)
    [ -n "$b" ] && printf '(%s)' "$b"
}

# cd to /workspace on first interactive login shell
if [ -d "$WORKSPACE_HOME" ] && [ "$PWD" = "$HOME" ] && [ -z "$ML_WS_CD_DONE" ]; then
    export ML_WS_CD_DONE=1
    cd "$WORKSPACE_HOME" 2>/dev/null || true
fi
