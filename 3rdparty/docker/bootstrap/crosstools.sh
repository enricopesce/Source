#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
if [ -z "${TARGET_ARCH:-}" ]; then echo "TARGET_ARCH isn't set!"; exit 1; fi
: "${BUILD_DIR_NAME:=generated.$TARGET_ARCH}"
if [ ! -d "$WORKPATH/src" ]; then echo "$WORKPATH/src is not available; run prep first"; exit 1; fi
if [ "$TARGET_ARCH" != arm64 ]; then echo "This pinned nightly-mmc build currently supports TARGET_ARCH=arm64"; exit 1; fi
GENERATED="$WORKPATH/$BUILD_DIR_NAME"
mkdir -p "$GENERATED"
echo "Building ARM64 cross tools in $GENERATED"
cd "$GENERATED"
"$WORKPATH/src/haiku/configure" -j4 --build-cross-tools "$TARGET_ARCH" \
	--cross-tools-source "$WORKPATH/src/buildtools" \
	--bootstrap "$WORKPATH/src/haikuporter/haikuporter" \
	"$WORKPATH/src/haikuports.cross" "$WORKPATH/src/haikuports"
