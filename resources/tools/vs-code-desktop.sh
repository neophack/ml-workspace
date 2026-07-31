#!/bin/sh

# Stops script execution if a command has an error
set -e

INSTALL_ONLY=0
# Loop through arguments and process them: https://pretzelhands.com/posts/command-line-flags
for arg in "$@"; do
    case $arg in
        -i|--install) INSTALL_ONLY=1 ; shift ;;
        *) break ;;
    esac
done

if [ ! -f "/usr/share/code/code" ]; then
    echo "Installing VS Code. Please wait..."
    # Install via the official Microsoft apt repository (stable, dependencies
    # resolved automatically, survives redirects better than a one-shot deb download).
    apt-get update
    apt-get install -y --no-install-recommends wget gpg
    install -m 0755 -d /etc/apt/keyrings
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
    chmod go+r /etc/apt/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list
    apt-get update
    # Retry the install a few times: the code deb is large (~230MB) and the
    # connection can be flaky (proxies / emulated builds).
    apt-get install -y --no-install-recommends \
        -o Acquire::Retries=10 \
        -o Acquire::https::Timeout=60 \
        code
    # Remove the apt source so it does not linger (keep the installed binary).
    rm -f /etc/apt/sources.list.d/vscode.list
else
    echo "VS Code is already installed"
fi

# Run
if [ $INSTALL_ONLY = 0 ] ; then
    echo "Starting VS Code"
    /usr/share/code/code --no-sandbox --unity-launch $WORKSPACE_HOME
    sleep 10
fi
