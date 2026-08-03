# Ubuntu 22.04
# NVIDIA CUDA® 12.8.0 Runtime + cuDNN
# Minimal desktop image:
#   - xfce4 desktop
#   - TigerVNC + noVNC (websockify)
#   - fcitx + 百度拼音输入法
#   - SSH (single-port multiplexed with noVNC via oneport)
#
# No ML / python packages are installed. Only system python3 is available.
#
# This image is amd64-only: TigerVNC tarball, the oneport binary and the
# fcitx baidu-pinyin .deb are all x86-64. Pin the platform so the build is
# reproducible on any host (arm64 hosts build via QEMU emulation).

FROM --platform=linux/amd64 nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

USER root

### BASICS ###

ENV \
    SHELL="/bin/bash" \
    NB_USER="ml" \
    HOME="/home/ml" \
    # Primary group id for the ml user. Use a dedicated non-root group (1000)
    # instead of gid 0 (root group) so the non-root user does NOT inherit
    # root-group write access to system directories.
    USER_GID=1000 \
    XDG_CACHE_HOME="/home/ml/.cache/" \
    XDG_RUNTIME_DIR="/tmp/runtime-root" \
    DISPLAY=":1" \
    TERM="xterm" \
    DEBIAN_FRONTEND="noninteractive" \
    RESOURCES_PATH="/resources" \
    SSL_RESOURCES_PATH="/resources/ssl" \
    WORKSPACE_HOME="/workspace" \
    TZ="Asia/Shanghai" \
    # Browser tab title for noVNC (can be overridden via -e NOVNC_TITLE=xxx).
    # The final title also appends the container hostname and its IP.
    NOVNC_TITLE="Desktop"

WORKDIR $HOME

# Make folders with least-privilege permissions (owner + group writable).
RUN \
    mkdir $RESOURCES_PATH && chmod 0775 $RESOURCES_PATH && \
    mkdir $WORKSPACE_HOME && chmod 0775 $WORKSPACE_HOME && \
    mkdir $SSL_RESOURCES_PATH && chmod 0770 $SSL_RESOURCES_PATH

# Layer cleanup script
COPY resources/scripts/clean-layer.sh  /usr/bin/clean-layer.sh
COPY resources/scripts/fix-permissions.sh  /usr/bin/fix-permissions.sh

# Make clean-layer and fix-permissions executable (build-time utilities)
RUN \
    chmod 0755 /usr/bin/clean-layer.sh && \
    chmod 0755 /usr/bin/fix-permissions.sh

# Generate and Set locals
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends locales && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8 && \
    clean-layer.sh

ENV LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en"

# Install minimal base system packages (no ML/dev libs, no pip/conda packages)
RUN \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends \
        sudo apt-utils ca-certificates \
        # download / transfer
        curl wget gnupg gnupg2 \
        # archive
        zip unzip gzip bzip2 \
        # shell / editor / utils
        bash-completion vim nano less tree jq git \
        htop procps iproute2 iputils-ping net-tools \
        lsof psmisc rsync \
        # required by many gui tools
        xclip \
        # fonts (chinese)
        fonts-wqy-microhei fonts-wqy-zenhei fonts-liberation \
        # timezone data
        tzdata && \
    # configure timezone
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    # Fix permissions
    fix-permissions.sh $HOME && \
    clean-layer.sh

# Create non-root user (member of sudo group; sudo requires a password by
# default except for the restricted service-bootstrap whitelist in
# /etc/sudoers.d/ml-services, installed later in the CONFIGURATION stage).
RUN \
    set -e && \
    chmod g+rw /home && mkdir -p $HOME && \
    # Create a dedicated group (gid from USER_GID, non-root) and the ml user
    # with that group as primary, plus the sudo group for (password-gated)
    # privilege escalation.
    groupadd -g $USER_GID $NB_USER && \
    useradd -d $HOME -s /bin/bash -g $NB_USER -G sudo $NB_USER && \
    chown -R $NB_USER:$NB_USER /home/$NB_USER && \
    # Hand /workspace to the ml user so it is fully owned (not just group-
    # writable) by ml at build time. /workspace was created earlier (root:root)
    # before the ml user existed; fix that now.
    chown -R $NB_USER:$NB_USER $WORKSPACE_HOME && \
    chmod 0775 $WORKSPACE_HOME

# Add tini (init) + SSH
RUN \
    wget --no-verbose https://github.com/krallin/tini/releases/download/v0.19.0/tini -O /tini && \
    chmod +x /tini && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server && \
    chmod go-w /root && \
    # /root/.ssh stays owned by root (never handed to the non-root user).
    mkdir -p /root/.ssh/ && \
    touch /root/.ssh/config && \
    chmod 700 /root/.ssh && \
    # Pre-create the ml user's ~/.ssh skeleton (configure_ssh.py fills it at
    # runtime); StrictModes requires 0700 + owner ml.
    mkdir -p $HOME/.ssh && \
    chown -R $NB_USER:$NB_USER $HOME/.ssh && \
    chmod 700 $HOME/.ssh && \
    mkdir -p /var/run/sshd && \
    fix-permissions.sh $HOME && \
    chmod -R 0775 $RESOURCES_PATH && \
    clean-layer.sh

