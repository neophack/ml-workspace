#!/usr/bin/python3

"""
Configure and run services (minimal cuda-runtime flavor).

Only configures SSH and then starts supervisord, which manages:
  - vncserver (TigerVNC)
  - novnc (websockify web client)
  - sshd
  - oneport (single-port multiplexing of noVNC HTTP + SSH)
"""

from subprocess import call
import os
import sys

import logging
logging.basicConfig(
    format='%(asctime)s [%(levelname)s] %(message)s',
    level=logging.INFO,
    stream=sys.stdout)

log = logging.getLogger(__name__)

log.info("Start Workspace")

ENV_RESOURCES_PATH = os.getenv("RESOURCES_PATH", "/resources")

# Configure ssh service (generates keys, writes ssh environment)
log.info("Configure ssh service")
call("sudo python3 " + ENV_RESOURCES_PATH + "/scripts/configure_ssh.py", shell=True)

# Run a user-provided startup script from the workspace folder if present
WORKSPACE_HOME = os.getenv('WORKSPACE_HOME', "/workspace")
startup_custom_script = os.path.join(WORKSPACE_HOME, "on_startup.sh")
if os.path.exists(startup_custom_script):
    log.info("Run on_startup.sh user script from workspace folder")
    call("/bin/bash " + startup_custom_script, shell=True)

# Run supervisor process - main container process
call('supervisord -n -c /etc/supervisor/supervisord.conf', shell=True)
