#!/bin/sh

# Stops script execution if a command has an error
set -e

INSTALL_ONLY=0
TOKEN=""
SERVER="api.openp2p.cn"
# Loop through arguments and process them: https://pretzelhands.com/posts/command-line-flags
for arg in "$@"; do
    case $arg in
        -i|--install) INSTALL_ONLY=1 ; shift ;;
        -t=*|--token=*) TOKEN="${arg#*=}" ; shift ;; # TODO Does not allow --token 1234
        -s=*|--server=*) SERVER="${arg#*=}"; shift ;; 
        *) break ;;
    esac
done

if [ ! -f "$RESOURCES_PATH/openp2p"  ]; then
    echo "Installing Openp2p. Please wait..."
    cd $RESOURCES_PATH
    OPENP2P_VERSION=3.6.5
    wget https://github.com/openp2p-cn/openp2p/releases/download/v$OPENP2P_VERSION/openp2p$OPENP2P_VERSION.linux-amd64.tar.gz
    tar xvpfz openp2p$OPENP2P_VERSION.linux-amd64.tar.gz
    rm ./openp2p$OPENP2P_VERSION.linux-amd64.tar.gz
    
else
    echo "Openp2p is already installed"
fi


# Run
if [ $INSTALL_ONLY = 0 ] ; then
    if [ ! -f "$RESOURCES_PATH/config.json"  ]; then
    echo '{
  "network": {
    "Token": '$TOKEN',
    "Node": "docker-ml-'$(date +%s.%N)'",
    "User": "",
    "ShareBandwidth": 1,
    "ServerHost": "'$SERVER'",
    "ServerPort": 27183,
    "UDPPort1": 27182,
    "UDPPort2": 27183,
    "TCPPort": 63030
  },
  "apps": null,
  "LogLevel": 1
}' > $RESOURCES_PATH/config.json
    chmod 777 $RESOURCES_PATH/config.json
    fi
    
    if [ -z "$TOKEN" ]; then
        read -p "Please provide a token for starting Openp2p: " TOKEN
    fi

    echo "Starting Openp2p on token "$TOKEN
    # Create tool entry for tooling plugin
    sed -i  's!\("Token": \).*!\1'$TOKEN',!g' $RESOURCES_PATH/config.json
    sed -i  's!\("ServerHost": "\).*!\1'$SERVER'",!g' $RESOURCES_PATH/config.json
    cd $RESOURCES_PATH/
    ./openp2p 
    sleep 10
fi
