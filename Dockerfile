# Slim ML workspace — single-port (8080) VNC desktop + SSH appliance, plus
# OpenVSCode Server (VS Code in the browser) on port 8090. The XFCE desktop
# ships the Chromium browser (open-source Chrome), ZCode (Electron IDE) and
# PyCharm Community.
#
# Base:   nvcr.io/nvidia/pytorch:25.03-py3
#         Ubuntu 24.04 LTS (noble) + Python 3.12 + CUDA 12.8.1 + cuDNN 9.8 + PyTorch 2.7.0a
# GPUs:   V100 (sm_70) as the minimum, through the latest — Ampere (sm_80/86), Ada (sm_89),
#         Hopper (sm_90), Blackwell (sm_100/120: B100/B200, RTX 50).
#
# Single port 8080 is served by `oneport` (a small Go protocol-sniffer binary, no nginx):
#   HTTP -> noVNC/websockify on 6901   (VNC web desktop)
#   SSH  -> sshd on 22
#
# CUDA architecture coverage:
#   TORCH_CUDA_ARCH_LIST is set to "7.0;7.5;8.0;8.6;8.9;9.0;10.0;12.0" so any CUDA extension
#   compiled at runtime (deepspeed, custom ops, a vLLM source build) targets V100 through
#   Blackwell. The NGC torch wheel already ships binaries for these arches where supported.
#   On first run, verify what torch itself exposes:
#       python -c "import torch; print(torch.cuda.get_arch_list())"
#
# V100 (sm_70) caveats — the minimum target:
#   * V100 has FP16 Tensor Cores only — NO BF16, NO FP8. Use torch.cuda.amp in fp16 on V100.
#   * PyTorch dropped sm_70 from *upstream* prebuilt wheels at 2.5. The NGC image builds torch
#     from source and historically covers a broad arch list, but sm_70 is NOT guaranteed here.
#     If `torch.cuda.get_arch_list()` omits 7.0 you will see, on a V100:
#         "no kernel image available for execution on the device"
#     Fix: rebuild torch from source with TORCH_CUDA_ARCH_LIST="7.0" (or use an older NGC tag).
#
# vLLM — NOT installed in this image, only the runtime is prepared:
#   * Prebuilt vLLM wheels target sm_80+ (no sm_70). For V100 build from source (see below).
#   * On newer GPUs (A100/H100/B200) `pip install vllm` usually just works.
#   * V100 (sm_70) source build:
#         pip install -v vllm==0.8.4 --no-build-isolation \
#             -C cmake.args="-DCMAKE_CUDA_ARCHITECTURES=70"
#       (TORCH_CUDA_ARCH_LIST already exported here; last sm_70-friendly vLLM ~0.7.3 / 0.8.4.)
#   * Multi-arch source build (V100 + newer): set CMAKE_CUDA_ARCHITECTURES="70;80;86;89;90".
#   * Community sm_70 fork:   https://github.com/1CatAI/1Cat-vLLM
#   * Upstream:               https://github.com/vllm-project/vllm

FROM nvcr.io/nvidia/pytorch:25.03-py3

USER root

### BASICS ###
# Technical Environment Variables
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
    # Target NVIDIA GPUs from V100 (sm_70, the minimum) through Blackwell (sm_120).
    # Used when building CUDA extensions at runtime (deepspeed, custom ops, a vLLM source build).
    #   7.0=V100  7.5=T4  8.0=A100  8.6=RTX30/A40  8.9=RTX40/L4/L40
    #   9.0=H100  10.0=GB202(B200)  12.0=RTX50
    TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0;10.0;12.0" \
    CUDA_ARCH="70;75;80;86;89;90;100;120"

WORKDIR $HOME

# The NGC pytorch image ships torch 2.7.0a0+nv25.3 (built for sm_70–sm_120) and numpy 1.26.4.
# Our pip installs must NOT upgrade torch/torchvision/numpy/nvidia-* — that would replace the
# NGC-optimized build with stock PyPI wheels (which dropped sm_70, breaking V100). The
# requirements file is additive only (no numpy/torch pins) and we install without --upgrade.
ENV PIP_NO_BUILD_ISOLATION=0 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Make folders
RUN \
    mkdir -p $RESOURCES_PATH && chmod a+rwx $RESOURCES_PATH && \
    mkdir -p $SSL_RESOURCES_PATH && chmod a+rwx $SSL_RESOURCES_PATH

