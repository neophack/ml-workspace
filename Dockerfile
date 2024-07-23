# Ubuntu 20.04 including Python 3.8
# NVIDIA CUDA® 12.1.0
# NVIDIA cuBLAS 12.1.3
# NVIDIA cuDNN 8.9.0
# NVIDIA NCCL 2.17.1
# NVIDIA RAPIDS™ 23.02
# Apex
# rdma-core 36.0
# NVIDIA HPC-X 2.13
# OpenMPI 4.1.4+
# GDRCopy 2.3
# TensorBoard 2.9.0
# Nsight Compute 2023.1.0.15
# Nsight Systems 2023.1.1.127
# NVIDIA TensorRT™ 8.6.1
# Torch-TensorRT 1.4.0.dev0
# NVIDIA DALI® 1.23.0
# MAGMA 2.6.2
# JupyterLab 2.3.2 including Jupyter-TensorBoard
# TransformerEngine 0.7
# PyTorch quantization wheel 2.1.2

FROM nvcr.io/nvidia/pytorch:23.04-py3

USER root

### BASICS ###
# Technical Environment Variables

ENV \
    SHELL="/bin/bash" \
    # Nobteook server user: https://github.com/jupyter/docker-stacks/blob/master/base-notebook/Dockerfile#L33
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
    TZ="Asia/Shanghai"

WORKDIR $HOME

# replace source
# RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && \
#     echo "deb https://mirrors.ustc.edu.cn/ubuntu/ focal main restricted universe multiverse" > /etc/apt/sources.list && \
#     echo "deb https://mirrors.ustc.edu.cn/ubuntu/ focal-security main restricted universe multiverse" >> /etc/apt/sources.list && \
#     echo "deb https://mirrors.ustc.edu.cn/ubuntu/ focal-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
#     echo "deb https://mirrors.ustc.edu.cn/ubuntu/ focal-backports main restricted universe multiverse" >> /etc/apt/sources.list 

# Make folders
RUN \
    mkdir $RESOURCES_PATH && chmod a+rwx $RESOURCES_PATH && \
    # mkdir $WORKSPACE_HOME && chmod a+rwx $WORKSPACE_HOME && \
    mkdir $SSL_RESOURCES_PATH && chmod a+rwx $SSL_RESOURCES_PATH

# Layer cleanup script
COPY resources/scripts/clean-layer.sh  /usr/bin/clean-layer.sh
COPY resources/scripts/fix-permissions.sh  /usr/bin/fix-permissions.sh

 # Make clean-layer and fix-permissions executable
 RUN \
    chmod a+rwx /usr/bin/clean-layer.sh && \
    chmod a+rwx /usr/bin/fix-permissions.sh

# Generate and Set locals
# https://stackoverflow.com/questions/28405902/how-to-set-the-locale-inside-a-debian-ubuntu-docker-container#38553499
RUN \
    apt-get update && \
    apt-get install -y locales && \
    # install locales-all?
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8 && \
    # Cleanup
    clean-layer.sh

ENV LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en"

# Install basics
RUN \
    # TODO add repos?
    # add-apt-repository ppa:apt-fast/stable
    # add-apt-repository 'deb http://security.ubuntu.com/ubuntu xenial-security main'
    apt-get update --fix-missing && \
    apt-get install -y sudo apt-utils && \
    apt-get upgrade -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        # This is necessary for apt to access HTTPS sources:
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
        dpkg-sig \
        uuid-dev \
        csh \
        xclip \
        clinfo \
        time \
        libssl-dev \
        libgdbm-dev \
        libncurses5-dev \
        libncursesw5-dev \
        # required by pyenv
        libreadline-dev \
        libedit-dev \
        xz-utils \
        gawk \
        # Simplified Wrapper and Interface Generator (5.8MB) - required by lots of py-libs
        swig \
        # Graphviz (graph visualization software) (4MB)
        graphviz libgraphviz-dev \
        # Terminal multiplexer
        screen \
        # Editor
        nano \
        # Find files
        locate \
        # Dev Tools
        sqlite3 \
        # XML Utils
        xmlstarlet \
        # GNU parallel
        parallel \
        #  R*-tree implementation - Required for earthpy, geoviews (3MB)
        libspatialindex-dev \
        # Search text and binary files
        yara \
        # Minimalistic C client for Redis
        libhiredis-dev \
        # postgresql client
        libpq-dev \
        # mysql client (10MB)
        libmysqlclient-dev \
        # mariadb client (7MB)
        # libmariadbclient-dev \
        # image processing library (6MB), required for tesseract
        libleptonica-dev \
        # GEOS library (3MB)
        libgeos-dev \
        # style sheet preprocessor
        less \
        # Print dir tree
        tree \
        # Bash autocompletion functionality
        bash-completion \
        # ping support
        iputils-ping \
        # Map remote ports to localhosM
        socat \
        # Json Processor
        jq \
        rsync \
        # sqlite3 driver - required for pyenv
        libsqlite3-dev \
        # VCS:
        git \
        subversion \
        jed \
        # odbc drivers
        unixodbc unixodbc-dev \
        # Image support
        libtiff-dev \
        libjpeg-dev \
        libpng-dev \
        libglib2.0-0 \
        libxext6 \
        libsm6 \
        libxext-dev \
        libxrender1 \
        libzmq3-dev \
        # protobuffer support
        protobuf-compiler \
        libprotobuf-dev \
        libprotoc-dev \
        autoconf \
        automake \
        libtool \
        cmake  \
        fonts-liberation \
        google-perftools \
        # Compression Libs
        # also install rar/unrar? but both are propriatory or unar (40MB)
        zip \
        gzip \
        unzip \
        bzip2 \
        lzop \
	    # deprecates bsdtar (https://ubuntu.pkgs.org/20.04/ubuntu-universe-i386/libarchive-tools_3.4.0-2ubuntu1_i386.deb.html)
        libarchive-tools \
        zlibc \
        # unpack (almost) everything with one command
        unp \
        libbz2-dev \
        liblzma-dev \
        fonts-wqy-microhei \
        ttf-wqy-zenhei \
        gdb \
        gosu \
        zlib1g-dev && \
    # Update git to newest version
    add-apt-repository -y ppa:git-core/ppa  && \
    apt-get update && \
    apt-get install -y --no-install-recommends git && \
    # Fix all execution permissions
    chmod -R a+rwx /usr/local/bin/ && \
    # configure dynamic linker run-time bindings
    ldconfig && \
    # Fix permissions
    fix-permissions.sh $HOME && \
    # Cleanup
    clean-layer.sh

