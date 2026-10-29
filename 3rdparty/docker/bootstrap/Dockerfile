FROM docker.io/library/python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND="noninteractive"

RUN apt-get update

# Base Haiku requirements
RUN apt-get install -y git nasm autoconf automake autopoint texinfo \
	flex bison gawk build-essential unzip wget zip less zlib1g-dev \
	libzstd-dev libcurl4-openssl-dev genisoimage libtool \
	mtools gcc-multilib u-boot-tools util-linux device-tree-compiler bc attr
RUN apt-get install -y cmake pkg-config libncurses-dev
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
RUN chmod 0755 /usr/local/bin/haiku-host-uudecode
ADD sources.lock /usr/local/share/haiku-bootstrap/sources.lock
ADD patches/ /usr/local/share/haiku-bootstrap/patches/
ADD haikuports_chroot.sh /usr/local/bin/haikuports_chroot
ADD haikuports_build.sh /usr/local/bin/haikuports_build

ENV WORKPATH="/work"
ENV PATH="$PATH:$WORKPATH/bin"

WORKDIR "/work"
VOLUME ["/work"]

ENTRYPOINT ["/bin/bash", "-c"]
