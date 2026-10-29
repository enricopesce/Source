FROM docker.io/library/python:3.12-slim-bookworm@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70

ENV DEBIAN_FRONTEND="noninteractive"

ARG DEBIAN_SNAPSHOT=20261029T000000Z
RUN sed -i \
	-e "s|http://deb.debian.org/debian-security|https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
	-e "s|http://deb.debian.org/debian|https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" \
	/etc/apt/sources.list.d/debian.sources \
	&& apt-get -o Acquire::Check-Valid-Until=false update

# Base Haiku requirements
RUN apt-get install -y git nasm autoconf automake autoconf-archive autopoint texinfo \
	flex bison gawk build-essential unzip wget zip less zlib1g-dev \
	libzstd-dev libcurl4-openssl-dev genisoimage libtool \
	mtools gcc-multilib u-boot-tools util-linux device-tree-compiler bc attr
RUN apt-get install -y cmake pkg-config libncurses-dev \
    libssl-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev \
    liblzma-dev libncursesw5-dev uuid-dev

# Debian Bookworm provides Autoconf 2.71; Python 3.14 ports require 2.72.
ARG AUTOCONF_VERSION=2.72
ARG AUTOCONF_SHA256=ba885c1319578d6c94d46e9b0dceb4014caafe2490e437a0dbca3f270a223f5a
RUN set -eux; \
    cd /tmp; \
    wget -q "https://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz"; \
    echo "${AUTOCONF_SHA256}  autoconf-${AUTOCONF_VERSION}.tar.xz" | sha256sum --check --strict -; \
    tar -xf "autoconf-${AUTOCONF_VERSION}.tar.xz"; \
    cd "autoconf-${AUTOCONF_VERSION}"; \
    ./configure --prefix=/usr/local; \
    make -j"$(nproc)"; \
    make install; \
    autoconf --version | grep -Fq "${AUTOCONF_VERSION}"; \
    cd /; \
    rm -rf "/tmp/autoconf-${AUTOCONF_VERSION}" "/tmp/autoconf-${AUTOCONF_VERSION}.tar.xz"
# Python 3.14 cross builds need a native interpreter of the same minor version.
ARG BUILD_PYTHON_VERSION=3.14.9
ARG BUILD_PYTHON_SHA256=e02d9ac21cebda6e46435369744a92c65cc7cd8669697694122cf97ffacd1e53
RUN set -eux; \
    cd /tmp; \
    wget -q "https://www.python.org/ftp/python/${BUILD_PYTHON_VERSION}/Python-${BUILD_PYTHON_VERSION}.tar.xz"; \
    echo "${BUILD_PYTHON_SHA256}  Python-${BUILD_PYTHON_VERSION}.tar.xz" | sha256sum --check --strict -; \
    tar -xf "Python-${BUILD_PYTHON_VERSION}.tar.xz"; \
    cd "Python-${BUILD_PYTHON_VERSION}"; \
    ./configure --prefix=/opt/python3.14 --with-ensurepip=no --disable-test-modules; \
    make -j"$(nproc)"; \
    make install; \
    /opt/python3.14/bin/python3.14 -c "import hashlib, pathlib, sys, sysconfig; assert sys.version_info[:2] == (3, 14)"; \
    cd /; \
    rm -rf "/tmp/Python-${BUILD_PYTHON_VERSION}" "/tmp/Python-${BUILD_PYTHON_VERSION}.tar.xz"
# The pinned flit-core recipe assembles Python 3.10 and 3.14 subpackages.
ARG BUILD_PYTHON310_VERSION=3.10.22
ARG BUILD_PYTHON310_SHA256=c61fe9b1a1a7ec2a0b0388e664187c378a5325a89e3606d220abf5bdfccb2543
RUN set -eux; \
    cd /tmp; \
    wget -q "https://www.python.org/ftp/python/${BUILD_PYTHON310_VERSION}/Python-${BUILD_PYTHON310_VERSION}.tar.xz"; \
    echo "${BUILD_PYTHON310_SHA256}  Python-${BUILD_PYTHON310_VERSION}.tar.xz" | sha256sum --check --strict -; \
    tar -xf "Python-${BUILD_PYTHON310_VERSION}.tar.xz"; \
    cd "Python-${BUILD_PYTHON310_VERSION}"; \
    ./configure --prefix=/opt/python3.10 --with-ensurepip=no --disable-test-modules; \
    make -j"$(nproc)"; \
    make install; \
    /opt/python3.10/bin/python3.10 -c "import hashlib, pathlib, sys, sysconfig; assert sys.version_info[:2] == (3, 10)"; \
    cd /; \
    rm -rf "/tmp/Python-${BUILD_PYTHON310_VERSION}" "/tmp/Python-${BUILD_PYTHON310_VERSION}.tar.xz"
