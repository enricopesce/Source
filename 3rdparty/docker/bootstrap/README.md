# Haiku bootstrap in a container

This directory contains the build definition for the ARM64 nightly-mmc image.
The container isolates Linux host tools. Haiku, HaikuPorter, HaikuPorts,
buildtools, and HaikuPortsCross revisions are pinned in sources.lock.

## Requirements

- Linux x86_64 host with Podman (default) or Docker, and GNU make
- Internet access for the pinned Git revisions and source archives
- Enough free disk space for the toolchain, package cache, and generated image

The container base image is pinned by digest, and Debian packages come from
the fixed Debian snapshot in the Dockerfile. Build dependencies are installed
inside the container image; the host does not need those packages.

## Reproduce the ARM64 nightly image

Run from this directory in a clean checkout. Record the build-definition
revision with git rev-parse HEAD; each successful image also gets a
haiku-mmc.image.build-info file listing that revision and the exact source
revisions used.

    make nightly-mmc WORKDIR="$HOME/haiku-nightly-mmc-work"

nightly-mmc builds the container image once, checks out the commits in
sources.lock, builds the cross-toolchain and bootstrap packages, then runs
@nightly-mmc. Missing profile packages and their dependencies are built from
the pinned HaikuPorts checkout. The generated image is written to
$WORKDIR/generated.arm64/haiku-mmc.image.

To repeat from clean sources, select a new workspace:

    make nightly-mmc WORKDIR="$HOME/haiku-nightly-mmc-clean"

## Continue an interrupted build

Use the existing workspace and rerun the last incomplete stage. Targets reuse
files already produced in generated.arm64:

- make prep WORKDIR=... checks out the pinned repositories.
- make crosstools WORKDIR=... builds the cross-toolchain.
- make bootstrap WORKDIR=... continues Jam's bootstrap build.
- make build-cross-fortran WORKDIR=... builds the cross-Fortran compiler.
- After those stages complete, make nightly-mmc RESUME=1 WORKDIR=... resumes
  package creation and image generation without repeating them.

RESUME=1 requires the source checkouts and bootstrap outputs to exist. Use it
only after the toolchain and bootstrap stages completed. The profile build
stores its Jam and HaikuPorter logs in the selected workspace.

make clean-work WORKDIR=... removes source checkouts, intermediate builds,
package caches, and generated images. Use it only when that data can be
discarded.

## Lower-level commands

    make prep
    make crosstools TARGET_ARCH=arm64
    make bootstrap TARGET_ARCH=arm64
    make build-cross-fortran TARGET_ARCH=arm64
    make enter TARGET_ARCH=arm64

When updating a fork, change its immutable commit in sources.lock and commit
the build definition with the update.