# user
RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    && set -x \
# change user to non-root (http://pjdietz.com/2016/08/28/nginx-in-docker-without-root.html):
    # && mv $PROJECTOR_DIR/$NB_USER /home \
    && chmod g+rw /home && mkdir -p $HOME \
    && useradd -d $HOME -s /bin/bash -G sudo $NB_USER \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && chown -R $NB_USER.$NB_USER /home/$NB_USER 

# Add tini
RUN wget --no-verbose https://github.com/krallin/tini/releases/download/v0.19.0/tini -O /tini && \
    chmod +x /tini && \
    # prepare ssh for inter-container communication for remote python kernel
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server \
        # SSLH for SSH + HTTP(s) Multiplexing
        sslh \
        # SSH Tooling
        autossh \
        mussh && \
    chmod go-w /root && \
    mkdir -p /root/.ssh/ && \
    # create empty config file if not exists
    touch /root/.ssh/config  && \
    sudo chown -R $NB_USER:users /root/.ssh && \
    chmod 700 /root/.ssh && \
    printenv >> /root/.ssh/environment && \
    chmod -R a+rwx /usr/local/bin/ && \
    # Fix permissions
    fix-permissions.sh $HOME && \
    # openrest install
    OPEN_RESTY_VERSION="1.19.9.1" && \
    mkdir $RESOURCES_PATH"/openresty" && \
    cd $RESOURCES_PATH"/openresty" && \
    apt-get update && \
    apt-get purge -y nginx nginx-common && \
    # libpcre required, otherwise you get a 'the HTTP rewrite module requires the PCRE library' error
    # Install apache2-utils to generate user:password file for nginx.
    apt-get install -y libssl-dev libpcre3 libpcre3-dev apache2-utils && \
    wget --no-verbose https://openresty.org/download/openresty-$OPEN_RESTY_VERSION.tar.gz  -O ./openresty.tar.gz && \
    tar xfz ./openresty.tar.gz && \
    rm ./openresty.tar.gz && \
    cd ./openresty-$OPEN_RESTY_VERSION/ && \
    # Surpress output - if there is a problem remove  > /dev/null
    ./configure --with-http_stub_status_module --with-http_sub_module > /dev/null && \
    make -j2 > /dev/null && \
    make install > /dev/null && \
    # create log dir and file - otherwise openresty will throw an error
    mkdir -p /var/log/nginx/ && \
    touch /var/log/nginx/upstream.log && \
    cd $RESOURCES_PATH && \
    rm -r $RESOURCES_PATH"/openresty" && \
    # Fix permissions
    chmod -R a+rwx $RESOURCES_PATH && \
    # Cleanup
    clean-layer.sh

ENV PATH=/usr/local/openresty/nginx/sbin:$PATH

COPY resources/nginx/lua-extensions /etc/nginx/nginx_plugins

### END BASICS ###

### RUNTIMES ###
# Install Miniconda: https://repo.continuum.io/miniconda/

# ENV \
#     # TODO: CONDA_DIR is deprecated and should be removed in the future
#     CONDA_DIR=/opt/conda \
#     CONDA_ROOT=/opt/conda \
#     PYTHON_VERSION="3.9.10" \
#     CONDA_PYTHON_DIR=/opt/conda/lib/python3.9 \
#     MINICONDA_VERSION=4.10.3 \
#     MINICONDA_MD5=8c69f65a4ae27fb41df0fe552b4a8a3b \
#     CONDA_VERSION=4.10.3

# RUN wget --no-verbose https://repo.anaconda.com/miniconda/Miniconda3-py39_${CONDA_VERSION}-Linux-x86_64.sh -O ~/miniconda.sh && \
#     echo "${MINICONDA_MD5} *miniconda.sh" | md5sum -c - && \
#     /bin/bash ~/miniconda.sh -b -p $CONDA_ROOT && \
#     export PATH=$CONDA_ROOT/bin:$PATH && \
#     rm ~/miniconda.sh && \
#     # Configure conda
#     # TODO: Add conde-forge as main channel -> remove if testted
#     # TODO, use condarc file
#     $CONDA_ROOT/bin/conda config --system --add channels conda-forge && \
#     $CONDA_ROOT/bin/conda config --system --set auto_update_conda False && \
#     $CONDA_ROOT/bin/conda config --system --set show_channel_urls True && \
#     $CONDA_ROOT/bin/conda config --system --set channel_priority strict && \
#     # Deactivate pip interoperability (currently default), otherwise conda tries to uninstall pip packages
#     $CONDA_ROOT/bin/conda config --system --set pip_interop_enabled false && \
#     # Update conda
#     $CONDA_ROOT/bin/conda update -y -n base -c defaults conda && \
#     $CONDA_ROOT/bin/conda update -y setuptools && \
#     $CONDA_ROOT/bin/conda install -y conda-build && \
#     # Update selected packages - install python 3.8.x
#     $CONDA_ROOT/bin/conda install -y --update-all python=$PYTHON_VERSION && \
#     # Link Conda
#     ln -s $CONDA_ROOT/bin/python /usr/local/bin/python && \
#     ln -s $CONDA_ROOT/bin/conda /usr/bin/conda && \
#     # Update
#     $CONDA_ROOT/bin/conda install -y pip && \
#     $CONDA_ROOT/bin/pip install --upgrade pip && \
#     chmod -R a+rwx /usr/local/bin/ && \
#     # Cleanup - Remove all here since conda is not in path as of now
#     # find /opt/conda/ -follow -type f -name '*.a' -delete && \
#     # find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
#     $CONDA_ROOT/bin/conda clean -y --packages && \
#     $CONDA_ROOT/bin/conda clean -y -a -f  && \
#     $CONDA_ROOT/bin/conda build purge-all && \
#     # Fix permissions
#     fix-permissions.sh $CONDA_ROOT && \
#     clean-layer.sh

# ENV PATH=$CONDA_ROOT/bin:$PATH

# # There is nothing added yet to LD_LIBRARY_PATH, so we can overwrite
# ENV LD_LIBRARY_PATH=$CONDA_ROOT/lib

