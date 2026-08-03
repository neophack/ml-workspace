#!/usr/bin/python3

"""
Main Workspace Entry Point (minimal cuda-runtime flavor).

Responsibilities:
  1. Resolve the web base url (supports reverse proxy / jupyterhub prefix).
  2. Set the `ml` user's login/sudo password from VNC_PW (so SSH password login
     and interactive sudo work out of the box; overridable per deployment).
  3. Delegate to run_workspace.py which configures ssh and starts supervisord.
"""

import logging
import os
import sys
from subprocess import run
from urllib.parse import quote

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    stream=sys.stdout,
)

log = logging.getLogger(__name__)

log.info("Starting cuda-runtime workspace...")


def set_env_variable(env_variable: str, value: str, ignore_if_set: bool = False):
    if ignore_if_set and os.getenv(env_variable, None):
        return
    os.environ[env_variable] = value


# --- Manage base path dynamically (reverse proxy friendly) -------------------

ENV_JUPYTERHUB_SERVICE_PREFIX = os.getenv("JUPYTERHUB_SERVICE_PREFIX", None)

ENV_NAME_WORKSPACE_BASE_URL = "WORKSPACE_BASE_URL"
base_url = os.getenv(ENV_NAME_WORKSPACE_BASE_URL, "")

if ENV_JUPYTERHUB_SERVICE_PREFIX:
    base_url = ENV_JUPYTERHUB_SERVICE_PREFIX

if not base_url.startswith("/"):
    base_url = "/" + base_url

base_url = base_url.rstrip("/").strip()
base_url = quote(base_url, safe="/%")

set_env_variable(ENV_NAME_WORKSPACE_BASE_URL, base_url)

ENV_RESOURCES_PATH = os.getenv("RESOURCES_PATH", "/resources")

# --- Resolve VNC_PW ---------------------------------------------------------
# VNC_PW is shared across: VNC desktop password, SSH login password, and the
# interactive sudo password. It is taken verbatim from the environment (build-
# time default "vncpassword"); override at runtime with -e VNC_PW=... to choose
# your own. No random generation is performed.
ENV_NB_USER = os.getenv("NB_USER", "ml")
vnc_pw = os.getenv("VNC_PW", "vncpassword")

# --- Set the ml user password from VNC_PW (one-shot, idempotent) ------------
# The helper reads the credential from stdin (never in `ps`) and is latched by
# /etc/.ml_ssh_pwd_revoked: the system login/sudo password is set ONLY on first
# boot. Later restarts keep the existing password, so a user who runs `passwd`
# is not clobbered. The VNC desktop password is always (re)written from VNC_PW
# by start-vnc-server.sh.
helper = f"{ENV_RESOURCES_PATH}/scripts/set-ml-password-if-unlocked.sh"
try:
    run(["sudo", "-n", helper], input=f"{ENV_NB_USER}:{vnc_pw}\n",
        text=True, check=True, capture_output=True)
    log.info("Login/sudo password provisioning checked for '%s'.", ENV_NB_USER)
except Exception as exc:  # pragma: no cover - startup best-effort
    log.warning("Failed to provision login password for '%s': %s", ENV_NB_USER, exc)

# Delegate to the workspace runner. Pass script arguments through verbatim.
cmd = ["python3", f"{ENV_RESOURCES_PATH}/scripts/run_workspace.py", *sys.argv[1:]]
sys.exit(run(cmd).returncode)
