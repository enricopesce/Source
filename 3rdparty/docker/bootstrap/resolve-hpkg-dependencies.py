#!/usr/bin/env python3
"""Print a runtime HPKG package and its recursively required local packages."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Package:
    path: Path
    name: str
    version: str
    requires: tuple[str, ...]
    provides: tuple[str, ...]


def section(package_info: str, name: str) -> tuple[str, ...]:
    match = re.search(
        rf"^\s*{re.escape(name)}\s*\{{\s*\n(.*?)^\s*\}}",
        package_info,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        return ()
    return tuple(
        line.strip().strip('"')
        for line in match.group(1).splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


def capability(expression: str) -> str:
    return expression.split()[0].strip('"')


def is_runtime(path: Path) -> bool:
    name = path.name
    return not (
        "_source_rigged-" in name
        or "_debuginfo-" in name
        or name.endswith("-source.hpkg")
    )


def read_package(tool: Path, path: Path, info_path: Path, env: dict[str, str]) -> Package:
    subprocess.run(
        [str(tool), "extract", "-i", str(info_path), str(path)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    info = info_path.read_text(encoding="utf-8", errors="replace")
    name = re.search(r"^\s*name\s+(.+?)\s*$", info, re.MULTILINE)
    version = re.search(r"^\s*version\s+(.+?)\s*$", info, re.MULTILINE)
    if not name or not version:
        raise ValueError(f"Missing package name or version in {path}")
    return Package(
        path=path,
        name=name.group(1).strip().strip('"'),
        version=version.group(1).strip().strip('"'),
        requires=section(info, "requires"),
        provides=section(info, "provides"),
    )


def package_order(package: Package) -> tuple[bool, str, str]:
    # Prefer regular runtime packages over bootstrap variants, then sort
    # deterministically by version and path when a capability has providers.
    return (
        "_bootstrap" not in package.version and "_bootstrap" not in package.name,
        package.version,
        str(package.path),
    )


def main() -> int:
    if len(sys.argv) < 4:
        print(
            "usage: resolve-hpkg-dependencies.py PACKAGE_TOOL ROOT_HPKG PACKAGE_DIR...",
            file=sys.stderr,
        )
        return 2

    tool = Path(sys.argv[1]).resolve()
    root_path = Path(sys.argv[2]).resolve()
    package_dirs = [Path(value).resolve() for value in sys.argv[3:]]
    env = os.environ.copy()
    packages: dict[Path, Package] = {}
    providers: dict[str, list[Package]] = {}

    with tempfile.TemporaryDirectory(prefix="haiku-hpkg-info-") as temporary:
        info_dir = Path(temporary)
        candidates = sorted(
            {path for directory in package_dirs for path in directory.glob("*.hpkg") if is_runtime(path)}
        )
        candidates = sorted(set(candidates) | {root_path})
        for index, path in enumerate(candidates):
            package = read_package(tool, path, info_dir / f"{index}.PackageInfo", env)
            packages[path] = package
            for provided in package.provides:
                providers.setdefault(capability(provided), []).append(package)

    for choices in providers.values():
        choices.sort(key=package_order, reverse=True)

    if root_path not in packages:
        raise ValueError(f"Root package was not indexed: {root_path}")

    base_packages = set(os.environ.get("HAIKU_NETSURF_BASE_PACKAGES", "").split())
    included: set[Path] = set()
    unresolved: set[str] = set()
    pending = [packages[root_path]]
    while pending:
        package = pending.pop()
        if package.path in included or package.name in base_packages:
            continue
        included.add(package.path)
        for requirement in package.requires:
            required = capability(requirement)
            choices = providers.get(required, [])
            if choices:
                pending.append(choices[0])
            elif required != "haiku":
                unresolved.add(required)

    if unresolved:
        print(
            "Unresolved NetSurf requirements expected from the Haiku base image: "
            + ", ".join(sorted(unresolved)),
            file=sys.stderr,
        )
    print(f"Resolved {len(included)} NetSurf runtime HPKGs", file=sys.stderr)
    for path in sorted(included, key=lambda item: (packages[item].name, packages[item].version)):
        print(path)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"NetSurf HPKG dependency resolution failed: {error}", file=sys.stderr)
        raise SystemExit(1)