# Install pyenv to allow dynamic creation of python versions
RUN git clone https://github.com/pyenv/pyenv.git $HOME/.pyenv && \
    # Install pyenv plugins based on pyenv installer
    git clone https://github.com/pyenv/pyenv-virtualenv.git $HOME/.pyenv/plugins/pyenv-virtualenv  && \
    git clone https://github.com/pyenv/pyenv-doctor.git $HOME/.pyenv/plugins/pyenv-doctor && \
    git clone https://github.com/pyenv/pyenv-update.git $HOME/.pyenv/plugins/pyenv-update && \
    git clone https://github.com/pyenv/pyenv-which-ext.git $HOME/.pyenv/plugins/pyenv-which-ext && \
    apt-get update && \
    # TODO: lib might contain high vulnerability
    # Required by pyenv
    apt-get install -y --no-install-recommends libffi-dev && \
    # Install pipx
    pip install pipx && \
    # Configure pipx
    python -m pipx ensurepath && \
    # Install node.js
    apt-get update && \
    # https://nodejs.org/en/about/releases/ use even numbered releases, i.e. LTS versions
    curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash - && \
    apt-get install -y nodejs && \
    # As conda is first in path, the commands 'node' and 'npm' reference to the version of conda.
    # Replace those versions with the newly installed versions of node
    # rm -f /opt/conda/bin/node && ln -s /usr/bin/node /opt/conda/bin/node && \
    # rm -f /opt/conda/bin/npm && ln -s /usr/bin/npm /opt/conda/bin/npm && \
    # Fix permissions
    chmod a+rwx /usr/bin/node && \
    chmod a+rwx /usr/bin/npm && \
    # Fix node versions - put into own dir and before conda:
    mkdir -p /opt/node/bin && \
    ln -s /usr/bin/node /opt/node/bin/node && \
    ln -s /usr/bin/npm /opt/node/bin/npm && \
    # Update npm
    /usr/bin/npm install -g npm && \
    # Install Yarn
    /usr/bin/npm install -g yarn && \
    # Install typescript
    /usr/bin/npm install -g typescript && \
    # Install webpack - 32 MB
    /usr/bin/npm install -g webpack && \
    # Install node-gyp
    /usr/bin/npm install -g node-gyp && \
    # Update all packages to latest version
    /usr/bin/npm update -g && \
    # Install supervisor for process supervision
    mkdir -p /var/run/sshd && chmod 400 /var/run/sshd && \
    # Install rsyslog for syslog logging
    apt-get install -y --no-install-recommends rsyslog && \
    apt-get install -y --no-install-recommends python3-venv && \
    pipx install supervisor && \
    pipx inject supervisor supervisor-stdout && \
    # supervisor needs this logging path
    mkdir -p /var/log/supervisor/ && \
    # Cleanup
    clean-layer.sh

# Add pyenv pythonbin and others to path 
ENV PATH=/opt/node/bin:$HOME/.local/bin:$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH \
    PYENV_ROOT=$HOME/.pyenv \
    CONDA_PYTHON_DIR=/usr/local/lib/python3.8 \
    OPENP2P_TOKEN="5971464605690461497" \
    # Add the defaults from /lib/x86_64-linux-gnu, otherwise lots of no version errors
    # cannot be added above otherwise there are errors in the installation of the gui tools
    # Call order: https://unix.stackexchange.com/questions/367600/what-is-the-order-that-linuxs-dynamic-linker-searches-paths-in
    LD_LIBRARY_PATH=/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu 

# Java - removed

### END RUNTIMES ###


### GUI TOOLS ###

# Install xfce4 & gui tools
RUN \
    # Use staging channel to get newest xfce4 version (4.16)
    add-apt-repository -y ppa:xubuntu-dev/staging && \
    apt-get update && \
    apt-get install -y --no-install-recommends xfce4 && \
    apt-get install -y --no-install-recommends gconf2 && \
    apt-get install -y --no-install-recommends xfce4-terminal && \
    apt-get install -y --no-install-recommends xfce4-clipman && \
    apt-get install -y --no-install-recommends xterm && \
    apt-get install -y --no-install-recommends --allow-unauthenticated xfce4-taskmanager  && \
    # Install dependencies to enable vncserver
    apt-get install -y --no-install-recommends xauth xinit dbus-x11 && \
    # Install gdebi deb installer
    apt-get install -y --no-install-recommends gdebi && \
    # Search for files
    apt-get install -y --no-install-recommends catfish && \
    apt-get install -y --no-install-recommends font-manager && \
    # vs support for thunar
    apt-get install -y thunar-vcs-plugin && \
    # Streaming text editor for large files - klogg is alternative to glogg
    apt-get install -y --no-install-recommends libqt5concurrent5 libqt5widgets5 libqt5xml5 && \
    wget --no-verbose https://github.com/variar/klogg/releases/download/v20.12/klogg-20.12.0.813-Linux.deb -O $RESOURCES_PATH/klogg.deb && \
    dpkg -i $RESOURCES_PATH/klogg.deb && \
    rm $RESOURCES_PATH/klogg.deb && \
    # Disk Usage Visualizer
    apt-get install -y --no-install-recommends baobab && \
    # Lightweight text editor
    apt-get install -y --no-install-recommends mousepad && \
    apt-get install -y --no-install-recommends vim && \
    # Process monitoring
    apt-get install -y --no-install-recommends htop && \
    # Install Archive/Compression Tools: https://wiki.ubuntuusers.de/Archivmanager/
    apt-get install -y p7zip p7zip-rar && \
    apt-get install -y --no-install-recommends thunar-archive-plugin && \
    apt-get install -y xarchiver && \
    # DB Utils
    apt-get install -y --no-install-recommends sqlitebrowser && \
    # Install nautilus and support for sftp mounting
    apt-get install -y --no-install-recommends nautilus gvfs-backends && \
    # Install gigolo - Access remote systems
    apt-get install -y --no-install-recommends gigolo gvfs-bin && \
    # xfce systemload panel plugin - needs to be activated
    # apt-get install -y --no-install-recommends xfce4-systemload-plugin && \
    # Leightweight ftp client that supports sftp, http, ...
    apt-get install -y --no-install-recommends gftp && \
    # Install chrome
    # sudo add-apt-repository ppa:system76/pop
    add-apt-repository ppa:saiarcot895/chromium-beta && \
    apt-get update && \
    apt-get install -y chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg && \
    ln -s /usr/bin/chromium-browser /usr/bin/google-chrome && \
    # Cleanup
    apt-get purge -y pm-utils xscreensaver* && \
    # Large package: gnome-user-guide 50MB app-install-data 50MB
    apt-get remove -y app-install-data gnome-user-guide && \
    clean-layer.sh


#:$CONDA_ROOT/lib

