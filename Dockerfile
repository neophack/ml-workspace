# Slim ML workspace — single-port (8080) VNC desktop + SSH appliance.
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
# ttf-wqy-zenhei -> fonts-wqy-zenhei (renamed), chromium (PPA stale on noble, not needed for a
# VNC+SSH server), node/npm/typescript toolchain, pyenv, sdkman.
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
RUN \
    set -e && \
    chmod g+rw /home && mkdir -p $HOME && \
    useradd -d $HOME -s /bin/bash -G sudo $NB_USER && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    chown -R $NB_USER.$NB_USER /home/$NB_USER

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

# xfce4 desktop + lightweight editors / file tools (no browser — SSH/VNC server use case)
RUN \
    add-apt-repository -y ppa:xubuntu-dev/staging && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        xfce4 \
        gconf2 \
        xfce4-terminal \
        xfce4-clipman \
        xterm \
        xfce4-taskmanager \
        xauth xinit dbus-x11 \
        thunar-vcs-plugin \
        mousepad \
        vim \
        htop \
        p7zip p7zip-rar \
        thunar-archive-plugin \
        xarchiver \
        gvfs-backends \
        gigolo && \
    apt-get purge -y pm-utils xscreensaver* && \
    apt-get remove -y app-install-data gnome-user-guide 2>/dev/null || true && \
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

### END GUI TOOLS ###


### INPUT METHOD (Baidu Pinyin via fcitx) ###

COPY resources/fcitx-baidupinyin_1.0.1.0_amd64.deb $RESOURCES_PATH/

# fcitx 4 + Baidu Pinyin. Qt5 runtime libs satisfy the deb's dependencies.
# Note: qt5-default was dropped from Ubuntu (>=21.04) and is not needed (no qmake step here).
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        fcitx \
        fcitx-bin \
        gdebi \
        im-config \
        libgsettings-qt-dev \
        libqt5qml5 \
        libqt5quick5 \
        libqt5quickwidgets5 \
        qml-module-qtquick2 \
        libxss-dev \
        eog && \
    gdebi -n $RESOURCES_PATH/fcitx-baidupinyin_1.0.1.0_amd64.deb && \
    im-config -n fcitx && \
    clean-layer.sh

### END INPUT METHOD ###


### PYTHON PACKAGES ###

# GPU runtime helpers + ONNX
RUN \
    pip install --no-cache-dir setuptools_scm wheel && \
    pip install --no-cache-dir --no-build-isolation \
        onnxruntime-gpu==1.20.2 \
        onnx \
        gpustat==1.1.1 \
        nvidia-ml-py3 && \
    clean-layer.sh

# Core ML + utility requirements (Python 3.12 compatible). No Jupyter, no zsh tooling.
# Installed WITHOUT version pins for packages already in the NGC base, and WITHOUT
# --upgrade, so the NGC torch/numpy/nvidia-* stack is left untouched (pip only installs
# what's genuinely missing). This avoids ResolutionImpossible conflicts.
COPY resources/libraries ${RESOURCES_PATH}/libraries
RUN \
    pip install --no-cache-dir -r ${RESOURCES_PATH}/libraries/requirements-minimal.txt && \
    clean-layer.sh

### END PYTHON PACKAGES ###


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
    INCLUDE_TUTORIALS="true" \
    WORKSPACE_PORT="8080" \
    SHELL="/bin/bash" \
    MAX_NUM_THREADS="auto"

### END CONFIGURATION ###

ARG ARG_BUILD_DATE="unknown" \
    ARG_VCS_REF="unknown" \
    ARG_WORKSPACE_VERSION="unknown"
ENV WORKSPACE_VERSION=$ARG_WORKSPACE_VERSION

USER $NB_USER

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
# Port 5901 is the raw VNC port, 3389 is the optional RDP port.
EXPOSE 8080
