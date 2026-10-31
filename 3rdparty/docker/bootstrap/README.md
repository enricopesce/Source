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
Autoconf 2.72 is installed from the official GNU release tarball with a
SHA-256 check, since the pinned Bookworm snapshot provides 2.71.
The container also installs the autoconf-archive macros from the pinned
Debian snapshot, so the patched Python configure script can be regenerated.
The container builds native CPython 3.10.22 and 3.14.9 interpreters from
official source tarballs with SHA-256 checks. The pinned HaikuPorts flit-core
recipe assembles subpackages for both versions, so both versioned host commands
are available to package scripts. The base python3 remains Python 3.12.
The host installer 1.0.1, flit-core 3.12.0, pyproject-hooks 1.2.0,
packaging 26.2, tomli 2.0.1, and build 1.5.0 wheels are pinned by SHA-256
and installed
for both interpreters. HaikuPorts uses these host modules to build and install
pure-Python wheels during cross builds.
Python 3.14's cross configure uses the matching 3.14 host interpreter.
Python 3.10.22 is the final 3.10 release and is included only as a build tool
while the pinned ports still package that version.

## Reproduce the ARM64 nightly image

Run from this directory in a clean checkout. Record the build-definition
revision with git rev-parse HEAD. Each successful image gets a
haiku-mmc.image.build-info file with the pinned source revisions, image
checksum, and package-manifest checksum. The adjacent
haiku-mmc.image.packages.tsv records each selected package name, version,
architecture, archive path, and SHA-256. The build stops if a selected archive
is missing, has an architecture other than arm64 or any, or contains an
out-of-layout or staging path.

    make nightly-mmc WORKDIR="$HOME/haiku-nightly-mmc-work"

nightly-mmc builds the container image once, checks out the commits in
sources.lock, builds the cross-toolchain, creates the bootstrap stage0 HPKG and
host package tools, seeds the GCC sysroot from stage0, completes the bootstrap
image, then runs @nightly-mmc. Missing profile packages and their dependencies are built from
the pinned HaikuPorts checkout. The driver follows both BUILD_REQUIRES and
BUILD_PREREQUIRES reported by HaikuPorter, including dynamically declared
Python version subpackages, builds the pinned provider, and retries the
blocked port. The generated image is written to
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
  package creation and image generation. It repairs the cross-Fortran sysroot
  link HaikuPorter expects, without rebuilding an existing compiler. To resume
  an interrupted port compile from its existing objects, add
  `HAIKU_RESUME_BUILD=1`.

RESUME=1 requires the source checkouts and bootstrap outputs to exist. Use it
only after the toolchain and bootstrap stages completed. The profile build
stores its Jam and HaikuPorter logs in the selected workspace.

make clean-work WORKDIR=... removes source checkouts, intermediate builds,
package caches, and generated images only when the workspace has the marker
created by these Makefile targets. It refuses home directories, symlinks,
non-empty unmarked directories, and paths without the marker.

## Lower-level commands

    make prep
    make crosstools TARGET_ARCH=arm64
    make bootstrap TARGET_ARCH=arm64
    make build-cross-fortran TARGET_ARCH=arm64
    make enter TARGET_ARCH=arm64

When updating a fork, change its immutable commit in sources.lock and commit
the build definition with the update.

## ARM64 development image contents

Haiku package archive paths are relative to /boot/system. Use the official system directories such as bin/, data/, develop/, and documentation/. Do not include boot/system/ inside an HPKG; Haiku exposes those entries under /boot/system/ when the package is activated. The audit reads every HPKG file list selected by the Jam image rules, checks that entries are relative to /boot/system and use Haiku system roots, rejects staging/build paths, and verifies each package's architecture metadata. It allows Haiku core boot files only in the core packages that define them.

The ARM64 development package selection is defined in
[DefaultBuildProfiles](../../../build/jam/DefaultBuildProfiles) and included by
`nightly-mmc`. It includes `binutils`, `gcc`, `gcc_fortran`, `git`, `make`,
`m4`, `perl`, `python3.10`, `file`, `mpfr`, `mpc`, `texinfo`, `jam`, `mawk`,
`mkdepend`, `nasm`, `patch`, `libiconv_devel`, `openssl3_devel`,
`libjpeg_turbo_devel`, `libpng16_devel`, `zlib_devel`, `zstd_devel`,
`autoconf`, `automake`, `bison`, `flex`, `pkgconfig`, `cmake`, `ninja`, `gdb`,
`libtool`, `libarchive`, `libarchive_devel`, `libuv_devel`, `rhash_devel`,
`isl_devel` and `xxhash_devel`, plus `haiku_devel.hpkg`.

NetSurf is deliberately not installed in the image. Its ARM64 recipe remains in the pinned HaikuPorts tree so developers can build it natively after booting Haiku.

The `nightly-mmc` image includes the pinned HaikuPorts checkout at `/boot/system/data/haikuports`, the HaikuPorter source checkout at `/boot/system/data/haikuporter`, a `haikuporter` command, its native ARM64 Python 3.14 runtime, and the development toolchain listed above. The checkouts are inside activated packages; copy them to writable storage before building:

    cp -a /boot/system/data/haikuports ~/haikuports
    cp -a /boot/system/data/haikuporter ~/haikuporter
    mkdir -p ~/config/settings
    cp ~/haikuporter/haikuports-sample.conf ~/config/settings/haikuports.conf

Edit `~/config/settings/haikuports.conf`: set `TREE_PATH` to `/boot/home/haikuports` and replace the sample `PACKAGER` value. Then, from Haiku, build NetSurf and any missing dependencies with:

    haikuporter -j2 --get-dependencies netsurf

The command fetches sources and builds the port in Haiku. NetSurf and its runtime dependencies are not copied into the generated image. The full Haiku OS image pipeline remains a cross-build on Linux x86_64; QEMU is not part of image generation. Build provenance is recorded beside the image in `haiku-mmc.image.build-info`.