# Install VNC
RUN \
    apt-get update  && \
    # required for websockify
    # apt-get install -y python-numpy  && \
    cd ${RESOURCES_PATH} && \
    # Tiger VNC
    wget -qO- https://sourceforge.net/projects/tigervnc/files/stable/1.12.0/tigervnc-1.12.0.x86_64.tar.gz/download | tar xz --strip 1 -C / && \
    # Install websockify
    mkdir -p ./novnc/utils/websockify && \
    # Before updating the noVNC version, we need to make sure that our monkey patching scripts still work!!
    wget -qO- https://github.com/novnc/noVNC/archive/v1.3.0.tar.gz | tar xz --strip 1 -C ./novnc && \
    wget -qO- https://github.com/novnc/websockify/archive/v0.10.0.tar.gz | tar xz --strip 1 -C ./novnc/utils/websockify && \
    # chmod +x -v ./novnc/utils/*.sh && \
    # create user vnc directory
    mkdir -p $HOME/.vnc && \
    # Fix permissions
    fix-permissions.sh ${RESOURCES_PATH} && \
    # Cleanup
    clean-layer.sh

# Install Web Tools - Offered via Jupyter Tooling Plugin

## VS Code Server: https://github.com/codercom/code-server
COPY resources/tools/vs-code-server.sh $RESOURCES_PATH/tools/vs-code-server.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/vs-code-server.sh --install && \
    # Cleanup
    clean-layer.sh

COPY resources/tools/pycharm.sh $RESOURCES_PATH/tools/pycharm.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/pycharm.sh && \
    # Cleanup
    clean-layer.sh

## ungit
COPY resources/tools/ungit.sh $RESOURCES_PATH/tools/ungit.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/ungit.sh --install && \
    # Cleanup
    clean-layer.sh

## netdata
# COPY resources/tools/netdata.sh $RESOURCES_PATH/tools/netdata.sh
# RUN \
#     /bin/bash $RESOURCES_PATH/tools/netdata.sh --install && \
#     # Cleanup
#     clean-layer.sh

## Glances webtool is installed in python section below via requirements.txt

## Filebrowser
COPY resources/tools/filebrowser.sh $RESOURCES_PATH/tools/filebrowser.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/filebrowser.sh --install && \
    # Cleanup
    clean-layer.sh

ARG ARG_WORKSPACE_FLAVOR="minimal"
ENV WORKSPACE_FLAVOR=$ARG_WORKSPACE_FLAVOR

# Install Visual Studio Code
COPY resources/tools/vs-code-desktop.sh $RESOURCES_PATH/tools/vs-code-desktop.sh
RUN \
    # If minimal flavor - do not install
    if [ "$WORKSPACE_FLAVOR" = "minimal" ]; then \
        exit 0 ; \
    fi && \
    /bin/bash $RESOURCES_PATH/tools/vs-code-desktop.sh --install && \
    # Cleanup
    clean-layer.sh

# Install Firefox

COPY resources/tools/firefox.sh $RESOURCES_PATH/tools/firefox.sh

RUN \
    # If minimal flavor - do not install
    if [ "$WORKSPACE_FLAVOR" = "minimal" ]; then \
        exit 0 ; \
    fi && \
    /bin/bash $RESOURCES_PATH/tools/firefox.sh --install && \
    # Cleanup
    clean-layer.sh

### END GUI TOOLS ###

### DATA SCIENCE BASICS ###



### END DATA SCIENCE BASICS ###

### JUPYTER ###

COPY \
    resources/jupyter/start.sh \
    resources/jupyter/start-notebook.sh \
    resources/jupyter/start-singleuser.sh \
    /usr/local/bin/

# Configure Jupyter / JupyterLab
# Add as jupyter system configuration
COPY resources/jupyter/nbconfig /etc/jupyter/nbconfig
COPY resources/jupyter/jupyter_notebook_config.json /etc/jupyter/

# install jupyter extensions
RUN \
    # Create empty notebook configuration
    mkdir -p $HOME/.jupyter/nbconfig/ && \
    printf "{\"load_extensions\": {}}" > $HOME/.jupyter/nbconfig/notebook.json && \
    pip --no-cache-dir install jupyter_contrib_nbextensions nbdime && \
    # Activate and configure extensions
    jupyter contrib nbextension install --sys-prefix && \
    # nbextensions configurator
    jupyter nbextensions_configurator enable --sys-prefix && \
    # Configure nbdime
    nbdime config-git --enable --global && \
    # Activate Jupytext
    jupyter nbextension enable --py jupytext --sys-prefix && \
    # Enable useful extensions
    jupyter nbextension enable skip-traceback/main --sys-prefix && \
    # jupyter nbextension enable comment-uncomment/main && \
    jupyter nbextension enable toc2/main --sys-prefix && \
    jupyter nbextension enable execute_time/ExecuteTime --sys-prefix && \
    jupyter nbextension enable collapsible_headings/main --sys-prefix && \
    jupyter nbextension enable codefolding/main --sys-prefix && \
    # Disable pydeck extension, cannot be loaded (404)
    jupyter nbextension disable pydeck/extension && \
    # Install and activate Jupyter Tensorboard
    pip install --no-cache-dir git+https://github.com/InfuseAI/jupyter_tensorboard.git && \
    jupyter tensorboard enable --sys-prefix && \
    # TODO moved to configuration files = resources/jupyter/nbconfig Edit notebook config
    # echo '{"nbext_hide_incompat": false}' > $HOME/.jupyter/nbconfig/common.json && \
    cat $HOME/.jupyter/nbconfig/notebook.json | jq '.toc2={"moveMenuLeft": false,"widenNotebook": false,"skip_h1_title": false,"sideBar": true,"number_sections": false,"collapse_to_match_collapsible_headings": true}' > tmp.$$.json && mv tmp.$$.json $HOME/.jupyter/nbconfig/notebook.json && \
    # If minimal flavor - exit here
    if [ "$WORKSPACE_FLAVOR" = "minimal" ]; then \
        # Cleanup
        clean-layer.sh && \
        exit 0 ; \
    fi && \
    # TODO: Not installed. Disable Jupyter Server Proxy
    # jupyter nbextension disable jupyter_server_proxy/tree --sys-prefix && \
    # Install jupyter black
    jupyter nbextension install https://github.com/drillan/jupyter-black/archive/master.zip --sys-prefix && \
    jupyter nbextension enable jupyter-black-master/jupyter-black --sys-prefix && \
    # If light flavor - exit here
    if [ "$WORKSPACE_FLAVOR" = "light" ]; then \
        # Cleanup
        clean-layer.sh && \
        exit 0 ; \
    fi && \
    # Install and activate what if tool
    pip install witwidget && \
    jupyter nbextension install --py --symlink --sys-prefix witwidget && \
    jupyter nbextension enable --py --sys-prefix witwidget && \
    # Activate qgrid
    jupyter nbextension enable --py --sys-prefix qgrid && \
    # TODO: Activate Colab support
    # jupyter serverextension enable --py jupyter_http_over_ws && \
    # Activate Voila Rendering
    # currently not working jupyter serverextension enable voila --sys-prefix && \
    # Enable ipclusters
    ipcluster nbextension enable && \
    # Fix permissions? fix-permissions.sh $CONDA_ROOT && \
    # Cleanup
    clean-layer.sh