# Layer cleanup / permission helpers
COPY resources/scripts/clean-layer.sh  /usr/bin/clean-layer.sh
COPY resources/scripts/fix-permissions.sh  /usr/bin/fix-permissions.sh
RUN \
    chmod a+rwx /usr/bin/clean-layer.sh && \
    chmod a+rwx /usr/bin/fix-permissions.sh

# Generate and set locales
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

# Install core apt packages (Ubuntu 24.04 / noble).
# Removed vs. the old image: unp (gone from noble), zlibc (obsolete), sslh (replaced by oneport),
# ttf-wqy-zenhei -> fonts-wqy-zenhei (renamed), node/npm/typescript toolchain, pyenv, sdkman.
# (chromium is installed from ppa:xtradeb/apps in its own block below.)
RUN \
    apt-get update --fix-missing && \
    apt-get install -y sudo apt-utils && \
    apt-get upgrade -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        gnupg-agent \
        gpg-agent \
        gnupg2 \
        ca-certificates \
        build-essential \
        pkg-config \
        software-properties-common \
        lsof \
        net-tools \
        libcurl4 \
        curl \
        wget \
        cron \
        openssl \
        iproute2 \
        psmisc \
        tmux \
        uuid-dev \
        xclip \
        clinfo \
        time \
        libssl-dev \
        libgdbm-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libreadline-dev \
        libedit-dev \
        libffi-dev \
        xz-utils \
        gawk \
        swig \
        graphviz libgraphviz-dev \
        screen \
        nano \
        tree \
        bash-completion \
        iputils-ping \
        socat \
        jq \
        rsync \
        libsqlite3-dev \
        sqlite3 \
        git \
        subversion \
        unixodbc unixodbc-dev \
        libtiff-dev \
        libjpeg-dev \
        libpng-dev \
        libglib2.0-0 \
        libxext6 \
        libsm6 \
        libxext-dev \
        libxrender1 \
        libzmq3-dev \
        protobuf-compiler \
        libprotobuf-dev \
        libprotoc-dev \
        autoconf \
        automake \
        libtool \
        cmake \
        fonts-liberation \
        google-perftools \
        zip \
        gzip \
        unzip \
        bzip2 \
        lzop \
        libarchive-tools \
        libbz2-dev \
        liblzma-dev \
        libspatialindex-dev \
        libhiredis-dev \
        libpq-dev \
        default-libmysqlclient-dev \
        libgeos-dev \
        libtiff-dev \
        less \
        fonts-wqy-microhei \
        fonts-wqy-zenhei \
        gdb \
        gosu \
        htop \
        nvtop \
        zlib1g-dev && \
    # Newer git from the official PPA
    add-apt-repository -y ppa:git-core/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends git && \
    chmod -R a+rwx /usr/local/bin/ && \
    ldconfig && \
    fix-permissions.sh $HOME && \
    clean-layer.sh

# Create the non-root user `ml`
# The NVIDIA base image ships an `ubuntu` user occupying UID/GID 1000.
# Remove it so we can pin `ml` to UID/GID 1000 — the UID almost every host
# login user has, which makes bind-mounted volumes line up owner-for-owner
# across machines instead of showing up as a foreign `ubuntu`/1001 owner.
RUN \
    set -e && \
    chmod g+rw /home && mkdir -p $HOME && \
    if id ubuntu >/dev/null 2>&1; then \
        userdel -r ubuntu 2>/dev/null || userdel ubuntu 2>/dev/null || true; \
    fi && \
    groupadd -g 1000 $NB_USER 2>/dev/null || groupmod -g 1000 $NB_USER 2>/dev/null || true && \
    useradd -u 1000 -g 1000 -d $HOME -s /bin/bash -G sudo $NB_USER && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    chown -R $NB_USER:$NB_USER /home/$NB_USER

