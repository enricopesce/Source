#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
: "${TARGET_ARCH:=arm64}"
: "${BUILD_DIR_NAME:=generated.$TARGET_ARCH}"
if [ "$TARGET_ARCH" != arm64 ]; then
	echo "Fortran cross-tool bootstrap currently supports ARM64 only" >&2
	exit 1
fi
GENERATED="$WORKPATH/$BUILD_DIR_NAME"
CROSS_TOOLS="$GENERATED/cross-tools-arm64"
BUILD="$GENERATED/cross-tools-arm64-fortran-build"
SYSROOT="$GENERATED/cross-tools-arm64-fortran-sysroot"
PACKAGE="$GENERATED/objects/linux/x86_64/release/tools/package/package"
PACKAGES="$GENERATED/objects/haiku/$TARGET_ARCH/packaging/packages"
GCC_VERSION=$(cat "$WORKPATH/src/buildtools/gcc/gcc/BASE-VER")
CROSS_DEVEL="$PACKAGES/haiku_cross_devel_sysroot_stage1_${TARGET_ARCH}.hpkg"
RUNTIME="$PACKAGES/haiku.hpkg"
DEVEL="$PACKAGES/haiku_devel.hpkg"
for input in "$CROSS_TOOLS/bin/aarch64-unknown-haiku-gcc" "$PACKAGE" "$CROSS_DEVEL" "$RUNTIME" "$DEVEL"; do
	if [ ! -s "$input" ]; then
		echo "Missing ARM64 Fortran cross-tool input: $input" >&2
		exit 1
	fi
done
if [ -x "$CROSS_TOOLS/bin/aarch64-unknown-haiku-gfortran" ] && [ -x "$CROSS_TOOLS/libexec/gcc/aarch64-unknown-haiku/$GCC_VERSION/f951" ]; then
	echo "ARM64 cross-GFortran is already available: $CROSS_TOOLS/bin/aarch64-unknown-haiku-gfortran"
	exit 0
fi
rm -rf "$BUILD" "$SYSROOT"
mkdir -p "$BUILD" "$SYSROOT"
for package in "$CROSS_DEVEL" "$RUNTIME" "$DEVEL"; do
	"$PACKAGE" extract -C "$SYSROOT" "$package"
done
export PATH="$CROSS_TOOLS/bin:$PATH"
export LD_LIBRARY_PATH="$GENERATED/objects/linux/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cd "$BUILD"
"$WORKPATH/src/buildtools/gcc/configure" \
	--prefix="$CROSS_TOOLS" --target=aarch64-unknown-haiku \
	--disable-nls --disable-shared --with-system-zlib --enable-languages=c,c++,fortran \
	--enable-lto --enable-frame-pointer --enable-__cxa-atexit --enable-threads=posix \
	--with-default-libstdcxx-abi=gcc4-compatible --with-sysroot="$SYSROOT" \
	--disable-maintainer-mode --disable-libgomp --disable-libatomic --disable-multilib
make -j4 all-host
make -j4 all-gcc
make -j4 install-host install-gcc
test -x "$CROSS_TOOLS/bin/aarch64-unknown-haiku-gfortran"
test -x "$CROSS_TOOLS/libexec/gcc/aarch64-unknown-haiku/$GCC_VERSION/f951"