# Install Jupyter Tooling Extension
COPY resources/jupyter/extensions $RESOURCES_PATH/jupyter-extensions

RUN \
    pip install --no-cache-dir $RESOURCES_PATH/jupyter-extensions/tooling-extension/ && \
    # Cleanup
    clean-layer.sh

# Install Git LFS
COPY resources/tools/git-lfs.sh $RESOURCES_PATH/tools/git-lfs.sh

RUN \
    /bin/bash $RESOURCES_PATH/tools/git-lfs.sh --install && \
    # Cleanup
    clean-layer.sh

### VSCODE ###

# Install vscode extension
# https://github.com/cdr/code-server/issues/171
# Alternative install: /usr/local/bin/code-server --user-data-dir=$HOME/.config/Code/ --extensions-dir=$HOME/.vscode/extensions/ --install-extension ms-python-release && \
RUN \
    SLEEP_TIMER=25 && \
    mkdir -p $HOME/.vscode/extensions/ && \
    # If minimal flavor -> exit here
    if [ "$WORKSPACE_FLAVOR" = "minimal" ]; then \
        exit 0 ; \
    fi && \
    cd $RESOURCES_PATH && \
    mkdir -p $HOME/.vscode/extensions/ && \
    # Install vs code jupyter - required by python extension
    VS_JUPYTER_VERSION="2023.1.2000312134" && \
    wget --retry-on-http-error=429 --waitretry 15 --tries 5 --no-verbose https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-toolsai/vsextensions/jupyter/$VS_JUPYTER_VERSION/vspackage -O ms-toolsai.jupyter-$VS_JUPYTER_VERSION.vsix && \
    bsdtar -xf ms-toolsai.jupyter-$VS_JUPYTER_VERSION.vsix extension && \
    rm ms-toolsai.jupyter-$VS_JUPYTER_VERSION.vsix && \
    mv extension $HOME/.vscode/extensions/ms-toolsai.jupyter-$VS_JUPYTER_VERSION && \
    sleep $SLEEP_TIMER && \
    # Install python extension - (newer versions are 30MB bigger)
    VS_PYTHON_VERSION="2021.12.1559732655" && \
    wget --no-verbose https://github.com/microsoft/vscode-python/releases/download/$VS_PYTHON_VERSION/ms-python-release.vsix && \
    bsdtar -xf ms-python-release.vsix extension && \
    rm ms-python-release.vsix && \
    mv extension $HOME/.vscode/extensions/ms-python.python-$VS_PYTHON_VERSION && \
    # && code-server --install-extension ms-python.python@$VS_PYTHON_VERSION \
    sleep $SLEEP_TIMER && \
    # If light flavor -> exit here
    # if [ "$WORKSPACE_FLAVOR" = "light" ]; then \
    #     exit 0 ; \
    # fi && \
    # Install prettie: https://github.com/prettier/prettier-vscode/releases
    PRETTIER_VERSION="9.1.1" && \
    wget --no-verbose https://github.com/prettier/prettier-vscode/releases/download/v$PRETTIER_VERSION/prettier-vscode-$PRETTIER_VERSION.vsix && \
    bsdtar -xf prettier-vscode-$PRETTIER_VERSION.vsix extension && \
    rm prettier-vscode-$PRETTIER_VERSION.vsix && \
    mv extension $HOME/.vscode/extensions/prettier-vscode-$PRETTIER_VERSION.vsix && \
    # Install code runner: https://github.com/formulahendry/vscode-code-runner/releases/latest
    VS_CODE_RUNNER_VERSION="0.9.17" && \
    wget --no-verbose https://github.com/formulahendry/vscode-code-runner/releases/download/$VS_CODE_RUNNER_VERSION/code-runner-$VS_CODE_RUNNER_VERSION.vsix && \
    bsdtar -xf code-runner-$VS_CODE_RUNNER_VERSION.vsix extension && \
    rm code-runner-$VS_CODE_RUNNER_VERSION.vsix && \
    mv extension $HOME/.vscode/extensions/code-runner-$VS_CODE_RUNNER_VERSION && \
    # && code-server --install-extension formulahendry.code-runner@$VS_CODE_RUNNER_VERSION \
    sleep $SLEEP_TIMER && \
    # Install ESLint extension: https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint
    VS_ESLINT_VERSION="2.2.3" && \
    wget --retry-on-http-error=429 --waitretry 15 --tries 5 --no-verbose https://marketplace.visualstudio.com/_apis/public/gallery/publishers/dbaeumer/vsextensions/vscode-eslint/$VS_ESLINT_VERSION/vspackage -O dbaeumer.vscode-eslint.vsix && \
    # && wget --no-verbose https://github.com/microsoft/vscode-eslint/releases/download/$VS_ESLINT_VERSION-insider.2/vscode-eslint-$VS_ESLINT_VERSION.vsix -O dbaeumer.vscode-eslint.vsix && \
    bsdtar -xf dbaeumer.vscode-eslint.vsix extension && \
    rm dbaeumer.vscode-eslint.vsix && \
    mv extension $HOME/.vscode/extensions/dbaeumer.vscode-eslint-$VS_ESLINT_VERSION.vsix && \
    # && code-server --install-extension dbaeumer.vscode-eslint@$VS_ESLINT_VERSION \
    # Fix permissions
    fix-permissions.sh $HOME/.vscode/extensions/ && \
    # Cleanup
    clean-layer.sh

### END VSCODE ###

    
# Install and activate ZSH
COPY resources/tools/oh-my-zsh.sh resources/.p10k.zsh $RESOURCES_PATH/tools/