# tini init + SSH server
RUN \
    wget --no-verbose https://github.com/krallin/tini/releases/download/v0.19.0/tini -O /tini && \
    chmod +x /tini && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server \
        autossh \
        mussh && \
    chmod go-w /root && \
    mkdir -p /root/.ssh/ && \
    touch /root/.ssh/config && \
    sudo chown -R $NB_USER:users /root/.ssh && \
    chmod 700 /root/.ssh && \
    printenv >> /root/.ssh/environment && \
    chmod -R a+rwx /usr/local/bin/ && \
    fix-permissions.sh $HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
    clean-layer.sh

### END BASICS ###


# Supervisor for process management. Plain pip (not pipx) because supervisor-stdout
# (an old sdist) fails to build inside pipx's isolated venv (no setuptools there).
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        rsyslog && \
    pip install --no-cache-dir supervisor supervisor-stdout && \
    mkdir -p /var/run/sshd && chmod 400 /var/run/sshd && \
    mkdir -p /var/log/supervisor/ && \
    clean-layer.sh

ENV PATH=$HOME/.local/bin:$PATH


### GUI TOOLS ###

# xfce4 desktop + lightweight editors / file tools (browser and IDE are
# installed in their own blocks below)
#
# IMPORTANT (Ubuntu 24.04 / Noble): do NOT add the `ppa:xubuntu-dev/staging` PPA
# that the torch-2.1 branch used on 20.04. On Noble the PPA's apt-get update
# fails (signature/network), and because the previous block ended with
# `... || true` the whole `apt-get install` failure was silently swallowed —
# the image "built" but xfce4, xauth, xinit and dbus-x11 were never installed,
# so TigerVNC died on startup with `couldn't find "xauth" on your PATH` and
# supervisord reported a vncserver crash loop. Noble's official universe repo
# already ships xfce4 4.18, so the PPA is unnecessary. The optional purge/remove
# steps at the end are allowed to find no packages without aborting the build,
# but the core install above MUST succeed (no `|| true` swallowing it).
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        xfce4 \
        xfce4-terminal \
        xfce4-clipman \
        xterm \
        xfce4-taskmanager \
        xauth xinit dbus-x11 \
        thunar-vcs-plugin \
        mousepad \
        vim \
        p7zip p7zip-rar \
        thunar-archive-plugin \
        xarchiver \
        gvfs-backends \
        gigolo && \
    { apt-get purge -y pm-utils 'xscreensaver*' || true ; } && \
    { apt-get remove -y app-install-data gnome-user-guide || true ; } && \
    # Fail the build loudly if any VNC-critical binary is missing, so a broken
    # apt state can never again produce an image that silently lacks xauth.
    command -v xauth >/dev/null 2>&1 && \
    command -v xinit >/dev/null 2>&1 && \
    command -v dbus-launch >/dev/null 2>&1 && \
    command -v startxfce4 >/dev/null 2>&1 && \
    clean-layer.sh

# TigerVNC + noVNC + websockify (VNC web desktop on 6901, raw VNC on 5901)
RUN \
    apt-get update && \
    cd ${RESOURCES_PATH} && \
    wget -qO- https://sourceforge.net/projects/tigervnc/files/stable/1.12.0/tigervnc-1.12.0.x86_64.tar.gz/download | tar xz --strip 1 -C / && \
    mkdir -p ./novnc/utils/websockify && \
    wget -qO- https://github.com/novnc/noVNC/archive/v1.3.0.tar.gz | tar xz --strip 1 -C ./novnc && \
    wget -qO- https://github.com/novnc/websockify/archive/v0.10.0.tar.gz | tar xz --strip 1 -C ./novnc/utils/websockify && \
    mkdir -p $HOME/.vnc && \
    fix-permissions.sh ${RESOURCES_PATH} && \
    clean-layer.sh

