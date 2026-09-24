#!/bin/sh

# Stops script execution if a command has an error
set -e

ZCODE_VERSION="3.14.3"
ZCODE_DEB_URL="https://cdn-zcode.z.ai/zcode/electron/releases/${ZCODE_VERSION}/linux-x64/ZCode-${ZCODE_VERSION}-linux-x64.deb"

# The official .deb is amd64-only (URL path: linux-x64).
if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo "ERROR: ZCode is amd64-only, but this build is $(dpkg --print-architecture)." >&2
    exit 1
fi

if ! hash zcode 2>/dev/null; then
    echo "Installing ZCode ${ZCODE_VERSION}. Please wait..."
    cd /tmp
    wget "$ZCODE_DEB_URL" -O ./zcode.deb
    apt-get update
    # apt (not dpkg) so the deb's declared Electron runtime deps are resolved.
    apt-get install -y --no-install-recommends ./zcode.deb
    rm -f ./zcode.deb
else
    echo "ZCode is already installed"
fi

# Make the Electron binary container-safe. This container's runtime forbids
# user namespaces even for root, so Electron's chrome-sandbox cannot work
# under any configuration (setuid root included). Replace /opt/ZCode/zcode
# with a wrapper that appends --no-sandbox, keeping the real binary as
# zcode.real. The wrapper also raises the fd soft limit 1024 -> 65535,
# which fixes the EMFILE errors seen at startup.
if [ -f /opt/ZCode/zcode ] && [ ! -f /opt/ZCode/zcode.real ]; then
    mv /opt/ZCode/zcode /opt/ZCode/zcode.real
    printf '%s\n' \
        '#!/bin/bash' \
        'ulimit -n 65535 2>/dev/null || true' \
        'exec /opt/ZCode/zcode.real --no-sandbox "$@"' \
        > /opt/ZCode/zcode
    chmod +x /opt/ZCode/zcode
fi

ln -sf /opt/ZCode/zcode /usr/local/bin/zcode

# Desktop entry: applications menu + double-clickable shortcut on the VNC
# desktop. Icon prefers the hi-res PNG shipped inside the package.
ICON="zcode"
for candidate in \
    /usr/share/icons/hicolor/512x512/apps/zcode.png \
    /usr/share/icons/hicolor/256x256/apps/zcode.png \
    /usr/share/pixmaps/zcode.png; do
    if [ -f "$candidate" ]; then
        ICON="$candidate"
        break
    fi
done
printf '[Desktop Entry]\nEncoding=UTF-8\nName=ZCode\nComment=ZCode IDE\nExec=zcode %%U\nIcon=%s\nTerminal=false\nStartupNotify=true\nType=Application\nCategories=Development;IDE;\n' "$ICON" > /usr/share/applications/zcode.desktop
mkdir -p "$HOME/Desktop"
cp /usr/share/applications/zcode.desktop "$HOME/Desktop/zcode.desktop"
chmod +x "$HOME/Desktop/zcode.desktop"
