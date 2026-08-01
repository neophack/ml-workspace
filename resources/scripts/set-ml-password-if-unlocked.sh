#!/bin/bash
#
# Idempotently set the `ml` user's login/sudo password and keep it stable across
# restarts.
#
# Usage:
#   echo "ml:<password>" | sudo set-ml-password-if-unlocked.sh
#
# Output (stdout): on every call, prints the currently-effective password for
# the ml user, in the form "EFFECTIVE_ML_PW=<password>". The entrypoint uses
# this to keep the VNC desktop password in sync with the system password.
#
# Two root-owned latch files under /etc pin behavior across restarts:
#   /etc/.ml_ssh_pwd_revoked   — present once the system password has been set;
#                                later restarts skip chpasswd so a user who ran
#                                `passwd` is never clobbered.
#   /etc/.ml_generated_pwd     — if the system password was originally a random
#                                generated value, it is persisted here so the
#                                same secret is reused on every restart
#                                (otherwise VNC desktop and SSH/sudo passwords
#                                would diverge). Root-readable only.
#
# Must run as root. Both latches are root-owned and not writable by ml, so the
# non-root user cannot tamper with them to reset or read the password.

set -eu

MARKER="/etc/.ml_ssh_pwd_revoked"
GEN_PWD_FILE="/etc/.ml_generated_pwd"
USER_NAME="${ML_USER:-ml}"

if [ -e "$MARKER" ]; then
    # Password was pinned on a previous boot. Echo back the effective password so
    # the caller (entrypoint) can sync the VNC desktop password to it.
    if [ -r "$GEN_PWD_FILE" ]; then
        effective="$(cat "$GEN_PWD_FILE")"
    else
        # User changed the password via `passwd`; we do not know it. Signal that
        # the caller should NOT override the VNC desktop password.
        effective=""
    fi
    echo "EFFECTIVE_ML_PW=${effective}"
    echo "[set-ml-password] Marker exists; keeping existing password." >&2
    exit 0
fi

# First boot: read "user:password" from stdin and set it via chpasswd.
if ! chpasswd; then
    echo "[set-ml-password] chpasswd failed for user '$USER_NAME'." >&2
    exit 1
fi

# Capture the password line from stdin was already consumed by chpasswd; the
# caller passes the password separately via argv is NOT an option (it would land
# in `ps`). Instead the caller tells us, via ML_GENERATED_PW env, whether this
# password was randomly generated and should be persisted for reuse.
if [ -n "${ML_GENERATED_PW:-}" ]; then
    printf '%s' "$ML_GENERATED_PW" > "$GEN_PWD_FILE"
    chown root:root "$GEN_PWD_FILE"
    chmod 0600 "$GEN_PWD_FILE"
    echo "EFFECTIVE_ML_PW=${ML_GENERATED_PW}"
else
    echo "EFFECTIVE_ML_PW="
fi

# Pin the system password: create the marker as root so ml cannot remove it.
touch "$MARKER"
chown root:root "$MARKER"
chmod 0644 "$MARKER"
echo "[set-ml-password] Password set for '$USER_NAME'; marker created." >&2