### END BASICS ###


### RUNTIMES ###

# Supervisor (process manager) + websockify deps, using system python3.
# numpy is required by websockify (noVNC websocket proxy).
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip python3-venv python3-numpy && \
    # provide a `python` alias (many scripts / supervisor cmds expect it)
    ln -sf /usr/bin/python3 /usr/bin/python && \
    pip3 install --no-cache-dir supervisor supervisor-stdout && \
    mkdir -p /var/log/supervisor/ && \
    mkdir -p /var/run/sshd && chmod 0755 /var/run/sshd && \
    clean-layer.sh

ENV PATH=$HOME/.local/bin:$PATH

### END RUNTIMES ###


### GUI TOOLS ###

# Install xfce4 desktop (minimal)
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        xfce4 \
        xfce4-terminal \
        xfce4-clipman \
        xterm \
        xfce4-taskmanager \
        # deps to enable vncserver
        xauth xinit dbus-x11 \
        # X11 / GTK libs required by GUI apps in the desktop
        libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxkbfile1 \
        libxrandr2 libxss1 libasound2 libgtk-3-0 libgbm1 libnss3 libnspr4 \
        # icon themes: xsettings.xml pins IconThemeName=gnome, so the gnome
        # theme (and its hicolor/adwaita fallbacks) must be installed, otherwise
        # panel launchers and menu icons render as broken placeholders.
        gnome-icon-theme adwaita-icon-theme hicolor-icon-theme && \
    # deb installer (needed for fcitx baidu pinyin)
    apt-get install -y --no-install-recommends gdebi-core && \
    apt-get purge -y pm-utils xscreensaver* && \
    clean-layer.sh

# Install TigerVNC + noVNC + websockify
RUN \
    apt-get update && \
    cd ${RESOURCES_PATH} && \
    # Tiger VNC
    wget -qO- https://sourceforge.net/projects/tigervnc/files/stable/1.12.0/tigervnc-1.12.0.x86_64.tar.gz/download | tar xz --strip 1 -C / && \
    # noVNC + websockify
    mkdir -p ./novnc/utils/websockify && \
    wget -qO- https://github.com/novnc/noVNC/archive/v1.3.0.tar.gz | tar xz --strip 1 -C ./novnc && \
    wget -qO- https://github.com/novnc/websockify/archive/v0.10.0.tar.gz | tar xz --strip 1 -C ./novnc/utils/websockify && \
    mkdir -p $HOME/.vnc && \
    fix-permissions.sh ${RESOURCES_PATH} && \
    clean-layer.sh

### END GUI TOOLS ###


### INPUT METHOD ###

COPY resources/fcitx-baidupinyin_1.0.1.0_amd64.deb $RESOURCES_PATH/

RUN \
    apt-get update && \
    apt-get install -y \
        fcitx \
        libgsettings-qt-dev \
        libqt5qml5 libqt5quick5 libqt5quickwidgets5 \
        qml-module-qtquick2 \
        libxss-dev \
        eog && \
    gdebi $RESOURCES_PATH/fcitx-baidupinyin_1.0.1.0_amd64.deb -n && \
    im-config -n fcitx && \
    clean-layer.sh

### END INPUT METHOD ###


### CONFIGURATION ###

# Copy resources into workspace (this overrides noVNC vnc.html / app/ui.js with our customized versions)
COPY ["resources/", "$RESOURCES_PATH/"]

# Configure Home folder (xfce, fcitx)
COPY resources/home/ $HOME/

# Copy ssh configuration files
COPY resources/ssh/ssh_config resources/ssh/sshd_config  /etc/ssh/

# Configure supervisor process
COPY resources/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
# Copy all supervisor program definitions into workspace
COPY resources/supervisor/programs/ /etc/supervisor/conf.d/

# Restricted sudoers whitelist: only service-bootstrap commands may run
# passwordless; everything else requires the ml user's password.
COPY resources/sudoers/ml-services /etc/sudoers.d/ml-services
RUN \
    chmod 0440 /etc/sudoers.d/ml-services && \
    visudo -cf /etc/sudoers.d/ml-services && \
    visudo -cf /etc/sudoers && \
    # ensure the password-provisioning helper and the sshd wrapper are
    # executable (both invoked via sudo at runtime)
    chmod 0755 $RESOURCES_PATH/scripts/set-ml-password-if-unlocked.sh \
                $RESOURCES_PATH/scripts/start-sshd.sh \
                $RESOURCES_PATH/scripts/ml-logout.sh

# Assume yes to all apt commands, to avoid user confusion around stdin.
COPY resources/config/90assumeyes /etc/apt/apt.conf.d/

# Default VNC / login / sudo password (override at runtime with -e VNC_PW=...).
# VNC_PW is used verbatim (no random generation): it sets the VNC desktop
# password (start-vnc-server.sh writes it on every boot) and, on first boot
# only, the ml user's login/sudo password via the one-shot latch script
# set-ml-password-if-unlocked.sh (which creates /etc/.ml_ssh_pwd_revoked).
# Later restarts keep the existing system password, so a user who runs
# `passwd` is never clobbered.
ENV VNC_PW="vncpassword"

