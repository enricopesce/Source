# Haiku bootstrap in a container

This container isolates the Linux host tools used to bootstrap Haiku. The
ARM64 nightly-mmc recipe below uses pinned revisions of the RenkuOS source,
HaikuPorter, HaikuPorts, buildtools, and HaikuPortsCross repositories.

## Requirements

- Podman (the default engine) or Docker (set ENGINE=docker)
- GNU make
- An internet connection
- Substantial free disk space for a clean ARM64 bootstrap and package build

Building the container image installs its declared Debian build dependencies
inside the image. The host does not need those packages installed.

## Reproduce the ARM64 nightly image

Run these commands from this directory:

    make image
    make nightly-mmc

The command starts from pinned source commits in sources.lock, builds the
cross-toolchain and bootstrap image, then runs @nightly-mmc. In a fresh
workspace, Jam invokes HaikuPorter for packages missing from the local build
repository; HaikuPorter builds the requested packages and their dependencies
from the pinned HaikuPorts source tree.

The generated image is written to
$HOME/haiku-nightly-mmc-work/generated.arm64/haiku-mmc.image.
To repeat the build from a clean workspace, first choose a new WORKDIR:

    make nightly-mmc WORKDIR="$HOME/haiku-nightly-mmc-clean"

make clean-work removes the selected workspace, including source checkouts,
intermediate builds, and images. Use it only when that data can be discarded.

The source lock pins the snapshots required by the ARM64 profile. Updating any
fork requires updating its commit ID in sources.lock.

## Generic bootstrap commands

The lower-level steps remain available:

1. make prep checks out the pinned sources.
2. TARGET_ARCH=arm64 make crosstools builds the cross-toolchain.
3. TARGET_ARCH=arm64 make bootstrap creates the bootstrap image.
4. TARGET_ARCH=arm64 make enter enters the build environment.
