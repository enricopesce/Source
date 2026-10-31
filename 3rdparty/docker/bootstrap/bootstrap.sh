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

cd "$GENERATED"
if [ ! -s "$CROSS_DEVEL_STAGE0" ]; then
	# Build the first-stage package and its host tools before using them to seed GCC.
	HAIKU_PORTER_EXTRA_OPTIONS="--debug" jam -q @bootstrap-raw "haiku_cross_devel_sysroot_stage0_$TARGET_ARCH.hpkg"
fi
if [ ! -s "$CROSS_DEVEL_STAGE0" ]; then
	echo "Bootstrap stage0 package was not produced: $CROSS_DEVEL_STAGE0" >&2
	exit 1
fi
if [ ! -s "$PACKAGE_TOOL" ]; then
	echo "Host HPKG tool was not produced: $PACKAGE_TOOL" >&2
	exit 1
fi

# Seed the buildtools GCC sysroot with the stage0 Haiku headers and libraries.
rm -rf "$CROSS_SYSROOT/boot/system"
mkdir -p "$CROSS_SYSROOT/boot/system"
LD_LIBRARY_PATH="$GENERATED/objects/linux/lib" "$PACKAGE_TOOL" extract -C "$CROSS_SYSROOT/boot/system" "$CROSS_DEVEL_STAGE0"
test -s "$CROSS_SYSROOT/boot/system/develop/headers/posix/stdlib.h"

BOOTSTRAP_PACKAGE_DIRECTORY="$GENERATED/objects/haiku/$TARGET_ARCH/packaging/repositories/HaikuPortsCross-build/packages"
shopt -s nullglob
bootstrap_runtime_packages=("$BOOTSTRAP_PACKAGE_DIRECTORY"/*.hpkg)
filtered_runtime_packages=()
for package in "${bootstrap_runtime_packages[@]}"; do
	case "$package" in
		*-source.hpkg|*_source_rigged-*|*-debuginfo.hpkg) continue ;;
	esac
	filtered_runtime_packages+=("$package")
done
if [ ${#filtered_runtime_packages[@]} -eq 0 ]; then
	echo "No HaikuPortsCross bootstrap runtime packages found in $BOOTSTRAP_PACKAGE_DIRECTORY" >&2
	exit 1
fi
bootstrap_runtime_package_list=$(IFS=,; echo "${filtered_runtime_packages[*]}")
bootstrap_porter_options="--debug --system-packages-directory=\"$BOOTSTRAP_PACKAGE_DIRECTORY\" --cross-runtime-package=\"$bootstrap_runtime_package_list\""
HAIKU_BOOTSTRAP_SOURCES_PROFILE=@bootstrap-raw HAIKU_PORTER_EXTRA_OPTIONS="$bootstrap_porter_options" jam -q @bootstrap-raw
# The final nightly profile rebuilds this list after local runtime packages exist.
rm -f "$GENERATED/objects/haiku/$TARGET_ARCH/packaging/repositories/HaikuPorts-sources-build/package_list"