# Branding and final fixups
RUN \
    ## create index.html to forward automatically to `vnc.html`
    ln -s $RESOURCES_PATH/novnc/vnc.html $RESOURCES_PATH/novnc/index.html && \
    # Configure git (TLS verification is kept ON for supply-chain safety)
    git config --global core.fileMode false && \
    git config --global credential.helper 'cache --timeout=31540000' || true && \
    # Various configurations
    chmod -R 0775 $WORKSPACE_HOME && \
    chmod -R 0775 $RESOURCES_PATH && \
    # make all desktop launchers executable
    chmod -R 0755 /usr/share/applications/ && \
    # 接管 XFCE 面板菜单「Log Out」项：把它从 xfce4-session-logout 改指向 ml-logout.sh，
    # 点击即停止整个容器（参考 torch-2.1 的 sed 思路，但执行体换成精确 kill 主链路的脚本，
    # 而非无差别的 killall python，避免误伤用户在容器内手动起的 python 进程）。
    # 机制：ml-logout.sh 先尝试 supervisorctl shutdown（优雅 exit 0），失败则 pkill
    # run_workspace.py —— 任一路径都会让 tini 失去子进程 → 容器停止。
    sed -i 's#xfce4-session-logout#'"$RESOURCES_PATH"'/scripts/ml-logout.sh#g' \
        /usr/share/applications/xfce4-session-logout.desktop && \
    # ensure Desktop folder exists (home skeleton may not ship one)
    mkdir -p $HOME/Desktop && \
    ln -s $WORKSPACE_HOME $HOME/Desktop/workspace && \
    # mark desktop shortcuts as trusted (executable) launchers
    chmod a+x $HOME/Desktop/*.desktop 2>/dev/null || true && \
    chown $NB_USER:$NB_USER /tmp && \
    chmod 1777 /tmp && \
    # Set /workspace as default directory to navigate to.
    # ~/.bashrc is shipped from resources/home/ and already cd's to
    # /workspace, so this only acts as a fallback if that file is replaced.
    grep -q "cd $WORKSPACE_HOME" $HOME/.bashrc 2>/dev/null || \
        echo 'cd '$WORKSPACE_HOME >> $HOME/.bashrc && \
    chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo && \
    # NOTE: the ml user's login/sudo password is NOT set at build time. It is
    # provisioned on first container boot by docker-entrypoint.py via the
    # one-shot latch script set-ml-password-if-unlocked.sh (creates
    # /etc/.ml_ssh_pwd_revoked), so the password from VNC_PW is applied exactly
    # once and never clobbers a password the user later changes with `passwd`.
    # The VNC desktop password, by contrast, is rewritten from VNC_PW on every
    # boot by start-vnc-server.sh.
    # Final permission fixups for runtime directories used by supervisord
    # and sshd (least-privilege: writable by owner + group only).
    chown -R $NB_USER:$NB_USER $HOME && \
    chmod -R 0775 $HOME && \
    # supervisord runs as the ml user (user=ml in supervisord.conf). It writes:
    #   - logfile + child program logs -> /var/log/supervisor  (image fs)
    #   - unix socket + pidfile       -> /tmp/supervisor        (image fs)
    # Both must be owned by ml. We deliberately do NOT use /var/run for the
    # socket/pidfile: /var/run is a symlink to /run, which Docker mounts as a
    # root-owned tmpfs at runtime (overriding any build-time ownership), so ml
    # could not create the socket there (EACCES). /tmp/supervisor is a normal
    # image directory, owned by ml, so the socket is writable.
    mkdir -p /var/log/supervisor && \
    chown -R $NB_USER:$NB_USER /var/log/supervisor && \
    chmod -R 0775 /var/log/supervisor && \
    mkdir -p /tmp/supervisor && \
    chown -R $NB_USER:$NB_USER /tmp/supervisor && \
    chmod 0700 /tmp/supervisor && \
    chmod 0700 /var/run/sshd && \
    chmod -R 0775 /var/log

# Environment variables for VNC and workspace
ENV \
    VNC_RESOLUTION=1600x900 \
    VNC_COL_DEPTH=24 \
    # Set default values for environment variables
    WORKSPACE_BASE_URL="/" \
    # Main port used for oneport proxy (multiplexes noVNC + SSH)
    WORKSPACE_PORT="8080" \
    # Add the defaults from /lib/x86_64-linux-gnu
    LD_LIBRARY_PATH=/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu

### END CONFIGURATION ###

USER $NB_USER

# use global option with tini to kill full process groups: https://github.com/krallin/tini#process-group-killing
ENTRYPOINT ["/tini", "-g", "--"]

CMD ["python3", "/resources/docker-entrypoint.py"]

# Port 8080 is the main access port (oneport: multiplexes noVNC HTTP + SSH)
# Port 5901 is the raw VNC port
EXPOSE 8080
