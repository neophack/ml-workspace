#!/usr/bin/python3

"""
Main Workspace Run Script (minimal cuda-runtime flavor)

Responsibilities:
  1. Resolve the web base url (supports reverse proxy / jupyterhub prefix).
  2. Delegate to run_workspace.py which configures ssh and starts supervisord.
"""

import logging
import os
import sys
from subprocess import call
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


# --- Manage base path dynamically (reverse proxy friendly) ---

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

# pass all script arguments to next script
script_arguments = " " + " ".join(sys.argv[1:])

sys.exit(
    call(
        "python3 " + ENV_RESOURCES_PATH + "/scripts/run_workspace.py" + script_arguments,
        shell=True,
    )
)