RUN \
    # Install ZSH
    /bin/bash $RESOURCES_PATH/tools/oh-my-zsh.sh --install && \
    # Make zsh the default shell
    # Initialize conda for command line activation
    # TODO do not activate for now, opening the bash shell is a bit slow
    # conda init bash && \
    # conda init zsh && \
    chsh -s $(which zsh) $NB_USER && \
    # Install sdkman - needs to be executed after zsh
    curl -s https://get.sdkman.io | bash && \ 
    cp $RESOURCES_PATH/tools/.p10k.zsh $HOME/ && \  
    # Cleanup
    clean-layer.sh

COPY resources/fcitx-baidupinyin_1.0.1.0_amd64.deb $RESOURCES_PATH/

RUN \
    apt-get update && \
    sed -i -e 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    apt-get install -y fcitx && \
    # apt-get install -y fcitx-googlepinyin fcitx-pinyin fcitx-sunpinyin && \
    apt-get install -y libgsettings-qt-dev qt5-default libqt5qml5 libxss-dev eog libqt5qml5 libqt5quick5 libqt5quickwidgets5 qml-module-qtquick2 && \
    gdebi $RESOURCES_PATH/fcitx-baidupinyin_1.0.1.0_amd64.deb -n && \
    im-config -n fcitx && \
    # Cleanup
    clean-layer.sh 

### INCUBATION ZONE ###
## Python 3
# Data science libraries requirements
COPY resources/libraries ${RESOURCES_PATH}/libraries

RUN \
    apt-get update && \  
    # Install minimal pip requirements
    # Install ONNX GPU Runtime Install cupy: https://cupy.chainer.org/
    pip install --no-cache-dir onnxruntime-gpu onnx && \
    # Install pycuda: https://pypi.org/project/pycuda
    # pip install --no-cache-dir pycuda && \
    # Install gpu utils libs
    pip install --no-cache-dir gpustat py3nvml gputil && \
     # Install scikit-cuda: https://scikit-cuda.readthedocs.io/en/latest/install.html
    pip install --no-cache-dir scikit-cuda && \
    apt-get install -y nvtop && \
    # Required by magenta
    # apt-get install -y libasound2-dev && \
    # required by rodeo ide (8MB)
    # apt-get install -y libgconf2-4 && \
    # required for pvporcupine (800kb)
    # apt-get install -y portaudio19-dev && \
    # Audio drivers for magenta? (3MB)
    # apt-get install -y libasound2-dev libjack-dev && \
    # libproj-dev required for cartopy (15MB)
    # apt-get install -y libproj-dev && \
    # mysql server: 150MB
    # apt-get install -y mysql-server && \
    # If minimal or light flavor -> exit here
    # if [ "$WORKSPACE_FLAVOR" = "minimal" ] || [ "$WORKSPACE_FLAVOR" = "light" ]; then \
    #     # Cleanup
    #     clean-layer.sh  && \
    #     exit 0 ; \
    # fi && \
    # Install fkill-cli program  TODO: 30MB, remove?
    # npm install --global fkill-cli && \
    # Activate pretty-errors
    # python -m pretty_errors -u -p && \
    # Cleanup
    clean-layer.sh
    
RUN pip install --no-cache-dir --upgrade --upgrade-strategy only-if-needed -r ${RESOURCES_PATH}/libraries/requirements-minimal.txt && \
    clean-layer.sh

ARG ARG_ROS_FLAVOR="all" \
    ROS_DISTRO=noetic \
    ROS2_DISTRO=galactic \
    INSTALL_PACKAGE=desktop 

# RUN \
#     if [ "$ARG_ROS_FLAVOR" = "all" ] || [ "$ARG_ROS_FLAVOR" = "ros" ]; then \
#         # ros1
#         apt-get update && \ 
#         apt-get install -y curl gnupg2 lsb-release && \
#         echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list && \
#         apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654 && \
#         apt-get update && \
#         apt-get install -y ros-${ROS_DISTRO}-${INSTALL_PACKAGE} && \
#         pip install --no-cache-dir catkin_pkg && \
#         clean-layer.sh  && \
#         exit 0 ; \
#     fi 

# RUN \
#     if [ "$ARG_ROS_FLAVOR" = "all" ] || [ "$ARG_ROS_FLAVOR" = "ros2" ]; then \
#         # ros2
#         apt-get update && \ 
#         apt-get install -y curl gnupg2 lsb-release && \
#         curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
#         echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null && \
#         apt-get update -q && \
#         apt-get install -y ros-${ROS2_DISTRO}-${INSTALL_PACKAGE} \
#         python3-argcomplete \
#         python3-colcon-common-extensions \
#         python3-rosdep python3-vcstool \
#         ros-${ROS2_DISTRO}-gazebo-ros-pkgs && \
#         rosdep init && \
#         clean-layer.sh && \
#         exit 0 ; \
#     fi 

### END INCUBATION ZONE ###

### CONFIGURATION ###

# Copy resources into workspace
COPY ["resources/", "$RESOURCES_PATH/"]

# Configure Home folder (e.g. xfce)
COPY resources/home/ $HOME/

# Copy some configuration files
COPY resources/ssh/ssh_config resources/ssh/sshd_config  /etc/ssh/
COPY resources/nginx/nginx.conf /etc/nginx/nginx.conf
COPY resources/config/xrdp.ini /etc/xrdp/xrdp.ini

# Configure supervisor process
COPY resources/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
# Copy all supervisor program definitions into workspace
COPY resources/supervisor/programs/ /etc/supervisor/conf.d/

# Assume yes to all apt commands, to avoid user confusion around stdin.
COPY resources/config/90assumeyes /etc/apt/apt.conf.d/

# Add tensorboard patch - use tensorboard jupyter plugin instead of the actual tensorboard magic
COPY resources/jupyter/tensorboard_notebook_patch.py $CONDA_PYTHON_DIR/dist-packages/tensorboard/notebook.py

# Additional jupyter configuration
COPY resources/jupyter/jupyter_notebook_config.py /etc/jupyter/
COPY resources/jupyter/sidebar.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/application-extension/
COPY resources/jupyter/plugin.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/extensionmanager-extension/
COPY resources/jupyter/ipython_config.py /etc/ipython/ipython_config.py

# Configure netdata
COPY resources/netdata/ /etc/netdata/
COPY resources/netdata/cloud.conf /var/lib/netdata/cloud.d/cloud.conf

# openp2p
COPY resources/tools/openp2p.sh $RESOURCES_PATH/tools/openp2p.sh
RUN \
    /bin/bash $RESOURCES_PATH/tools/openp2p.sh --install && \
    # Cleanup
    clean-layer.sh

