#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
if [ -z "${TARGET_ARCH:-}" ]; then echo "TARGET_ARCH isn't set!"; exit 1; fi
: "${BUILD_DIR_NAME:=generated.$TARGET_ARCH}"
GENERATED="$WORKPATH/$BUILD_DIR_NAME"
if [ ! -d "$GENERATED" ]; then echo "$GENERATED is not available; run crosstools first"; exit 1; fi
cd "$GENERATED"
HAIKU_PORTER_EXTRA_OPTIONS="--debug" jam -q @bootstrap-raw
