#!/bin/bash
#
# Idempotently set the `ml` user's login/sudo password on first boot only.
#
# Usage:
#   echo "ml:<password>" | sudo set-ml-password-if-unlocked.sh
#
# Behavior is pinned across restarts by a single root-owned latch file:
#   /etc/.ml_ssh_pwd_revoked   — present once the system password has been set;
#                                later restarts skip chpasswd so a user who ran
#                                `passwd` is never clobbered.
#
# The password itself comes from VNC_PW (read in the entrypoint) and is also
# (re)written to the VNC desktop password file by start-vnc-server.sh on every
# boot, so the two stay in sync. Only the system login/sudo password is latched
# to the first boot.
#
# Must run as root. The latch is root-owned and not writable by ml, so the
# non-root user cannot tamper with it to reset the password.

set -eu

MARKER="/etc/.ml_ssh_pwd_revoked"
USER_NAME="${ML_USER:-ml}"

if [ -e "$MARKER" ]; then
    # Password was pinned on a previous boot; keep the existing password.
    echo "[set-ml-password] Marker exists; keeping existing password." >&2
    exit 0
fi

# First boot: read "user:password" from stdin and set it via chpasswd.
if ! chpasswd; then
    echo "[set-ml-password] chpasswd failed for user '$USER_NAME'." >&2
    exit 1
fi

# Pin the system password: create the marker as root so ml cannot remove it.
touch "$MARKER"
chown root:root "$MARKER"
chmod 0644 "$MARKER"
echo "[set-ml-password] Password set for '$USER_NAME'; marker created." >&2
