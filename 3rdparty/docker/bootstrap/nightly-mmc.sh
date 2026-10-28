#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
: "${TARGET_ARCH:=arm64}"
: "${BUILD_DIR_NAME:=generated.$TARGET_ARCH}"
if [ "$TARGET_ARCH" != arm64 ]; then echo "This profile is ARM64 only (TARGET_ARCH=arm64)"; exit 1; fi
if [ -e "$WORKPATH/$BUILD_DIR_NAME" ]; then
	echo "$WORKPATH/$BUILD_DIR_NAME already exists."
	echo "Use a new empty WORKDIR for a clean, reproducible build."
	exit 1
fi
export BUILD_DIR_NAME
export HAIKU_DONT_FETCH_PACKAGES=0
prep
crosstools
bootstrap
GENERATED="$WORKPATH/$BUILD_DIR_NAME"
cd "$GENERATED"
# A fresh bootstrap repository makes the final Jam rules build every missing
# profile package and its dependency closure from the pinned HaikuPorts tree.
jam -q @nightly-mmc
IMAGE="$GENERATED/haiku-mmc.image"
if [ ! -s "$IMAGE" ]; then echo "Build completed without expected image: $IMAGE"; exit 1; fi
echo "ARM64 nightly image: $IMAGE"