# Chromium — the open-source Google Chrome. Ported from the torch-2.1 branch,
# which installed `chromium-browser` from ppa:saiarcot895/chromium-beta on
# Ubuntu 20.04. That PPA is stale (last release targets kinetic, no noble
# builds), and noble's official `chromium-browser` is only a snap stub (snap
# does not work inside Docker). ppa:xtradeb/apps is the maintained successor
# that ships the latest real .deb chromium builds for Ubuntu 24.04 (noble).
RUN \
    add-apt-repository -y ppa:xtradeb/apps && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        chromium \
        chromium-l10n && \
    ln -sf /usr/bin/chromium /usr/bin/google-chrome && \
    # Container-safe Chromium flags. Chromium's default sandbox cannot run inside
    # Docker (no user namespaces / setuid sandbox), so it crashes on startup.
    # The Ubuntu chromium launcher script sources every file in /etc/chromium.d/,
    # so dropping flags there is the official, upgrade-proof mechanism — it also
    # covers the google-chrome symlink and any wrapper invocation (e.g. ZCode's
    # built-in browser).
    printf '%s\n' \
        '# Disable the sandbox and GPU acceleration inside the container.' \
        'export CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --no-sandbox --disable-gpu --disable-dev-shm-usage"' \
        > /etc/chromium.d/99-container-flags && \
    # Fail the build loudly if the browser binary is missing.
    command -v chromium >/dev/null 2>&1 && \
    clean-layer.sh

# PyCharm Community — install script taken verbatim from the torch-2.1 branch
# (resources/tools/pycharm.sh), including its pinned version 2022.2.2.
# Downloads the official JetBrains tarball into /opt/pycharm, symlinks
# `pycharm-community` onto PATH and adds an XFCE desktop entry.
# NOTE: amd64 only — JetBrains did not publish an ARM64 Linux tarball for
# PyCharm Community before 2022.3.
COPY resources/tools/pycharm.sh $RESOURCES_PATH/tools/pycharm.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/pycharm.sh && \
    # Fail the build loudly if the launcher is missing.
    command -v pycharm-community >/dev/null 2>&1 && \
    clean-layer.sh

# ZCode (Electron IDE) — installed from the official .deb by
# resources/tools/zcode.sh, same pattern as the PyCharm block above.
# The script also replaces the Electron binary with a --no-sandbox wrapper:
# this container's runtime forbids user namespaces even for root, so the
# chrome-sandbox cannot work under any configuration (verified: the setuid
# root workaround is blocked by the kernel too). Without the wrapper the
# app crashes on startup; with it the GUI runs stably. The wrapper also
# raises the fd limit to 65535 (fixes startup EMFILE errors).
# A desktop shortcut is created at ~/Desktop/zcode.desktop for the VNC session.
# NOTE: amd64 only — the official .deb ships linux-x64 builds exclusively.
COPY resources/tools/zcode.sh $RESOURCES_PATH/tools/zcode.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/zcode.sh && \
    # Fail the build loudly if the launcher is missing.
    command -v zcode >/dev/null 2>&1 && \
    clean-layer.sh

### END GUI TOOLS ###

### PYTHON PACKAGES ###

# GPU runtime helpers + ONNX. gpustat needs nvidia-ml-py (already in the NGC base as
# 12.570.86); do NOT install nvidia-ml-py3 (an old fork that conflicts with it).
# torchaudio 2.7.0 matches the NGC torch 2.7.0a0 and MUST be installed with
# --no-deps: its PyPI metadata depends on torch==2.7.0, and letting pip resolve
# that would replace the NGC-optimized torch build with a stock PyPI wheel
# (which dropped sm_70, breaking V100). Note the stock torchaudio wheel itself
# also only ships sm_75+ CUDA kernels — torchaudio ops without a V100 kernel
# will fail on sm_70; the common paths (load/save/resample via sox/soundfile
# backends) are unaffected.
RUN \
    pip install --no-cache-dir setuptools_scm wheel && \
    pip install --no-cache-dir --no-deps torchaudio==2.7.0+cu128 -i https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir --no-build-isolation \
        onnxruntime-gpu==1.20.2 \
        onnx \
        gpustat==1.1.1 && \
    clean-layer.sh

