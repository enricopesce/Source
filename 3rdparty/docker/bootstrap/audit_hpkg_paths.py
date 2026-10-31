#!/usr/bin/env python3
"""Audit the exact HPKG files selected for the nightly-mmc image."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

SYSTEM_DIRECTORIES = {
    "add-ons",
    "apps",
    "bin",
    "boot",
    "cache",
    "data",
    "demos",
    "develop",
    "documentation",
    "lib",
    "non-packaged",
    "packages",
    "preferences",
    "servers",
    "settings",
    "var",
}
CORE_HAIKU_ROOT_FILES = {"Deskbar", "Tracker", "runtime_loader"}
CORE_HAIKU_BOOT_PATHS = {"first-login", "PostInstallScript", "SetupEnvironment"}
STAGING_SEGMENTS = {
    ".self",
    "arm64-cross-tool-prefix",
    "cross-tools-arm64",
    "sources-build",
}
SYSTEM_COPY_MARKER = (
    "AppendToContainerCopyFilesScriptSingleFile "
    "<HaikuImage>haiku.image-copy-files-dummy-system/packages-"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def log_package_references(log_path: Path, selection_path: Path) -> list[str]:
    lines = log_path.read_text(errors="replace").splitlines()
    refs: list[str] = []
    saw_system_packages = False

    for index, line in enumerate(lines):
        variable = None
        for name in ("systemPackages", "otherPackages"):
            if f"echo \"{name}=\"" in line:
                variable = name
                break
        if variable is None:
            continue
        if variable == "systemPackages":
            saw_system_packages = True

        for candidate in lines[index + 1 : index + 16]:
            if candidate.startswith("script="):
                break
            if candidate.startswith("for value in "):
                refs.extend(re.findall(r"\"([^\"]+\\.hpkg)\"", candidate))
                break

    selection_lines = selection_path.read_text(errors="replace").splitlines()
    for line in selection_lines:
        for variable in ("systemPackages", "otherPackages"):
            if not line.startswith(f"{variable}="):
                continue
            if variable == "systemPackages":
                saw_system_packages = True
            refs.extend(re.findall(r"([A-Za-z0-9_./+-]+[.]hpkg)", line))

    for line in lines:
        if SYSTEM_COPY_MARKER not in line or ".hpkg" not in line:
            continue
        tail = line.split(SYSTEM_COPY_MARKER, 1)[1].strip()
        ref = tail.split()[0] if tail else ""
        if ref.endswith(".hpkg"):
            refs.append(ref)

    if not saw_system_packages:
        raise ValueError("Package selection file does not record systemPackages")
    if not refs:
        raise ValueError("No selected HPKG files found in Jam output or selection file")
    return sorted(set(refs))

def resolve_package_ref(ref: str, generated: Path, target_arch: str) -> tuple[Path, str]:
    container_prefix = f"/work/{generated.name}/"
    if ref.startswith(container_prefix):
        relative = ref[len(container_prefix) :]
    elif ref.startswith("/work/"):
        raise ValueError(f"HPKG reference is outside the selected workspace: {ref}")
    elif ref.startswith("/"):
        raise ValueError(f"absolute HPKG reference is not reproducible: {ref}")
    else:
        relative = ref

    rel_path = PurePosixPath(relative)
    if any(part in ("", ".", "..") for part in rel_path.parts):
        raise ValueError(f"unsafe HPKG reference: {ref}")

    candidates = [generated.joinpath(*rel_path.parts)]
    if len(rel_path.parts) == 1:
        name = rel_path.name
        candidates = [
            generated / "download" / name,
            generated / "objects" / "haiku" / target_arch / "packaging" / "packages" / name,
            generated / "objects" / "haiku" / target_arch / "packaging" / "repositories" / "HaikuPorts-sources-build" / "packages" / name,
            generated / "objects" / "haiku" / target_arch / "packaging" / "repositories" / "HaikuPortsCross-build" / "packages" / name,
        ]

    for candidate in candidates:
        if candidate.is_file():
            resolved = candidate.resolve()
            try:
                relative_to_generated = resolved.relative_to(generated.resolve())
            except ValueError as error:
                raise ValueError(f"HPKG resolves outside the workspace: {ref}") from error
            return resolved, relative_to_generated.as_posix()

    raise FileNotFoundError(f"selected HPKG is missing: {ref}")


def audit_entries(package_tool: Path, archive: Path, package_name: str) -> list[str]:
    process = subprocess.run(
        [str(package_tool), "list", "-p", str(archive)],
        check=False,
        text=True,
        capture_output=True,
        env=os.environ.copy(),
    )
    if process.returncode != 0:
        raise RuntimeError(
            f"cannot read {archive.name}: {process.stderr.strip() or process.stdout.strip()}"
        )

    issues: list[str] = []
    for entry in process.stdout.splitlines():
        if not entry or entry == ".PackageInfo":
            continue
        if entry.startswith("/"):
            issues.append(f"absolute path: {entry}")
            continue
        raw_parts = entry.split("/")
        if any(part in ("", ".", "..") for part in raw_parts):
            issues.append(f"unsafe path: {entry}")
            continue

        parts = PurePosixPath(entry).parts
        top = parts[0]
        standard_root = top in SYSTEM_DIRECTORIES
        haiku_core_root = package_name == "haiku" and (
            top in CORE_HAIKU_ROOT_FILES
            or top == "kernel_arm64"
        )
        loader_root = package_name == "haiku_loader" and top == "haiku_loader.efi"
        if not (standard_root or haiku_core_root or loader_root):
            issues.append(f"non-standard root: {entry}")
            continue

        if top == "boot" and len(parts) > 1:
            standard_boot_path = parts[1] in {"post-install", "pre-uninstall"}
            haiku_core_boot_path = (
                package_name == "haiku" and parts[1] in CORE_HAIKU_BOOT_PATHS
            )
            if not (standard_boot_path or haiku_core_boot_path):
                issues.append(f"non-standard boot path: {entry}")
                continue

        if any(
            part in STAGING_SEGMENTS
            or re.fullmatch(r"work-[0-9][A-Za-z0-9._+-]*", part)
            or re.fullmatch(r"generated\.[A-Za-z0-9_+-]+", part)
            for part in parts
        ):
            issues.append(f"build path leaked into package: {entry}")

    return issues


def package_metadata(
    package_tool: Path, archive: Path
) -> tuple[str, str, str]:
    with tempfile.TemporaryDirectory(prefix="haiku-hpkg-metadata-") as temporary:
        info_path = Path(temporary) / "PackageInfo"
        process = subprocess.run(
            [str(package_tool), "extract", "-i", str(info_path), str(archive)],
            check=False,
            text=True,
            capture_output=True,
            env=os.environ.copy(),
        )
        if process.returncode != 0:
            raise RuntimeError(
                f"cannot read package metadata for {archive.name}: "
                f"{process.stderr.strip() or process.stdout.strip()}"
            )
        info = info_path.read_text(encoding="utf-8", errors="replace")

    fields: dict[str, str] = {}
    for field in ("name", "version", "architecture"):
        match = re.search(rf"^\s*{field}\s+(.+?)\s*$", info, re.MULTILINE)
        if match:
            fields[field] = match.group(1).strip().strip('"')
    if any(field not in fields for field in ("name", "version", "architecture")):
        raise RuntimeError(f"invalid name/version/architecture metadata in {archive.name}")
    return fields["name"], fields["version"], fields["architecture"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-tool", required=True, type=Path)
    parser.add_argument("--generated", required=True, type=Path)
    parser.add_argument("--jam-log", required=True, type=Path)
    parser.add_argument("--selection-file", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--target-arch", default="arm64")
    args = parser.parse_args()

    try:
        refs = log_package_references(args.jam_log, args.selection_file)
        records: list[tuple[str, str, str, str, str]] = []
        failures: list[str] = []
        seen_archives: set[Path] = set()

        for ref in refs:
            try:
                archive, relative = resolve_package_ref(ref, args.generated, args.target_arch)
                if archive in seen_archives:
                    continue
                seen_archives.add(archive)
                name, version, architecture = package_metadata(
                    args.package_tool, archive
                )
                if architecture not in {args.target_arch, "any"}:
                    raise ValueError(
                        f"package architecture is {architecture}, expected "
                        f"{args.target_arch} or any"
                    )
                issues = audit_entries(args.package_tool, archive, name)
                if issues:
                    failures.extend(f"{archive.name}: {issue}" for issue in issues[:12])
                records.append(
                    (name, version, architecture, sha256_file(archive), relative)
                )
            except Exception as error:  # report each missing or unreadable selected package
                failures.append(f"{ref}: {error}")

        if failures:
            for failure in failures[:80]:
                print(f"FAIL {failure}", file=sys.stderr)
            if len(failures) > 80:
                print(f"FAIL ... {len(failures) - 80} further findings", file=sys.stderr)
            return 1

        records.sort(key=lambda row: (row[0], row[1], row[4]))
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.manifest.with_suffix(args.manifest.suffix + ".part")
        with temporary.open("w", newline="") as stream:
            stream.write("# format=2\n")
            writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
            writer.writerow(("package", "version", "architecture", "sha256", "archive"))
            writer.writerows(records)
        temporary.replace(args.manifest)
        print(f"Path audit passed: {len(records)} selected packages")
        print(f"Package manifest: {args.manifest}")
        return 0
    except Exception as error:
        print(f"Path audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
