#!/usr/bin/python3

"""
Configure and run services (minimal cuda-runtime flavor).

Only configures SSH and then starts supervisord, which manages:
  - vncserver (TigerVNC)
  - novnc (websockify web client)
  - sshd
  - oneport (single-port multiplexing of noVNC HTTP + SSH)

Security note: subprocess is invoked with argument lists (never shell=True) to
avoid command injection from environment-controlled values.
"""

import logging
import os
import sys
from subprocess import run

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    stream=sys.stdout,
)

log = logging.getLogger(__name__)

log.info("Start Workspace")

ENV_RESOURCES_PATH = os.getenv("RESOURCES_PATH", "/resources")

# Configure ssh service (generates keys, writes ssh environment).
# Runs as root via the restricted sudoers whitelist; configure_ssh.py itself
# only ever needs to run once at startup.
log.info("Configure ssh service")
run(
    ["sudo", "-n", "/usr/bin/python3",
     f"{ENV_RESOURCES_PATH}/scripts/configure_ssh.py"],
    check=False,
)

# NOTE: we intentionally do NOT execute any script from /workspace. The workspace
# is a shared, user-writable data volume; auto-running scripts from it is a
# persistent-backdoor risk surface (anything that can write the volume could
# plant a script that runs on every boot). Users who need startup customization
# should extend the image and place scripts under /resources/scripts instead.

# Run supervisor process - main container process.
sys.exit(
    run(
        ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
    ).returncode
)
