#!/bin/sh
#
# ~/.vnc/xstartup — launches the desktop session inside the TigerVNC server.
#
# Why this file exists:
#   On Ubuntu 24.04 (the base of NGC pytorch:25.03-py3), relying on the
#   `session=xfce` directive in ~/.vnc/config is unreliable: xfce4-session
#   starts without a private D-Bus session bus and without an X resources
#   merge, and exits immediately. Xvnc then sees its session die and
#   terminates ~5s after start, which supervisord reports as a crash loop
#   ("exited: vncserver (terminated by SIGTERM; not expected)").
#
#   An explicit xstartup gives xfce4-session a clean environment on both
#   Ubuntu 20.04 and 24.04. This mirrors how the upstream ml-toolset image
#   (torch-2.1 / cuda-runtime branches) actually starts the desktop, which
#   is why those branches work on the older base.
#
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# X resources / keymap (ignore errors when the user has no .Xresources)
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"
xsetroot -solid grey 2>/dev/null

# Start a private D-Bus session bus and export its address so xfce4-session
# and all spawned apps (including fcitx5) can use it. dbus-launch prints
# "eval" lines setting DBUS_SESSION_BUS_ADDRESS / DBUS_SESSION_BUS_PID; we
# eval them into the current shell.
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
    echo "[xstartup] dbus session bus: $DBUS_SESSION_BUS_ADDRESS"
fi

# Export input-method environment variables so GTK/Qt/XIM applications can
# talk to the running fcitx5 instance. im-config only creates a Wayland profile
# in this container, so set them explicitly for the X11 VNC session. fcitx5
# keeps the "fcitx" im-module name for GTK/Qt/XIM.
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export QT_QPA_PLATFORM=xcb
export QT_QPA_PLATFORMTHEME=gtk2
export XMODIFIERS=@im=fcitx

# Start the fcitx5 input method daemon before the desktop so it is available as
# soon as the XFCE session launches. The Rime engine deploys its schemas on
# first start (see ~/.local/share/fcitx5/rime).
fcitx5 -d &

# Run xfce4-session as the last foreground process. When it exits, Xvnc
# tears the display down — which is the desired lifecycle.
exec startxfce4
