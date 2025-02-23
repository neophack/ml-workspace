#! /usr/bin/env bash
# since vncserver is running as a daemon, we're creating a foreground process uppon vncserver for supervisord.

# Reason: vnc server fails to start via supervisor process:
# spawnerr: unknown error making dispatchers for 'vncserver': ENOENT
# alternative: /usr/bin/Xvnc $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION -Log *:stderr:100
# e.g.: /usr/bin/Xvnc :1 -auth $HOME/.Xauthority -depth 24 -desktop VNC -fp /usr/share/fonts/X11/misc,/usr/share/fonts/X11/Type1 -geometry 1600x900 -pn -rfbauth $HOME/.vnc/passwd -rfbport 5901 -rfbwait 30000
# $HOME/.vnc/xstartup
# vncserver uses Xvnc, all Xvnc options can be used (e.g. for logging)
# https://wiki.archlinux.org/index.php/TigerVNC

set -eu

# Set default values for vnc settings if not provided
VNC_PW=${VNC_PW:-"vncpassword"}
VNC_RESOLUTION=${VNC_RESOLUTION:-"1600x900"}
VNC_COL_DEPTH=${VNC_COL_DEPTH:-"24"}

mkdir -p $HOME/.vnc
touch $HOME/.vnc/passwd

chmod 1777 /tmp 

# Set password:
echo "$VNC_PW" | vncpasswd -f >> $HOME/.vnc/passwd
chmod 600 $HOME/.vnc/passwd

config_file=$HOME/.vnc/config
touch $config_file
printf "geometry=$VNC_RESOLUTION\ndepth=$VNC_COL_DEPTH\ndesktop=Desktop-GUI\nsession=xfce" > ~/.vnc/config
command="/usr/libexec/vncserver $DISPLAY"

# Proxy signals
function kill_app(){
    # correct forwarding of shutdown signal
    _wait_pid=$!
    kill -s SIGTERM $_wait_pid
    trap - SIGTERM && kill -- -$$
    if [ -n "$(pidof xinit)" ] ; then
        ### ignore the errors if not alive any more
        kill $(pidof xinit) > /dev/null 2>&1
    fi
    exit 0 # exit okay
}
trap "kill_app" SIGINT SIGTERM SIGQUIT EXIT

# Old way: is not supported in tiger vnc 11
# /usr/libexec/vncserver -kill $DISPLAY &

# Kill vnc server via the xinit script
# init_pid="$(pidof xinit)"
if [ -n "$(pidof xinit)" ] ; then
    ### ignore the errors if not alive any more
    kill $(pidof xinit) > /dev/null 2>&1
fi

#cleanup tmp from previous run
rm -rfv /tmp/.X*-lock /tmp/.x*-lock /tmp/.X11-unix
# Delete existing logs
find $HOME/.vnc/ -name '*.log' -delete
# rm -rf /tmp/.X* /tmp/.x* /tmp/ssh*

# Launch daemon

sleep 1
$command &> "$HOME/.vnc/vnc.log" &
sleep 5

_wait_pid=$!

echo "Started VNC Server $_wait_pid"

tail -f -q --pid $_wait_pid $HOME/.vnc/*.log &

# Disable screensaver and power management - needs to run after the vnc server is started
xset s noblank && xset s off
# dpms option not available: xset -display :1 -dpms &&

# Loop while the pidfile and the process exist
echo "Starting monitoring pid file for vnc server"
while kill -0 $_wait_pid ; do
    sleep 1
done

exit 1000 # exit unexpected
