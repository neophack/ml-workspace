# ~/.bashrc: executed by interactive *non-login* bash shells
# (e.g. xfce4-terminal, `docker exec -it ... bash`).
#
# For login shells (SSH, `bash -l`) bash reads ~/.profile instead, which in
# turn sources this file -- so everything below covers both entry points.

# If not running interactively, do nothing. Keeps non-interactive contexts
# (scripts, `docker exec ...` without -t) cheap and free of side effects.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Terminal / color capability ---------------------------------------------
# Some launchers (noVNC's bare xterm, non-tty exec) start with TERM=dumb or
# empty, which makes ls/grep/PS1 disable colors. Fall back to a capable TERM
# only when the inherited value can't render color.
case "$TERM" in
    xterm|xterm-*|*-256color|screen|screen-*|tmux|tmux*|rxvt*|alacritty*) ;;
    *) TERM=xterm-256color ;;
esac

# Don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend checkwinsize globstar

# --- Prompt ------------------------------------------------------------------
# Colored prompt: green user@host, blue cwd, red $ when root.
if [ "$(id -u)" -eq 0 ]; then
    PS1='\[\e[1;31m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]# '
else
    PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
fi

# --- Color support for ls / grep ---------------------------------------------
if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
fi

# --- Aliases -----------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Colorize a few more common tools when they support it.
command -v dir    >/dev/null 2>&1 && alias dir='dir --color=auto'
command -v vdir   >/dev/null 2>&1 && alias vdir='vdir --color=auto'
command -v diff   >/dev/null 2>&1 && alias diff='diff --color=auto'
command -v ip     >/dev/null 2>&1 && alias ip='ip --color=auto'

# --- Bash completion ---------------------------------------------------------
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# --- Default working directory ----------------------------------------------
# Mirror the behaviour previously hard-coded at the end of Dockerfile's
# .bashrc append (line ~253): always land in /workspace for new shells.
if [ -d /workspace ]; then
    cd /workspace 2>/dev/null || true
fi