RUN ln -s /opt/python3.10/bin/python3.10 /usr/local/bin/python3.10 \
    && ln -s /opt/python3.14/bin/python3.14 /usr/local/bin/python3.14 \
    && python3.10 --version | grep -Fq 3.10.22 \
    && python3.14 --version | grep -Fq 3.14.9
ARG BUILD_INSTALLER_VERSION=1.0.1
ARG BUILD_INSTALLER_WHEEL_SHA256=011d045df8b954ced7dde3a7e42ae4418da40ecda7990f2d11d5ed7c146fd98b
ARG BUILD_FLIT_CORE_VERSION=3.12.0
ARG BUILD_FLIT_CORE_WHEEL_SHA256=e7a0304069ea895172e3c7bb703292e992c5d1555dd1233ab7b5621b5b69e62c
RUN set -eux; \
    printf "%s\n" \
        "installer==${BUILD_INSTALLER_VERSION} --hash=sha256:${BUILD_INSTALLER_WHEEL_SHA256}" \
        "flit-core==${BUILD_FLIT_CORE_VERSION} --hash=sha256:${BUILD_FLIT_CORE_WHEEL_SHA256}" \
        > /tmp/haiku-host-build-requirements.txt; \
    python3 -m pip install --disable-pip-version-check --no-cache-dir --no-compile --no-deps --require-hashes --target=/opt/python3.10/lib/python3.10/site-packages -r /tmp/haiku-host-build-requirements.txt; \
    python3 -m pip install --disable-pip-version-check --no-cache-dir --no-compile --no-deps --require-hashes --target=/opt/python3.14/lib/python3.14/site-packages -r /tmp/haiku-host-build-requirements.txt; \
    python3.10 -c "from importlib.metadata import version; assert version('installer') == '${BUILD_INSTALLER_VERSION}' and version('flit-core') == '${BUILD_FLIT_CORE_VERSION}'"; \
    python3.14 -c "from importlib.metadata import version; assert version('installer') == '${BUILD_INSTALLER_VERSION}' and version('flit-core') == '${BUILD_FLIT_CORE_VERSION}'"
RUN apt-get install -y vim nano
RUN echo "source /usr/share/vim/vim80/defaults.vim" > ~/.vimrc
RUN echo "set mouse=" >> ~/.vimrc

ENV GIT_BUILDTOOLS="https://github.com/haiku/buildtools.git"
ENV GIT_HAIKU="https://github.com/enricopesce/Source.git"
ENV GIT_HAIKUPORTER="https://github.com/enricopesce/haikuporter.git"
ENV GIT_HAIKUPORTS="https://github.com/enricopesce/haikuports.git"
ENV GIT_HAIKUPORTS_CROSS="https://github.com/haikuports/haikuports.cross.git"

ADD prep.sh /usr/local/bin/prep
ADD crosstools.sh /usr/local/bin/crosstools
ADD build-cross-fortran.sh /usr/local/bin/build-cross-fortran
ADD bootstrap.sh /usr/local/bin/bootstrap
ADD nightly-mmc.sh /usr/local/bin/nightly-mmc
ADD host-uudecode.py /usr/local/bin/haiku-host-uudecode
ADD find-port-provider.py /usr/local/bin/find-port-provider
RUN chmod 0755 /usr/local/bin/haiku-host-uudecode /usr/local/bin/find-port-provider
ADD sources.lock /usr/local/share/haiku-bootstrap/sources.lock
ADD patches/ /usr/local/share/haiku-bootstrap/patches/
ADD haikuports_chroot.sh /usr/local/bin/haikuports_chroot
ADD haikuports_build.sh /usr/local/bin/haikuports_build

ENV WORKPATH="/work"
ENV PATH="$PATH:$WORKPATH/bin"

WORKDIR "/work"
VOLUME ["/work"]

ENTRYPOINT ["/bin/bash", "-c"]
