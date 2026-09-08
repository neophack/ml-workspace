#!/usr/bin/env bash
#
# start-openvscode-server.sh — foreground launcher for OpenVSCode Server, called
# by supervisord ([program:openvscode-server]). supervisord's command= line
# cannot express a conditional, so this wrapper reads the CS_REQUIRE_TOKEN env
# var and picks the right token flag.
#
# Token behavior:
#   CS_REQUIRE_TOKEN=true  (default) -> --connection-token "$VNC_PW"
#      Browse to http://host:$CS_PORT/?tkn=<VNC_PW>. Reuses the VNC password as
#      the connection token, mirroring the old code-server --auth password flow.
#   CS_REQUIRE_TOKEN=false          -> --without-connection-token
#      Open to anyone who can reach the port; use only behind network isolation
#      (private network / SSH tunnel / reverse proxy with auth).
set -euo pipefail

# Common flags: bind all interfaces on CS_PORT (>= 1024; supervisord runs as the
# non-root `ml` user), set /workspace as the default folder, and load extensions
# from the same dir populated at build time (OPENVSCODE_EXTENSIONS_DIR, set in the
# Dockerfile). Passing --extensions-dir explicitly keeps build-time installs and
# runtime in sync regardless of OpenVSCode's default data dir.
common_args=(
    --host 0.0.0.0
    --port "${CS_PORT:-8090}"
    --default-folder /workspace
    --extensions-dir "${OPENVSCODE_EXTENSIONS_DIR:-/home/ml/.local/share/openvscode-server/extensions}"
)

if [ "${CS_REQUIRE_TOKEN:-true}" = "true" ]; then
    if [ -z "${VNC_PW:-}" ]; then
        echo "start-openvscode-server: CS_REQUIRE_TOKEN=true but VNC_PW is unset" >&2
        exit 1
    fi
    exec openvscode-server "${common_args[@]}" --connection-token "${VNC_PW}"
else
    exec openvscode-server "${common_args[@]}" --without-connection-token
fi
