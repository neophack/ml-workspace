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
# NOTE: do NOT set `session=xfce` here. On Ubuntu 24.04 (NGC pytorch:25.03-py3
# base) relying on the built-in session launcher leaves xfce4-session without a
# D-Bus session bus, so it exits immediately and Xvnc tears down ~5s later —
# observed as a supervisord crash loop. The desktop is started instead via
# ~/.vnc/xstartup (see below), which works on both 20.04 and 24.04.
printf "geometry=$VNC_RESOLUTION\ndepth=$VNC_COL_DEPTH\ndesktop=Desktop-GUI" > "$config_file"

# Deploy a desktop-launching xstartup. TigerVNC runs ~/.vnc/xstartup to bring
# up the session; without it (or with only `session=`) the desktop fails to
# start on newer Ubuntu bases.
xstartup_src="${RESOURCES_PATH:-/resources}/scripts/xstartup-template.sh"
xstartup_dst="$HOME/.vnc/xstartup"
if [ -f "$xstartup_src" ]; then
    cp -f "$xstartup_src" "$xstartup_dst"
    chmod 755 "$xstartup_dst"
fi
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
# Capture the PID of the vncserver child immediately (before any other
# background job is spawned, so $! refers unambiguously to vncserver).
_wait_pid=$!

echo "Started VNC Server $_wait_pid"

sleep 5

tail -f -q --pid $_wait_pid $HOME/.vnc/*.log &

# Disable screensaver and power management - needs to run after the vnc server is started.
# Run on the VNC display and tolerate failure: under `set -eu` a non-zero xset
# (e.g. the server not having fully opened its socket yet on 24.04) would
# otherwise kill the whole script and trip the supervisord crash loop.
DISPLAY=$DISPLAY xset s noblank 2>/dev/null || true
DISPLAY=$DISPLAY xset s off 2>/dev/null || true
# dpms option not available: xset -display :1 -dpms &&

# Loop while the pidfile and the process exist
echo "Starting monitoring pid file for vnc server"
while kill -0 $_wait_pid ; do
    sleep 1
done

exit 1000 # exit unexpected
