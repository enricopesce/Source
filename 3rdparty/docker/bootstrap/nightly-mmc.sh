#!/bin/bash
set -euo pipefail
: "${WORKPATH:=/work}"
: "${TARGET_ARCH:=arm64}"
: "${BUILD_DIR_NAME:=generated.$TARGET_ARCH}"
if [ "$TARGET_ARCH" != arm64 ]; then echo "This profile is ARM64 only (TARGET_ARCH=arm64)"; exit 1; fi
if [ "${RESUME:-0}" != 1 ] && [ -e "$WORKPATH/$BUILD_DIR_NAME" ]; then
	echo "$WORKPATH/$BUILD_DIR_NAME already exists."
	echo "Use RESUME=1 to continue it, or select a new WORKDIR for a clean build."
	exit 1
fi
export TARGET_ARCH BUILD_DIR_NAME
put_work_bin_last() {
	local entry new_path=""
	local -a path_entries
	IFS=: read -r -a path_entries <<< "$PATH"
	for entry in "${path_entries[@]}"; do
		if [ -n "$entry" ] && [ "$entry" != "$WORKPATH/bin" ]; then
			new_path="${new_path:+$new_path:}$entry"
		fi
	done
	export PATH="$new_path:$WORKPATH/bin"
}
use_host_jam() {
	HOST_JAM="$WORKPATH/src/buildtools/jam/bin.linuxx86/jam"
	if [ ! -x "$HOST_JAM" ]; then
		echo "Host Jam executable is missing: $HOST_JAM" >&2
		return 1
	fi
	local host_jam_dir=${HOST_JAM%/*}
	PATH="${PATH%:$WORKPATH/bin}"
	export PATH="$PATH:$host_jam_dir:$WORKPATH/bin"
}
put_work_bin_last
export HAIKU_BOOTSTRAP_SOURCES_PROFILE=@nightly-mmc
if [ "${RESUME:-0}" = 1 ]; then
	if [ ! -d "$WORKPATH/src/haiku" ] || [ ! -d "$WORKPATH/$BUILD_DIR_NAME" ]; then
		echo "RESUME=1 requires existing source checkouts and $WORKPATH/$BUILD_DIR_NAME"
		exit 1
	fi
	echo "Resuming ARM64 build in $WORKPATH/$BUILD_DIR_NAME"
	use_host_jam
	build-cross-fortran
else
	prep
	use_host_jam
	crosstools
	bootstrap
	build-cross-fortran
fi

GENERATED="$WORKPATH/$BUILD_DIR_NAME"
PACKAGE_ROOT="$GENERATED/objects/haiku/$TARGET_ARCH/packaging"
CROSS_REPOSITORY="$PACKAGE_ROOT/repositories/HaikuPortsCross-build"
BOOTSTRAP_PACKAGE_REPOSITORY="$CROSS_REPOSITORY/packages"
PORT_REPOSITORY="$PACKAGE_ROOT/repositories/HaikuPorts-sources-build"
PORT_PACKAGES="$PORT_REPOSITORY/packages"
HAIKU_PORTS_SOURCE_PACKAGE="$GENERATED/download/haikuports_source-1.0.0-1-any.hpkg"
export HAIKU_PORTS_SOURCE_PACKAGE
HOST_TOOLS="$GENERATED/objects/linux/x86_64/release/tools"
UNBOOTSTRAP="$GENERATED/.unbootstrap"

export PATH="$HOST_TOOLS/addattr:$HOST_TOOLS/package:$HOST_TOOLS/locale:$HOST_TOOLS/rc:$HOST_TOOLS:$PATH"
export LD_LIBRARY_PATH="$GENERATED/objects/linux/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HAIKU_SOURCE_DIR="$WORKPATH/src/haiku"

mkdir -p "$WORKPATH/bin" "$PORT_PACKAGES"
cp /usr/local/bin/haiku-host-uudecode "$WORKPATH/bin/uudecode"
chmod 0755 "$WORKPATH/bin/uudecode"

mkdir -p "$PORT_PACKAGES"
shopt -s nullglob
if [ "${RESUME:-0}" = 1 ] && [ -e "$UNBOOTSTRAP/.converted" ]; then
	echo "Reusing converted bootstrap packages"
else
	mkdir -p "$UNBOOTSTRAP/packages"
bootstrap_inputs=("$BOOTSTRAP_PACKAGE_REPOSITORY/.obsolete"/*_bootstrap*.hpkg)
if [ ${#bootstrap_inputs[@]} -eq 0 ]; then
	bootstrap_inputs=("$BOOTSTRAP_PACKAGE_REPOSITORY"/*_bootstrap*.hpkg)
fi
if [ ${#bootstrap_inputs[@]} -eq 0 ]; then
	echo "No bootstrap packages found under $BOOTSTRAP_PACKAGE_REPOSITORY"
	exit 1
fi
cp "${bootstrap_inputs[@]}" "$UNBOOTSTRAP/packages/"
(
	cd "$UNBOOTSTRAP"
	"$HAIKU_SOURCE_DIR/3rdparty/pulkomandy/unbootstrap.sh"
)
converted_packages=("$UNBOOTSTRAP"/*.hpkg)
if [ ${#converted_packages[@]} -eq 0 ]; then
	echo "Bootstrap package conversion produced no packages"
	exit 1
fi
cp -f "${converted_packages[@]}" "$PORT_PACKAGES/"
	touch "$UNBOOTSTRAP/.converted"
fi

CROSS_DEVEL_PACKAGE="$PACKAGE_ROOT/packages/haiku_cross_devel_sysroot_stage1_${TARGET_ARCH}.hpkg"
HAIKU_RUNTIME_PACKAGE="$PACKAGE_ROOT/packages/haiku.hpkg"
HAIKU_DEVEL_PACKAGE="$PACKAGE_ROOT/packages/haiku_devel.hpkg"
HPORTS_CONFIG="$PORT_REPOSITORY/haikuports.conf"
if [ ! -s "$HPORTS_CONFIG" ] || [ ! -s "$CROSS_DEVEL_PACKAGE" ] || [ ! -s "$HAIKU_RUNTIME_PACKAGE" ] || [ ! -s "$HAIKU_DEVEL_PACKAGE" ]; then
	echo "Missing HaikuPorter cross-build inputs under $PACKAGE_ROOT"
	exit 1
fi
mkdir -p "$GENERATED/download"
cp -f "$HAIKU_RUNTIME_PACKAGE" "$HAIKU_DEVEL_PACKAGE" "$GENERATED/download/"

mwx_firmware_archive="$GENERATED/download/mwx-firmware-20260309p0.tgz"
mwx_firmware_sha256="777e0e188aeeece6bb294b1c2bcf54926b213276e31a86df1c04cf4248b41345"
if ! printf '%s  %s\n' "$mwx_firmware_sha256" "$mwx_firmware_archive" | sha256sum -c - >/dev/null 2>&1; then
	mwx_firmware_temporary="$mwx_firmware_archive.part"
	if ! printf '%s  %s\n' "$mwx_firmware_sha256" "$mwx_firmware_temporary" | sha256sum -c - >/dev/null 2>&1; then
		rm -f "$mwx_firmware_temporary"
		wget -q -O "$mwx_firmware_temporary" https://firmware.openbsd.org/firmware/7.9/mwx-firmware-20260309p0.tgz
		printf '%s  %s\n' "$mwx_firmware_sha256" "$mwx_firmware_temporary" | sha256sum -c -
	fi
	mv -f "$mwx_firmware_temporary" "$mwx_firmware_archive"
fi

cd "$GENERATED"
jam_log="$WORKPATH/nightly-mmc-jam.log"
porter_log="$WORKPATH/nightly-mmc-porter.log"
ports_root="$WORKPATH/src/haikuports"
declare -A BUILDING_PORTS=()
build_port() {
	local port_name="$1"
	local required_output="${2:-}"
	local depth="${3:-0}"
	local package dependency provider runtime_package_list
	local -a runtime_packages port_outputs

	if (( depth > 32 )); then
		echo "Dependency build exceeded 32 levels at $port_name" >&2
		return 1
	fi
	if [[ ${BUILDING_PORTS[$port_name]+building} ]]; then
		echo "Cycle while building HaikuPorts dependency $port_name" >&2
		return 1
	fi
	BUILDING_PORTS[$port_name]=1

	runtime_packages=()
	for package in "$PORT_PACKAGES"/*.hpkg; do
		case "$package" in *-source.hpkg|*_source_rigged-*.hpkg|*-debuginfo.hpkg|haikuports_source-*.hpkg) continue ;; esac
		runtime_packages+=("$package")
	done
	if [ ${#runtime_packages[@]} -eq 0 ]; then
		echo "No runtime packages available for HaikuPorter" >&2
		unset "BUILDING_PORTS[$port_name]"
		return 1
	fi
	runtime_package_list=$(IFS=,; echo "${runtime_packages[*]}")
	if python3 "$WORKPATH/src/haikuporter/haikuporter" \
		--config="$HPORTS_CONFIG" \
		--cross-devel-package "$CROSS_DEVEL_PACKAGE" \
		--cross-runtime-package "$HAIKU_RUNTIME_PACKAGE,$HAIKU_DEVEL_PACKAGE,$runtime_package_list" \
		--no-package-obsoletion --missing-dependencies "$port_name" \
		>"$porter_log" 2>&1; then
		port_outputs=("$PORT_PACKAGES"/*.hpkg)
		if [ ${#port_outputs[@]} -eq 0 ]; then
			echo "HaikuPorter produced no package outputs for $port_name" >&2
			tail -n 20 "$porter_log"
			unset "BUILDING_PORTS[$port_name]"
			return 1
		fi
		cp -f "${port_outputs[@]}" "$GENERATED/download/"
		if [ -n "$required_output" ] && [ ! -s "$GENERATED/download/$required_output" ]; then
			echo "HaikuPorter did not produce the requested package $required_output" >&2
			tail -n 30 "$porter_log"
			unset "BUILDING_PORTS[$port_name]"
			return 1
		fi
		unset "BUILDING_PORTS[$port_name]"
		return 0
	fi

	dependency=$(sed -nE 's/.*Reason: build-(requires|prerequires) "([^"]+)".*/\2/p' "$porter_log" | head -n 1)
	if [ -z "$dependency" ]; then
		echo "HaikuPorter failed for $port_name; log: $porter_log" >&2
		tail -n 30 "$porter_log"
		unset "BUILDING_PORTS[$port_name]"
		return 1
	fi
	if ! provider=$(/usr/local/bin/find-port-provider "$ports_root" "$dependency"); then
		echo "Cannot resolve HaikuPorts provider for $dependency needed by $port_name" >&2
		tail -n 30 "$porter_log"
		unset "BUILDING_PORTS[$port_name]"
		return 1
	fi
	if [ "$provider" = "$port_name" ]; then
		echo "Port $port_name cannot resolve its own build requirement $dependency" >&2
		tail -n 30 "$porter_log"
		unset "BUILDING_PORTS[$port_name]"
		return 1
	fi
	echo "Building missing dependency $dependency from HaikuPorts port $provider"
	if ! build_port "$provider" "" "$((depth + 1))"; then
		unset "BUILDING_PORTS[$port_name]"
		return 1
	fi
	unset "BUILDING_PORTS[$port_name]"
	build_port "$port_name" "$required_output" "$((depth + 1))"
}
# HPKG entries are relative to /boot/system; omit the boot/system prefix here.
build_haikuports_source_package() {
	local source_revision package_file package_root package_contents package_info
	source_revision=$(git -C "$WORKPATH/src/haikuports" rev-parse HEAD)
	package_file="$HAIKU_PORTS_SOURCE_PACKAGE"
	package_root="$GENERATED/haikuports-source-package"
	package_contents="$package_root/data/haikuports"
	package_info="$GENERATED/haikuports-source.PackageInfo"
	rm -rf "$package_root"
	rm -f "$package_file"
	mkdir -p "$package_contents" "$GENERATED/download"
	git -C "$WORKPATH/src/haikuports" archive --format=tar "$source_revision" \
		| tar -xf - -C "$package_contents"
	cp -a "$WORKPATH/src/haikuports/.git" "$package_contents/.git"
	if [ "$(git -C "$package_contents" rev-parse HEAD)" != "$source_revision" ]; then
		echo "Packaged HaikuPorts checkout does not match pinned revision $source_revision" >&2
		return 1
	fi
	cat > "$package_info" <<EOF
name haikuports_source
version 1.0.0-1
architecture any
summary "Pinned HaikuPorts source repository"
description "HaikuPorts checkout at $source_revision. Copy it to writable storage before editing."
packager "RenkuOS ARM64 build"
vendor "RenkuOS"
licenses { "MIT" }
copyrights { "2002-2017 The HaikuPorts Project" }
provides { haikuports_source = 1.0.0 }
requires { haiku }
EOF
	package create -q -C "$package_root" -i "$package_info" "$package_file"
	rm -f "$package_info"
	echo "Packaged HaikuPorts Git checkout at $source_revision"
}
build_haikuporter_runtime_package() {
	local source_revision package_file package_root package_contents package_info wrapper
	source_revision=$(git -C "$WORKPATH/src/haikuporter" rev-parse HEAD)
	package_file="$GENERATED/download/haikuporter-1.5.3-2-any.hpkg"
	package_root="$GENERATED/haikuporter-runtime-package"
	package_contents="$package_root/data/haikuporter"
	package_info="$GENERATED/haikuporter-renkuos.PackageInfo"
	wrapper="$package_root/bin/haikuporter"
	rm -rf "$package_root"
	rm -f "$package_file"
	mkdir -p "$package_contents" "${wrapper%/*}" "$GENERATED/download"
	git -C "$WORKPATH/src/haikuporter" archive --format=tar "$source_revision" \
		| tar -xf - -C "$package_contents"
	cp -a "$WORKPATH/src/haikuporter/.git" "$package_contents/.git"
	if [ "$(git -C "$package_contents" rev-parse HEAD)" != "$source_revision" ]; then
		echo "Packaged HaikuPorter checkout does not match pinned revision $source_revision" >&2
		return 1
	fi
	cat > "$wrapper" <<'EOF'
#!/bin/sh
exec python3.14 /boot/system/data/haikuporter/haikuporter "$@"
EOF
	chmod 0755 "$wrapper"
	cat > "$package_info" <<EOF
name haikuporter
version 1.5.3-2
architecture any
summary "RenkuOS HaikuPorter ARM64 build environment"
description "HaikuPorter fork at $source_revision, with a native Python 3.14 launcher."
packager "RenkuOS ARM64 build"
vendor "RenkuOS"
licenses { "MIT" }
copyrights { "2013-2026 Haiku, Inc." }
provides {
	haikuporter = 1.5.3
	cmd:haikuporter = 1.5.3
}
requires {
	haiku
	cmd:git
	cmd:python3.14 >= 3.14.9
}
EOF
	package create -q -C "$package_root" -i "$package_info" "$package_file"
	rm -f "$package_info"
	echo "Packaged HaikuPorter fork at $source_revision"
}
build_haikuports_source_package
build_haikuporter_runtime_package
if ! compgen -G "$PORT_PACKAGES/python3.14-*-arm64.hpkg" >/dev/null; then
	echo "Building ARM64 Python 3.14 runtime for native HaikuPorter"
	build_port python3.14 ""
fi
python314_packages=("$PORT_PACKAGES"/python3.14-*-arm64.hpkg)
if [ ${#python314_packages[@]} -ne 1 ]; then
	echo "Expected one ARM64 Python 3.14 package, found ${#python314_packages[@]}" >&2
	exit 1
fi
haikuporter_package="$GENERATED/download/haikuporter-1.5.3-2-any.hpkg"
HAIKU_LOCAL_RUNTIME_PACKAGES_FILE="$GENERATED/local-runtime-packages.jam"
HAIKU_IMAGE_BASE_PACKAGES="bzip2 file git libiconv libjpeg_turbo libpng16 openssl3 xz_utils zlib zstd"
export HAIKU_LOCAL_RUNTIME_PACKAGES_FILE HAIKU_IMAGE_BASE_PACKAGES
local_runtime_roots=("$haikuporter_package" "${python314_packages[0]}")
{
	printf 'HAIKU_LOCAL_RUNTIME_PACKAGES =\n'
	/usr/local/bin/resolve-hpkg-dependencies \
		"$HOST_TOOLS/package/package" "$PORT_PACKAGES" \
		"$BOOTSTRAP_PACKAGE_REPOSITORY" -- "${local_runtime_roots[@]}" \
		| while IFS= read -r package_path; do printf '\t%s\n' "$package_path"; done
	printf ';\n'
} > "$HAIKU_LOCAL_RUNTIME_PACKAGES_FILE"

while ! "$HOST_JAM" -q @nightly-mmc >"$jam_log" 2>&1; do
	missing_package=""
	if grep -q 'HAIKU_NO_DOWNLOADS is set' "$jam_log" || grep -Eq "package 'download/[A-Za-z0-9_.+-]+\.hpkg' does not exist" "$jam_log"; then
		# With HAIKU_NO_DOWNLOADS, Jam reports a repository-cache failure when
		# profile packages are absent instead of naming the first missing file.
		while IFS= read -r package_path; do
			package_name=${package_path#download/}
			if [ ! -s "$GENERATED/download/$package_name" ]; then
				missing_package=$package_name
				break
			fi
		done < <(grep -oE 'download/[A-Za-z0-9_.+-]+\.hpkg' "$jam_log" | sort -u)
	fi
	if [ -z "$missing_package" ]; then
		echo "nightly-mmc stopped without a missing package target; log: $jam_log"
		tail -n 20 "$jam_log"
		exit 1
	fi
	port_name=$(printf '%s\n' "$missing_package" | sed -E 's/-[0-9].*\.hpkg$//')
	case "$port_name" in
		*_source_rigged) port_name=${port_name%_source_rigged} ;;
		*_source|*_debuginfo) port_name=${port_name%_*} ;;
	esac
	echo "Building missing package $missing_package from HaikuPorts port $port_name"
    if ! build_port "$port_name" "$missing_package"; then
        exit 1
    fi
done

IMAGE="$GENERATED/haiku-mmc.image"
if [ ! -s "$IMAGE" ]; then echo "Build completed without expected image: $IMAGE"; exit 1; fi
manifest="$IMAGE.build-info"
manifest_temporary="$manifest.part"
{
	printf 'format=1\nprofile=nightly-mmc\ntarget_arch=%s\n' "$TARGET_ARCH"
	printf 'build_driver_revision=%s\n' "${BUILD_DRIVER_REV:-unrecorded}"
	printf 'host_build_machine=%s\n' "$(/usr/bin/gcc -dumpmachine)"
	printf 'host_gcc_version=%s\n' "$(/usr/bin/gcc -dumpfullversion)"
	printf 'haikuports_source_package_sha256=%s\n' "$(sha256sum "$GENERATED/download/haikuports_source-1.0.0-1-any.hpkg" | cut -d' ' -f1)"
	printf 'haikuporter_runtime_package_sha256=%s\n' "$(sha256sum "$GENERATED/download/haikuporter-1.5.3-2-any.hpkg" | cut -d' ' -f1)"
	printf 'python314_package_sha256=%s\n' "$(sha256sum "${python314_packages[0]}" | cut -d' ' -f1)"
	printf 'local_runtime_package_list_sha256=%s\n' "$(sha256sum "$HAIKU_LOCAL_RUNTIME_PACKAGES_FILE" | cut -d' ' -f1)"
	for source_repo in buildtools haiku haikuporter haikuports haikuports.cross; do
		printf 'source_%s_revision=%s\n' "$source_repo" "$(git -C "$WORKPATH/src/$source_repo" rev-parse HEAD)"
	done
	printf 'haikuports_cross_patch_sha256=%s\n' \
		"$(sha256sum /usr/local/share/haiku-bootstrap/patches/arm64-bootstrap-cross-recipes.patch | cut -d' ' -f1)"
	printf 'mwx_firmware_sha256=%s\n' "$mwx_firmware_sha256"
	printf 'image_size_bytes=%s\n' "$(stat -c %s "$IMAGE")"
} > "$manifest_temporary"
mv -f "$manifest_temporary" "$manifest"
echo "ARM64 nightly image: $IMAGE"
echo "Build provenance: $manifest"
