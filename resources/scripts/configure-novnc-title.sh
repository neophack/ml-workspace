#!/usr/bin/env bash
#
# Renders the noVNC browser tab title at container startup.
#
# The final title is composed of:
#   ${NOVNC_TITLE}  - customizable via environment variable (default: "Desktop")
#   ${HOSTNAME}     - container name
#   ${container IP} - first non-loopback IPv4 of the container
#
# Result example:  Desktop [a1b2c3d4 @ 172.17.0.2]
#
# noVNC is a pure static frontend (served by websockify), so it cannot read
# container environment variables from the browser. Therefore this script
# rewrites the title into the served static files (app/ui.js + vnc.html)
# before websockify serves them. It is idempotent and safe to run on every
# start, because it matches whole lines (not the rendered value).

set -eu

RESOURCES_PATH="${RESOURCES_PATH:-/resources}"
NOVNC_DIR="${RESOURCES_PATH}/novnc"
UI_JS="${NOVNC_DIR}/app/ui.js"
VNC_HTML="${NOVNC_DIR}/vnc.html"

# --- Compose the title components -------------------------------------------

TITLE_BASE="${NOVNC_TITLE:-Desktop}"
CONTAINER_NAME="${HOSTNAME:-unknown}"

# First non-loopback IPv4 address. `hostname -I` prints space-separated IPs.
CONTAINER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -z "${CONTAINER_IP}" ]; then
    CONTAINER_IP="unknown"
fi

# Escape characters that would break the sed replacement or the JS string.
# We escape backslashes, double quotes, ampersands (sed replacement) and pipes (sed delimiter).
esc_for_sed() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

ESC_TITLE="$(esc_for_sed "${TITLE_BASE} [${CONTAINER_NAME} @ ${CONTAINER_IP}]")"

FINAL_TITLE="${TITLE_BASE} [${CONTAINER_NAME} @ ${CONTAINER_IP}]"

echo "[configure-novnc-title] Browser title -> ${FINAL_TITLE}"

# --- Rewrite the PAGE_TITLE constant in app/ui.js ---------------------------
# Matches:  const PAGE_TITLE = "...";
if [ -f "${UI_JS}" ]; then
    sed -i -E "s|^const PAGE_TITLE = .*;$|const PAGE_TITLE = \"${ESC_TITLE}\";|" "${UI_JS}"
else
    echo "[configure-novnc-title] WARNING: ${UI_JS} not found" >&2
fi

# --- Rewrite the <title> tag in vnc.html ------------------------------------
# Matches:  <title>...</title>
if [ -f "${VNC_HTML}" ]; then
    sed -i -E "s|<title>.*</title>|<title>${ESC_TITLE}</title>|" "${VNC_HTML}"
else
    echo "[configure-novnc-title] WARNING: ${VNC_HTML} not found" >&2
fi

# --- Rewrite the visible brand block in vnc.html ----------------------------
# Replaces the text inside the two brand divs (main title + host info).
# Idempotent: the regex anchors on the stable div ids, so it matches the
# structure rather than the rendered value. This keeps working across restarts
# even when hostname/IP change.
if [ -f "${VNC_HTML}" ]; then
    ESC_BRAND_TITLE="$(esc_for_sed "${TITLE_BASE}")"
    ESC_BRAND_SUB="$(esc_for_sed "${CONTAINER_NAME} @ ${CONTAINER_IP}")"
    sed -i -E \
        -e "s|(<div id=\"noVNC_brand_title\"[^>]*>)[^<]*(</div>)|\1${ESC_BRAND_TITLE}\2|" \
        -e "s|(<div id=\"noVNC_brand_subtitle\"[^>]*>)[^<]*(</div>)|\1${ESC_BRAND_SUB}\2|" \
        "${VNC_HTML}"
fi

exit 0
