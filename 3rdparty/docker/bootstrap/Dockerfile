FROM docker.io/library/python:3.12-slim-bookworm@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70

ENV DEBIAN_FRONTEND="noninteractive"

ARG DEBIAN_SNAPSHOT=20261029T000000Z
RUN sed -i \
	-e "s|http://deb.debian.org/debian-security|https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
	-e "s|http://deb.debian.org/debian|https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" \
	/etc/apt/sources.list.d/debian.sources \
	&& apt-get -o Acquire::Check-Valid-Until=false update

# Base Haiku requirements
RUN apt-get install -y git nasm autoconf automake autopoint texinfo \
	flex bison gawk build-essential unzip wget zip less zlib1g-dev \
	libzstd-dev libcurl4-openssl-dev genisoimage libtool \
	mtools gcc-multilib u-boot-tools util-linux device-tree-compiler bc attr
RUN apt-get install -y cmake pkg-config libncurses-dev

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