# Branding of various components
RUN \
    ## create index.html to forward automatically to `vnc.html`
    # Needs to be run after patching
    ln -s $RESOURCES_PATH/novnc/vnc.html $RESOURCES_PATH/novnc/index.html &&\
    # Jupyter Branding
    cp -f $RESOURCES_PATH/branding/logo.png $CONDA_PYTHON_DIR"/dist-packages/notebook/static/base/images/logo.png" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $CONDA_PYTHON_DIR"/dist-packages/notebook/static/base/images/favicon.ico" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $CONDA_PYTHON_DIR"/dist-packages/notebook/static/favicon.ico" && \
    # Fielbrowser Branding
    mkdir -p $RESOURCES_PATH"/filebrowser/img/icons/" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $RESOURCES_PATH"/filebrowser/img/icons/favicon.ico" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $RESOURCES_PATH"/filebrowser/img/icons/favicon-32x32.png" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $RESOURCES_PATH"/filebrowser/img/icons/favicon-16x16.png" && \
    cp -f $RESOURCES_PATH/branding/ml-workspace-logo.svg $RESOURCES_PATH"/filebrowser/img/logo.svg" && \
    # Configure git
    git config --global core.fileMode false && \
    git config --global http.sslVerify false && \
    # Use store or credentialstore instead? timout == 365 days validity
    git config --global credential.helper 'cache --timeout=31540000' && \
    # Configure Matplotlib
    # Import matplotlib the first time to build the font cache.
    MPLBACKEND=Agg python -c "import matplotlib.pyplot" \
    # Stop Matplotlib printing junk to the console on first load
    sed -i "s/^.*Matplotlib is building the font cache using fc-list.*$/# Warning removed/g" $CONDA_PYTHON_DIR/dist-packages/matplotlib/font_manager.py && \
    # ungit:
    echo "[Desktop Entry]\nVersion=1.0\nType=Link\nName=Ungit\nComment=Git Client\nCategories=Development;\nIcon=/resources/icons/ungit-icon.png\nURL=http://localhost:8092/tools/ungit" > /usr/share/applications/ungit.desktop && \
    chmod +x /usr/share/applications/ungit.desktop && \
    # netdata:
    echo "[Desktop Entry]\nVersion=1.0\nType=Link\nName=Netdata\nComment=Hardware Monitoring\nCategories=System;Utility;Development;\nIcon=/resources/icons/netdata-icon.png\nURL=http://localhost:8092/tools/netdata" > /usr/share/applications/netdata.desktop && \
    chmod +x /usr/share/applications/netdata.desktop && \
    # glances:
    echo "[Desktop Entry]\nVersion=1.0\nType=Link\nName=Glances\nComment=Hardware Monitoring\nCategories=System;Utility;\nIcon=/resources/icons/glances-icon.png\nURL=http://localhost:8092/tools/glances" > /usr/share/applications/glances.desktop && \
    chmod +x /usr/share/applications/glances.desktop && \
    # Remove mail and logout desktop icons
    # rm /usr/share/applications/xfce4-mail-reader.desktop && \
    # rm /usr/share/applications/xfce4-session-logout.desktop && \
    sed -i 's/xfce4-session-logout/killall python/g' /usr/share/applications/xfce4-session-logout.desktop && \
    # Various configurations
    touch /root/.ssh/config && \
    # clear chome init file - not needed since we load settings manually
    chmod -R a+rwx $WORKSPACE_HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
    # make all desktop launchers executable
    chmod -R a+rwx /usr/share/applications/ && \
    ln -s $RESOURCES_PATH/tools/ $HOME/Desktop/Tools && \
    ln -s $WORKSPACE_HOME $HOME/Desktop/workspace && \
    chmod a+rwx /usr/local/bin/start-notebook.sh && \
    chmod a+rwx /usr/local/bin/start.sh && \
    chmod a+rwx /usr/local/bin/start-singleuser.sh && \
    chown $NB_USER:$NB_USER /tmp && \
    chmod 1777 /tmp && \
    # TODO: does 1777 work fine? 
    chmod a+rwx /tmp && \
    # Set /workspace as default directory to navigate to as root user
    echo 'cd '$WORKSPACE_HOME >> $HOME/.bashrc && \
    # printf "\necho \"choose ros neotic(1) or ros2 galactic(2) or none:\"\nread edition\n if [ \"\$edition\" ] && [ \"\$edition\" -eq \"1\" ]; then \n  source /opt/ros/noetic/setup.bash \n  export ROS_HOSTNAME=localhost \n  export ROSMASTER_URI=http://localhost:11311 \n  export ROS_IP=\'hostname -I\' \n  echo -e \"\\\\033[33mros environment\\\\033[0m \" \nelif [ \"\$edition\" ] && [ \"\$edition\" -eq \"2\" ]; then \n  source /opt/ros/galactic/setup.bash \n  echo -e \"\\\\033[32mros2 environment\\\\033[0m\" \nelse\n  echo -e \"\\\\033[35mnone ros environment\\\\033[0m\" \nfi" >> $HOME/.bashrc && \
    chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo && \
    rm /usr/local/etc/jupyter/jupyter_notebook_config.py && \
    rm /opt/pytorch/jupyter_notebook_config.py

