#!/usr/bin/env python3
"""Find a HaikuPorts recipe that declares a required build provide."""
import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print(f"usage: {sys.argv[0]} <haikuports-root> <provide>", file=sys.stderr)
    raise SystemExit(2)

root = Path(sys.argv[1])
provide = sys.argv[2].strip().split()[0]
provide = re.sub(r"_(?:x86_64|riscv64|arm64|x86|arm|ppc|m68k|sparc)$", "", provide)
provide = re.sub(r"\$[A-Za-z_][A-Za-z0-9_]*$", "", provide)
pattern = re.compile(
    r"^\s*" + re.escape(provide) + r"(?:\$[A-Za-z_][A-Za-z0-9_]*)?\s*=",
    re.MULTILINE,
)
providers = set()
for recipe in sorted(root.rglob("*.recipe")):
    try:
        source = recipe.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        continue
    if pattern.search(source):
        providers.add(recipe.parent.name)
        continue

    # Python ports generate per-version package provides in shell loops, so
    # their concrete names (for example installer_python310) are not literal.
    dynamic = re.fullmatch(
        r"(?P<port>[A-Za-z0-9_.+-]+)_python(?P<version>3(?:\.\d+|\d{1,2}))",
        provide,
    )
    versions = re.search(r"PYTHON_VERSIONS\s*=\s*\(([^)]*)\)", source)
    if dynamic and versions and re.search(r"PROVIDES_\$pythonPackage", source):
        version = dynamic.group("version")
        version = version if "." in version else f"3.{version[1:]}"
        recipe_port = recipe.parent.name.replace("-", "_")
        requested_port = dynamic.group("port").replace("-", "_")
        if recipe_port == requested_port and version in versions.group(1).split():
            providers.add(recipe.parent.name)

if len(providers) == 1:
    print(next(iter(providers)))
    raise SystemExit(0)
if len(providers) > 1:
    feature = provide.split(":", 1)[-1]
    hint = feature[3:] if feature.startswith("lib") else feature
    preferred = providers.intersection({feature, hint})
    if len(preferred) == 1:
        print(next(iter(preferred)))
        raise SystemExit(0)
    print(f"ambiguous providers for {provide}: {', '.join(sorted(providers))}", file=sys.stderr)
    raise SystemExit(1)

print(f"no HaikuPorts recipe declares {provide}", file=sys.stderr)
raise SystemExit(1)
