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

if ! hash sqlectron 2>/dev/null; then
    cd $RESOURCES_PATH
    echo "Installing Sqlectron Term. Please wait..."
    npm install -g sqlectron-term
    echo "Installing Sqlectron GUI"
    wget https://github.com/sqlectron/sqlectron-gui/releases/download/v1.37.1/sqlectron_1.37.1_amd64.deb -O ./sqlectron.deb
    apt-get update
    apt-get install -y ./sqlectron.deb
    rm ./sqlectron.deb
fi

# Run
if [ $INSTALL_ONLY = 0 ] ; then
    echo "Starting Sqlectron..."
    echo "Sqlectron is a GUI application. Make sure to run this script only within the VNC Desktop."
    sqlectron --no-sandbox
    sleep 10
fi