# MKL and Hardware Optimization
# Fix problem with MKL with duplicated libiomp5: https://github.com/dmlc/xgboost/issues/1715
# Alternative - use openblas instead of Intel MKL: conda install -y nomkl
# http://markus-beuckelmann.de/blog/boosting-numpy-blas.html
# MKL:
# https://software.intel.com/en-us/articles/tips-to-improve-performance-for-popular-deep-learning-frameworks-on-multi-core-cpus
# https://github.com/intel/pytorch#bkm-on-xeon
# http://astroa.physics.metu.edu.tr/MANUALS/intel_ifc/mergedProjects/optaps_for/common/optaps_par_var.htm
# https://www.tensorflow.org/guide/performance/overview#tuning_mkl_for_the_best_performance
# https://software.intel.com/en-us/articles/maximize-tensorflow-performance-on-cpu-considerations-and-recommendations-for-inference
ENV KMP_DUPLICATE_LIB_OK="True" \
    # Control how to bind OpenMP* threads to physical processing units # verbose
    KMP_AFFINITY="granularity=fine,compact,1,0" \
    KMP_BLOCKTIME=0 \
    # KMP_BLOCKTIME="1" -> is not faster in my tests
    # TensorFlow uses less than half the RAM with tcmalloc relative to the default. - requires google-perftools
    # Too many issues: LD_PRELOAD="/usr/lib/libtcmalloc.so.4" \
    # TODO set PYTHONDONTWRITEBYTECODE
    # TODO set XDG_CONFIG_HOME, CLICOLOR?
    # https://software.intel.com/en-us/articles/getting-started-with-intel-optimization-for-mxnet
    # KMP_AFFINITY=granularity=fine, noduplicates,compact,1,0
    # MXNET_SUBGRAPH_BACKEND=MKLDNN
    # TODO: check https://github.com/oneapi-src/oneTBB/issues/190
    # TODO: https://github.com/pytorch/pytorch/issues/37377
    # use omp
    MKL_THREADING_LAYER=GNU \
    # To avoid over-subscription when using TBB, let the TBB schedulers use Inter Process Communication to coordinate:
    ENABLE_IPC=1 \
    # will cause pretty_errors to check if it is running in an interactive terminal
    PYTHON_PRETTY_ERRORS_ISATTY_ONLY=1 \
    # TODO: evaluate - Deactivate hdf5 file locking
    HDF5_USE_FILE_LOCKING=False \
    # Basic VNC Settings - no password
    VNC_PW=vncpassword \
    VNC_RESOLUTION=1600x900 \
    VNC_COL_DEPTH=24 \
    # Set default values for environment variables
    CONFIG_BACKUP_ENABLED="true" \
    SHUTDOWN_INACTIVE_KERNELS="false" \
    SHARED_LINKS_ENABLED="true" \
    AUTHENTICATE_VIA_JUPYTER="false" \
    DATA_ENVIRONMENT=$WORKSPACE_HOME"/environment" \
    WORKSPACE_BASE_URL="/" \
    INCLUDE_TUTORIALS="true" \
    # Main port used for sshl proxy -> can be changed
    WORKSPACE_PORT="8080" \
    # Set zsh as default shell (e.g. in jupyter)
    SHELL="/usr/bin/zsh" \
    # Fix dark blue color for ls command (unreadable):
    # https://askubuntu.com/questions/466198/how-do-i-change-the-color-for-directories-with-ls-in-the-console
    # USE default LS_COLORS - Dont set LS COLORS - overwritten in zshrc
    # LS_COLORS="" \
    # set number of threads various programs should use, if not-set, it tries to use all
    # this can be problematic since docker restricts CPUs by stil showing all
    MAX_NUM_THREADS="auto"

### END CONFIGURATION ###
ARG ARG_BUILD_DATE="unknown" \
    ARG_VCS_REF="unknown" \
    ARG_WORKSPACE_VERSION="unknown"
ENV WORKSPACE_VERSION=$ARG_WORKSPACE_VERSION 

# Overwrite & add Labels
LABEL \
    "maintainer"="mltooling.team@gmail.com" \
    "workspace.version"=$WORKSPACE_VERSION \
    "workspace.flavor"=$WORKSPACE_FLAVOR \
    # Kubernetes Labels
    "io.k8s.description"="All-in-one web-based development environment for machine learning." \
    "io.k8s.display-name"="Machine Learning Workspace" \
    # Openshift labels: https://docs.okd.io/latest/creating_images/metadata.html
    "io.openshift.expose-services"="8080:http, 5901:xvnc" \
    "io.openshift.non-scalable"="true" \
    "io.openshift.tags"="workspace, machine learning, vnc, ubuntu, xfce" \
    "io.openshift.min-memory"="1Gi" \
    # Open Container labels: https://github.com/opencontainers/image-spec/blob/master/annotations.md
    "org.opencontainers.image.title"="Machine Learning Workspace" \
    "org.opencontainers.image.description"="All-in-one web-based development environment for machine learning." \
    "org.opencontainers.image.documentation"="https://github.com/ml-tooling/ml-workspace" \
    "org.opencontainers.image.url"="https://github.com/ml-tooling/ml-workspace" \
    "org.opencontainers.image.source"="https://github.com/ml-tooling/ml-workspace" \
    # "org.opencontainers.image.licenses"="Apache-2.0" \
    "org.opencontainers.image.version"=$WORKSPACE_VERSION \
    "org.opencontainers.image.vendor"="ML Tooling" \
    "org.opencontainers.image.authors"="Lukas Masuch & Benjamin Raethlein" \
    "org.opencontainers.image.revision"=$ARG_VCS_REF \
    "org.opencontainers.image.created"=$ARG_BUILD_DATE \
    # Label Schema Convention (deprecated): http://label-schema.org/rc1/
    "org.label-schema.name"="Machine Learning Workspace" \
    "org.label-schema.description"="All-in-one web-based development environment for machine learning." \
    "org.label-schema.usage"="https://github.com/ml-tooling/ml-workspace" \
    "org.label-schema.url"="https://github.com/ml-tooling/ml-workspace" \
    "org.label-schema.vcs-url"="https://github.com/ml-tooling/ml-workspace" \
    "org.label-schema.vendor"="ML Tooling" \
    "org.label-schema.version"=$WORKSPACE_VERSION \
    "org.label-schema.schema-version"="1.0" \
    "org.label-schema.vcs-ref"=$ARG_VCS_REF \
    "org.label-schema.build-date"=$ARG_BUILD_DATE

# Removed - is run during startup since a few env variables are dynamically changed: RUN printenv > /root/.ssh/environment

# This assures we have a volume mounted even if the user forgot to do bind mount.
# So that they do not lose their data if they delete the container.
# TODO: VOLUME [ "/workspace" ]
# TODO: WORKDIR /workspace?



USER $NB_USER

RUN \
    sudo chmod 777 $HOME/ -R &&\
    sudo chown ml:ml $HOME/ -R &&\
    sudo chmod 777 /etc/nginx/ -R &&\
    sudo chown root:crontab /usr/bin/crontab &&\
    sudo chmod 2755 /usr/bin/crontab &&\
    sudo chmod 777 /var/log/supervisor/ -R &&\
    sudo chmod 777 /var/run -R &&\
    sudo chmod 400 /var/run/sshd && \
    sudo chmod 777 /usr/local/openresty/nginx -R &&\
    sudo chmod 777 /var/log -R &&\
    sudo chmod g-w,o-w .oh-my-zsh -R

# use global option with tini to kill full process groups: https://github.com/krallin/tini#process-group-killing
ENTRYPOINT ["/tini", "-g", "--"]

CMD ["python", "/resources/docker-entrypoint.py"]

# Port 8080 is the main access port (also includes SSH)
# Port 5091 is the VNC port
# Port 3389 is the RDP port
# Port 8090 is the Jupyter Notebook Server
# See supervisor.conf for more ports

EXPOSE 8080
###
