#!/bin/sh
#
# run-sogoupinyin.sh — foreground launcher for Sogou Pinyin's candidate-box
# service, meant to run under supervisord (see
# resources/supervisor/programs/sogoupinyin.conf).
#
# Why this wrapper exists:
#   Sogou's candidate window is drawn by sogoupinyin-service (a Qt5/QML
#   process), not by fcitx itself. The service needs the XFCE session's
#   DISPLAY and D-Bus session bus, but supervisord starts long before the
#   VNC desktop exists — so this script first waits for xfce4-session and
#   adopts its environment, then waits for fcitx to answer, and only then
#   execs the service.
#
#   The service exits whenever fcitx restarts or its D-Bus name vanishes
#   ("IpcDbus::SogouImeServerExit" in ~/.xsession-errors); supervisord's
#   autorestart then re-runs this wrapper and brings it back. Sogou's own
#   /etc/xdg/autostart entries are disabled (Hidden=true in the Dockerfile)
#   so supervisord is the only one managing the service lifecycle.

# Wait (up to ~2 min) for the XFCE session of this user to appear.
i=0
SESSION_PID=
while [ $i -lt 120 ]; do
    SESSION_PID=$(pgrep -u "$(id -u)" -x xfce4-session | head -1)
    [ -n "$SESSION_PID" ] && break
    sleep 1
    i=$((i + 1))
done
if [ -z "$SESSION_PID" ]; then
    echo "[run-sogoupinyin] no xfce4-session found, giving up" >&2
    exit 1
fi

# Adopt the session's D-Bus address; the VNC desktop always lives on :1.
export DISPLAY=:1
DBUS_ADDR=$(tr '\0' '\n' < "/proc/$SESSION_PID/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
[ -n "$DBUS_ADDR" ] && export DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR"
export XMODIFIERS=@im=fcitx GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx

# Wait up to ~15s for fcitx to answer fcitx-remote.
i=0
while [ $i -lt 30 ]; do
    fcitx-remote >/dev/null 2>&1 && break
    sleep 0.5
    i=$((i + 1))
done

echo "[run-sogoupinyin] starting sogoupinyin-service (session pid $SESSION_PID)"
/opt/sogoupinyin/files/bin/sogoupinyin-service &

# When supervisord stops this program, take the daemonized service down too.
trap 'pkill -f /opt/sogoupinyin/files/bin/sogoupinyin-service; exit 0' TERM INT

# sogoupinyin-service daemonizes: the process we just spawned forks and the
# parent exits 0 immediately, so supervisord cannot track $!. Watch the
# daemonized process instead; when it disappears (e.g. fcitx restarted and
# its D-Bus name vanished — "IpcDbus::SogouImeServerExit"), exit so
# supervisord's autorestart runs this wrapper again.
while pgrep -f /opt/sogoupinyin/files/bin/sogoupinyin-service >/dev/null 2>&1; do
    sleep 2
done
echo "[run-sogoupinyin] sogoupinyin-service gone, exiting for restart" >&2
exit 1
