#!/usr/bin/python3

"""
Configure the SSH service at container startup.

Generates an ed25519 key pair (if absent) under the `ml` user's ~/.ssh so that
public-key login actually works (the container only permits the `ml` user to
log in). Exposes ONLY the public key under $RESOURCES_PATH so it can be fetched
out of band; the private key stays at ~/.ssh/<key> with mode 0600.

Security notes:
  - subprocess is invoked with argument lists (never shell=True).
  - The private key is never copied into a world-readable location.
  - Only *.pub is published, with mode 0644.
  - The ssh session environment file is written with a strict whitelist
    (locale only) to avoid leaking secrets/tokens injected via the container
    environment.
"""

import logging
import os
import sys
from pathlib import Path
from subprocess import run

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    stream=sys.stdout,
)

log = logging.getLogger(__name__)

# The login user: sshd only allows this user (AllowUsers ml), so keys and
# authorized_keys MUST live in THIS user's home, not /root. Resolve the home
# directory explicitly (do NOT rely on $HOME, which sudo may reset to /root).
NB_USER = os.getenv("NB_USER", "ml")
HOME = Path(f"/home/{NB_USER}")
RESOURCE_FOLDER = Path(os.environ.get("RESOURCES_PATH", "/resources"))
SSH_DIR = HOME / ".ssh"
SSH_KEY_NAME = "id_ed25519"

# Whitelist of environment variables forwarded into ssh sessions. Locale only:
# these are harmless and commonly expected by interactive shells. Everything
# else (notably anything that may carry a secret) is dropped.
def _is_locale_var(key: str) -> bool:
    return key == "LANG" or key.startswith("LC_")


def sh(cmd, **kwargs):
    """Run a command given as an argument list (no shell)."""
    return run(cmd, **kwargs)


SSH_DIR.mkdir(parents=True, exist_ok=True)

# --- Export a curated environment for ssh sessions (whitelist only) ---------
env_path = SSH_DIR / "environment"
with env_path.open("w") as fp:
    for key, value in os.environ.items():
        if not _is_locale_var(key):
            continue
        fp.write(f"{key}={value}\n")

# --- Generate an SSH key pair (for ssh / remote kernel access) ---------------
key_path = SSH_DIR / SSH_KEY_NAME
if not key_path.is_file():
    log.info("Creating new SSH Key (%s) for user '%s'", SSH_KEY_NAME, NB_USER)
    sh(["ssh-keygen", "-f", str(key_path), "-t", "ed25519", "-q", "-N", ""],
       check=True, stdout=sys.stderr)

# Publish ONLY the public key under $RESOURCES_PATH (mode 0644).
pub_src = SSH_DIR / f"{SSH_KEY_NAME}.pub"
pub_dst = RESOURCE_FOLDER / "public-key.pub"
sh(["/bin/cp", "-f", str(pub_src), str(pub_dst)], check=True)

# Ensure known_hosts and authorized_keys exist.
for name in ("authorized_keys", "known_hosts"):
    (SSH_DIR / name).touch(exist_ok=True)

# Add the public key to authorized_keys (idempotently).
auth_path = SSH_DIR / "authorized_keys"
pub_line = pub_src.read_text().strip()
existing = auth_path.read_text() if auth_path.is_file() else ""
if pub_line not in existing.splitlines():
    with auth_path.open("a") as fp:
        fp.write(pub_line + "\n")

# Add the identity to the ssh agent (best-effort, used e.g. for git auth).
sh(
    ["bash", "-c", 'eval "$(ssh-agent -s)" && ssh-add "$0" > /dev/null',
     str(key_path)],
    check=False,
)

# --- Fix permissions (StrictModes compliant) --------------------------------
# Directory 0700, private key 0600, public keys 0644. Files are created by root
# (this script runs via sudo), so chown them to the login user; otherwise
# StrictModes rejects keyfiles not owned by the account.
sh(["chown", "-R", f"{NB_USER}:{NB_USER}", str(SSH_DIR)], check=False)
sh(["chmod", "700", str(SSH_DIR)], check=False)
sh(["chmod", "600", str(key_path)], check=False)
sh(["chmod", "644", str(pub_src)], check=False)
sh(["chmod", "644", str(pub_dst)], check=False)
