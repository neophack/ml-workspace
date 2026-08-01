#!/bin/bash
#
# Privilege-separated wrapper that launches sshd in the foreground with a
# FIXED, hardened configuration. It exists so that the non-root `ml` user can
# start the system sshd via sudo WITHOUT being granted arbitrary sshd
# arguments (which would allow local root escalation, e.g.
#   sudo /usr/sbin/sshd -f /tmp/evil -o PermitRootLogin=yes).
#
# This exact path is the only sshd-related entry whitelisted in sudoers.
# Do NOT add wildcard arguments to that whitelist.

set -eu

# `env -i` resets the environment so K8s/Docker-injected variables do not leak
# into sshd (otherwise a large env can break client connections).
exec env -i /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
