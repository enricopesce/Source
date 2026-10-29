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
