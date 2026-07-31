# ~/.profile: executed by the command interpreter for *login* shells.
# (SSH login, `bash -l`, su -).
#
# This is a no-op for non-bash shells. For bash we delegate to ~/.bashrc,
# which is where the prompt, aliases and color handling actually live.

# If not bash, do nothing (keeps sh/dash fast).
if [ -n "$BASH_VERSION" ]; then
    # Source .bashrc if this is an interactive bash shell.
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# Put $HOME/.local/bin and /usr/local/bin on PATH if not already.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) [ -d "/usr/local/bin" ] && PATH="/usr/local/bin:$PATH" ;;
esac
export PATH
