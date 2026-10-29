#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
if [ -z "${TARGET_ARCH:-}" ]; then echo "TARGET_ARCH isn't set!"; exit 1; fi
: "${BUILD_DIR_NAME:=generated.$TARGET_ARCH}"
GENERATED="$WORKPATH/$BUILD_DIR_NAME"
if [ ! -d "$GENERATED" ]; then echo "$GENERATED is not available; run crosstools first"; exit 1; fi

CROSS_SYSROOT="$GENERATED/cross-tools-$TARGET_ARCH/sysroot"
CROSS_DEVEL_STAGE0="$GENERATED/objects/haiku/$TARGET_ARCH/packaging/packages/haiku_cross_devel_sysroot_stage0_$TARGET_ARCH.hpkg"
PACKAGE_TOOL="$GENERATED/objects/linux/x86_64/release/tools/package/package"
for input in "$CROSS_DEVEL_STAGE0" "$PACKAGE_TOOL"; do
	if [ ! -s "$input" ]; then
		echo "Missing bootstrap sysroot input: $input" >&2
		exit 1
	fi
done

# Seed the buildtools GCC sysroot with the stage0 Haiku headers and libraries.
rm -rf "$CROSS_SYSROOT/boot/system"
mkdir -p "$CROSS_SYSROOT/boot/system"
LD_LIBRARY_PATH="$GENERATED/objects/linux/lib" "$PACKAGE_TOOL" extract -C "$CROSS_SYSROOT/boot/system" "$CROSS_DEVEL_STAGE0"
test -s "$CROSS_SYSROOT/boot/system/develop/headers/posix/stdlib.h"

cd "$GENERATED"
HAIKU_PORTER_EXTRA_OPTIONS="--debug" jam -q @bootstrap-raw
