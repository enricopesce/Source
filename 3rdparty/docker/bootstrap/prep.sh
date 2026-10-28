#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
LOCK_FILE=/usr/local/share/haiku-bootstrap/sources.lock
if [ ! -d "$WORKPATH" ]; then echo "$WORKPATH is not available!"; exit 1; fi
if [ ! -f "$LOCK_FILE" ]; then echo "Missing pinned source lock: $LOCK_FILE"; exit 1; fi
source "$LOCK_FILE"
mkdir -p "$WORKPATH/src"
clone_pinned() {
	local name="$1" url="$2" revision="$3" destination="$WORKPATH/src/$1"
	if [ -z "$revision" ] || [[ "$revision" == *SET_AFTER_COMMIT* ]]; then
		echo "No pinned revision configured for $name in $LOCK_FILE"; exit 1
	fi
	if [ ! -d "$destination/.git" ]; then git clone "$url" "$destination"
	elif [ -n "$(git -C "$destination" status --porcelain)" ]; then
		echo "$destination has local changes; use a new build workspace"; exit 1
	fi
	git -C "$destination" fetch --force origin "$revision"
	git -C "$destination" checkout --detach FETCH_HEAD
}
clone_pinned buildtools "$GIT_BUILDTOOLS" "$REF_BUILDTOOLS"
clone_pinned haikuporter "$GIT_HAIKUPORTER" "$REF_HAIKUPORTER"
clone_pinned haikuports "$GIT_HAIKUPORTS" "$REF_HAIKUPORTS"
clone_pinned haikuports.cross "$GIT_HAIKUPORTS_CROSS" "$REF_HAIKUPORTS_CROSS"
clone_pinned haiku "$GIT_HAIKU" "$REF_HAIKU"
mkdir -p "$WORKPATH/bin"
if [ ! -x "$WORKPATH/bin/jam" ]; then
	cd "$WORKPATH/src/buildtools/jam"
	rm -rf bin.*
	make
	cp -f bin.linuxx86/jam "$WORKPATH/bin/jam"
fi