# Core ML + utility requirements (Python 3.12 compatible). No zsh tooling.
# The browser-based editor is OpenVSCode Server (installed in its own Dockerfile block),
# not Jupyter. Installed without version pins (use NGC versions where present) and without --upgrade,
# so the NGC torch/numpy stack is preserved. NOTE: flask is intentionally omitted — it
# requires blinker>=1.9 but the NGC image's debian-installed blinker 1.7.0 has no pip
# RECORD file and cannot be upgraded/uninstalled. fastapi+uvicorn cover web serving.
COPY resources/libraries ${RESOURCES_PATH}/libraries
RUN \
    pip install --no-cache-dir -r ${RESOURCES_PATH}/libraries/requirements-minimal.txt && \
    clean-layer.sh

### END PYTHON PACKAGES ###

### INPUT METHOD (Sogou Pinyin via fcitx) ###

COPY resources/sogoupinyin_4.2.1.145_amd64.deb $RESOURCES_PATH/

# fcitx 4 + Sogou Pinyin. The official .deb targets older Ubuntu releases but runs
# on 24.04 when the fcitx stack and the Qt5/QML libraries it needs are present.
# We install fcitx and its frontends explicitly because Ubuntu 24.04's metapackage
# with --no-install-recommends no longer pulls in the UI and GTK/Qt frontends,
# which makes the IME fail to start.
RUN \
    apt-get update && \
    # Sogou Pinyin 4.2.1's candidate-box service links against Qt5Svg and Xss;
    # without them it silently fails to start, so install those runtime libs here.
    apt-get install -y --no-install-recommends \
        fcitx \
        fcitx-bin \
        fcitx-data \
        fcitx-libs \
        fcitx-ui-classic \
        fcitx-module-dbus \
        fcitx-module-kimpanel \
        fcitx-module-x11 \
        fcitx-frontend-gtk2 \
        fcitx-frontend-gtk3 \
        fcitx-frontend-qt5 \
        fcitx-config-gtk \
        gdebi \
        im-config \
        lsb-release \
        x11-utils \
        libxtst6 \
        libqt5qml5 \
        libqt5quick5 \
        libqt5quickwidgets5 \
        qml-module-qtquick2 \
        libgsettings-qt1 \
        libqt5svg5 \
        libxss1 \
        fonts-droid-fallback \
        humanity-icon-theme \
        # gdk-pixbuf SVG loader. Humanity's icons (all the XFCE Applications-menu
        # category icons, many app/panel icons) are SVG-only; without
        # librsvg2-common GTK cannot render ANY svg icon and shows the
        # "broken image" placeholder instead (empty menu icons).
        librsvg2-common && \
    clean-layer.sh

# Install Sogou Pinyin .deb and select fcitx as the default input method. The
# package ships /etc/xdg/autostart desktop files for its service and watchdog;
# make sure the fcitx input method itself also autostarts in the XFCE/VNC session.
RUN \
    gdebi -n $RESOURCES_PATH/sogoupinyin_4.2.1.145_amd64.deb && \
    im-config -n fcitx && \
    (cp /usr/share/applications/fcitx.desktop /etc/xdg/autostart/fcitx.desktop || true) && \
    # Disable Sogou's own xdg-autostart entries: they race fcitx (the service
    # starts before fcitx is on the session bus, then exits silently and the
    # candidate box never appears). supervisord manages the service instead
    # (resources/supervisor/programs/sogoupinyin.conf), with autorestart.
    for f in /etc/xdg/autostart/sogoupinyin-service.desktop \
             /etc/xdg/autostart/sogoupinyin-watchdog.desktop; do \
        [ -f "$f" ] && printf '\nHidden=true\n' >> "$f"; \
    done && \
    # Fail the build if Sogou's candidate-box service still has missing .so
    # dependencies, instead of discovering it at runtime inside the container.
    if ldd /opt/sogoupinyin/files/bin/sogoupinyin-service | grep -q "not found"; then \
        echo "ERROR: sogoupinyin-service has unmet library dependencies:"; \
        ldd /opt/sogoupinyin/files/bin/sogoupinyin-service | grep "not found"; \
        exit 1; \
    fi && \
    clean-layer.sh

### END INPUT METHOD ###


### OPENVSCODE SERVER ###

