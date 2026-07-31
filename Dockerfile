# Ubuntu 22.04
# NVIDIA CUDA® 12.8.0 Runtime + cuDNN
# Minimal desktop image:
#   - xfce4 desktop
#   - TigerVNC + noVNC (websockify)
#   - VS Code
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
    USER_GID=0 \
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

# Make folders
RUN \
    mkdir $RESOURCES_PATH && chmod a+rwx $RESOURCES_PATH && \
    mkdir $WORKSPACE_HOME && chmod a+rwx $WORKSPACE_HOME && \
    mkdir $SSL_RESOURCES_PATH && chmod a+rwx $SSL_RESOURCES_PATH

# Layer cleanup script
COPY resources/scripts/clean-layer.sh  /usr/bin/clean-layer.sh
COPY resources/scripts/fix-permissions.sh  /usr/bin/fix-permissions.sh

# Make clean-layer and fix-permissions executable
RUN \
    chmod a+rwx /usr/bin/clean-layer.sh && \
    chmod a+rwx /usr/bin/fix-permissions.sh

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

# Create non-root user (passwordless sudo)
RUN \
    set -e && \
    chmod g+rw /home && mkdir -p $HOME && \
    useradd -d $HOME -s /bin/bash -G sudo $NB_USER && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    chown -R $NB_USER.$NB_USER /home/$NB_USER

# Add tini (init) + SSH
RUN \
    wget --no-verbose https://github.com/krallin/tini/releases/download/v0.19.0/tini -O /tini && \
    chmod +x /tini && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server && \
    chmod go-w /root && \
    mkdir -p /root/.ssh/ && \
    touch /root/.ssh/config && \
    sudo chown -R $NB_USER:users /root/.ssh && \
    chmod 700 /root/.ssh && \
    mkdir -p /var/run/sshd && \
    fix-permissions.sh $HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
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
    mkdir -p /var/run/sshd && chmod 400 /var/run/sshd && \
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
        # X11 / GTK libs required by VS Code and other GUI apps
        libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxkbfile1 \
        libxrandr2 libxss1 libasound2 libgtk-3-0 libgbm1 libnss3 libnspr4 && \
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

# Install Visual Studio Code
COPY resources/tools/vs-code-desktop.sh $RESOURCES_PATH/tools/vs-code-desktop.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/vs-code-desktop.sh --install && \
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

# Configure Home folder (xfce, fcitx, code)
COPY resources/home/ $HOME/

# Copy ssh configuration files
COPY resources/ssh/ssh_config resources/ssh/sshd_config  /etc/ssh/

# Configure supervisor process
COPY resources/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
# Copy all supervisor program definitions into workspace
COPY resources/supervisor/programs/ /etc/supervisor/conf.d/

# Assume yes to all apt commands, to avoid user confusion around stdin.
COPY resources/config/90assumeyes /etc/apt/apt.conf.d/

# Branding and final fixups
RUN \
    ## create index.html to forward automatically to `vnc.html`
    ln -s $RESOURCES_PATH/novnc/vnc.html $RESOURCES_PATH/novnc/index.html && \
    # Configure git
    git config --global core.fileMode false && \
    git config --global http.sslVerify false && \
    git config --global credential.helper 'cache --timeout=31540000' || true && \
    # Various configurations
    chmod -R a+rwx $WORKSPACE_HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
    # make all desktop launchers executable
    chmod -R a+rwx /usr/share/applications/ && \
    # ensure Desktop folder exists (home skeleton may not ship one)
    mkdir -p $HOME/Desktop && \
    ln -s $RESOURCES_PATH/tools/ $HOME/Desktop/Tools && \
    ln -s $WORKSPACE_HOME $HOME/Desktop/workspace && \
    chown $NB_USER:$NB_USER /tmp && \
    chmod 1777 /tmp && \
    chmod a+rwx /tmp && \
    # Set /workspace as default directory to navigate to
    echo 'cd '$WORKSPACE_HOME >> $HOME/.bashrc && \
    chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo

# Environment variables for VNC and workspace
ENV \
    # Basic VNC Settings - no password
    VNC_PW=vncpassword \
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

RUN \
    sudo chmod 777 $HOME/ -R && \
    sudo chown ml:ml $HOME/ -R && \
    sudo chmod 777 /var/log/supervisor/ -R && \
    sudo chmod 777 /var/run -R && \
    sudo chmod 400 /var/run/sshd && \
    sudo chmod 777 /var/log -R

# use global option with tini to kill full process groups: https://github.com/krallin/tini#process-group-killing
ENTRYPOINT ["/tini", "-g", "--"]

CMD ["python3", "/resources/docker-entrypoint.py"]

# Port 8080 is the main access port (oneport: multiplexes noVNC HTTP + SSH)
# Port 5901 is the raw VNC port
EXPOSE 8080