# OpenVSCode Server (VS Code in the browser,
# https://github.com/gitpod-io/openvscode-server) on port 8090 (non-privileged,
# since supervisord runs as the non-root `ml` user). Installed after the
# input-method block so the desktop/IME stack is already present.
#
# We download the official release tarball from GitHub (not the old
# code-server.dev installer) and extract it under /opt/openvscode-server, then
# symlink the CLI entry point (bin/openvscode-server) onto PATH. The asset
# suffix maps Docker's TARGETARCH (arm64 / amd64) to the release naming
# (linux-arm64 / linux-x64). Pinning OPENVSCODE_VERSION makes future upgrades a
# one-line change; bumping it pulls a newer VS Code base.
#
# Auth reuses the existing VNC_PW env var as the connection token (see
# start-openvscode-server.sh); the workspace root is /workspace (matches the
# Desktop/workspace symlink).
ARG OPENVSCODE_VERSION=1.109.5
ARG TARGETARCH
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) asset_arch=arm64 ;; \
        amd64) asset_arch=x64 ;; \
        *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    asset="openvscode-server-v${OPENVSCODE_VERSION}-linux-${asset_arch}.tar.gz"; \
    curl -fsSL -o "/tmp/${asset}" \
        "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v${OPENVSCODE_VERSION}/${asset}"; \
    mkdir -p /opt/openvscode-server; \
    tar xzf "/tmp/${asset}" -C /opt/openvscode-server --strip-components=1; \
    rm -f "/tmp/${asset}"; \
    ln -sf /opt/openvscode-server/bin/openvscode-server /usr/local/bin/openvscode-server; \
    # Fail the build loudly if the binary is missing instead of discovering it
    # at runtime inside the container.
    command -v openvscode-server >/dev/null 2>&1; \
    clean-layer.sh

### END OPENVSCODE SERVER ###


### CONFIGURATION ###

# Copy resources into the image
COPY ["resources/", "$RESOURCES_PATH/"]

# Home folder (bashrc with colored prompt + aliases)
COPY resources/home/ $HOME/

# SSH configs
COPY resources/ssh/ssh_config resources/ssh/sshd_config  /etc/ssh/

# xrdp config (optional, not auto-started)
COPY resources/config/xrdp.ini /etc/xrdp/xrdp.ini

# Supervisor config
COPY resources/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY resources/supervisor/programs/ /etc/supervisor/conf.d/

# Assume yes for apt
COPY resources/config/90assumeyes /etc/apt/apt.conf.d/

# Branding / misc setup
RUN \
    ln -s $RESOURCES_PATH/novnc/vnc.html $RESOURCES_PATH/novnc/index.html && \
    git config --global core.fileMode false && \
    git config --global http.sslVerify false && \
    git config --global credential.helper 'cache --timeout=31540000' && \
    MPLBACKEND=Agg python -c "import matplotlib.pyplot" 2>/dev/null || true && \
    sed -i 's/xfce4-session-logout/killall python/g' /usr/share/applications/xfce4-session-logout.desktop 2>/dev/null || true && \
    touch /root/.ssh/config && \
    chmod -R a+rwx $WORKSPACE_HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
    chmod -R a+rwx /usr/share/applications/ && \
    mkdir -p $HOME/Desktop && \
    ln -s $WORKSPACE_HOME $HOME/Desktop/workspace && \
    chown $NB_USER:$NB_USER /tmp && \
    chmod 1777 /tmp && \
    chmod a+rwx /tmp && \
    chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo

# MKL / OpenMP / VNC defaults
ENV KMP_DUPLICATE_LIB_OK="True" \
    KMP_AFFINITY="granularity=fine,compact,1,0" \
    KMP_BLOCKTIME=0 \
    MKL_THREADING_LAYER=GNU \
    ENABLE_IPC=1 \
    PYTHON_PRETTY_ERRORS_ISATTY_ONLY=1 \
    HDF5_USE_FILE_LOCKING=False \
    VNC_PW=vncpassword \
    VNC_RESOLUTION=1600x900 \
    VNC_COL_DEPTH=24 \
    CONFIG_BACKUP_ENABLED="true" \
    SHUTDOWN_INACTIVE_KERNELS="false" \
    SHARED_LINKS_ENABLED="true" \
    DATA_ENVIRONMENT=$WORKSPACE_HOME"/environment" \
    WORKSPACE_BASE_URL="/" \
    WORKSPACE_PORT="8080" \
    # OpenVSCode Server (VS Code in the browser) listens on its own port,
    # independent of the 8080 oneport muxer. Must be >= 1024: supervisord runs
    # as the non-root `ml` user and cannot bind privileged ports or setuid to
    # root. Default 8090; overridable at runtime.
    CS_PORT="8090" \
    # Token toggle for OpenVSCode Server. Default true: the VNC_PW value is used
    # as the connection token (browse to http://host:8090/?tkn=<VNC_PW>). Set to
    # false to run without a token (--without-connection-token) when the port is
    # already isolated at the network level. (Named ..._TOKEN, not ..._AUTH, to
    # avoid the buildkit SecretsUsedInArgOrEnv lint that keys off "auth".)
    CS_REQUIRE_TOKEN="true" \
    SHELL="/bin/bash" \
    MAX_NUM_THREADS="auto"

### END CONFIGURATION ###

ARG ARG_BUILD_DATE="unknown" \
    ARG_VCS_REF="unknown" \
    ARG_WORKSPACE_VERSION="unknown"
ENV WORKSPACE_VERSION=$ARG_WORKSPACE_VERSION

USER $NB_USER

### OPENVSCODE SERVER EXTENSIONS ###

# Pre-install a default set of VS Code extensions into OpenVSCode Server so
# they are available on first launch. OpenVSCode Server resolves these from the
# Open VSX registry (https://open-vsx.org), which all of the IDs below are
# published to. Installed as the `ml` user into the extensions dir under
# ~/.local/share/openvscode-server/extensions; the launcher passes
# --extensions-dir with the same path so they load at runtime.
#
# Why the sudo chown/chmod up front: at this point in the build the later
# `sudo chmod 777 $HOME -R` step has NOT run yet. The `COPY resources/home/`
# step above drops files as root:root, and various prior RUNs leave /home/ml
# owned by root or without write bits for `ml`. Without fixing ownership here,
# OpenVSCode Server fails with "EACCES: permission denied, mkdir". We normalize
# ownership of the whole home dir, create the extensions dir, then install.
# Failures here MUST abort the build (an earlier version swallowed errors and
# produced an image with no extensions, discovered only at runtime).
ENV OPENVSCODE_EXTENSIONS_DIR=/home/ml/.local/share/openvscode-server/extensions
RUN sudo chown -R $NB_USER:$NB_USER /home/$NB_USER && \
    sudo chmod -R u+rwX /home/$NB_USER && \
    mkdir -p "$OPENVSCODE_EXTENSIONS_DIR" && \
    for ext in \
        mhutchie.git-graph \
        ms-python.python \
    ; do \
        echo "Installing OpenVSCode Server extension: $ext"; \
        openvscode-server --extensions-dir "$OPENVSCODE_EXTENSIONS_DIR" --install-extension "$ext"; \
    done

### END OPENVSCODE SERVER EXTENSIONS ###

RUN \
    sudo chmod 777 $HOME/ -R && \
    sudo chown ml:ml $HOME/ -R && \
    sudo chown root:crontab /usr/bin/crontab 2>/dev/null || true && \
    sudo chmod 2755 /usr/bin/crontab 2>/dev/null || true && \
    sudo chmod 777 /var/log/supervisor/ -R && \
    sudo chmod 777 /var/run -R && \
    sudo chmod 400 /var/run/sshd && \
    sudo chmod 777 /var/log -R

# tini kills the full process group
ENTRYPOINT ["/tini", "-g", "--"]
CMD ["python", "/resources/docker-entrypoint.py"]

# Port 8080 is the main access port (HTTP to VNC desktop + SSH, muxed by oneport)
# Port 8090 is OpenVSCode Server (VS Code in the browser), served independently.
# Port 5901 is the raw VNC port, 3389 is the optional RDP port.
EXPOSE 8080 8090
