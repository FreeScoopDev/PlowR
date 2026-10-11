#!/usr/bin/env python3
"""Fails if PlowR names an SF Symbol that iOS 26.0 doesn't have.

A missing symbol isn't a build error: the icon is silently blank. The
Documents tab and New Route showed nothing on iOS 26 and 27 until
2026-10-10 (doc.stack.fill, map.badge.plus). The deployment target is
iOS 26.0, so every symbol must exist there.

scripts/sf-symbols-ios26.0.txt lists the names iOS 26.0 has, taken from
SF Symbols' name_availability.plist in the iOS 26.5 simulator runtime (only
names whose first release is iOS 26.0 or earlier). Raise it, with the
deployment target, by regenerating it the same way.

Only literal names are checked: systemImage:, systemName:, icon:,
symbol:, and the cases of PlowRSymbol in DesignSystem.swift (case x = "...").
A name built at run time isn't seen.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KNOWN = set((ROOT / "scripts" / "sf-symbols-ios26.0.txt").read_text().split())
PATTERN = re.compile(r'\b(?:systemImage|systemName|icon|symbol):\s*"([a-z0-9]+(?:\.[a-z0-9]+)*)"')
# PlowRSymbol's cases: screens name icons through it, not as literals.
TOKEN_PATTERN = re.compile(r'^\s*case\s+\w+\s*=\s*"([a-z0-9]+(?:\.[a-z0-9]+)*)"')

failures = []
checked = 0
for folder in ("PlowR", "PlowRWidgets"):
    for path in sorted((ROOT / folder).rglob("*.swift")):
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            names = PATTERN.findall(line)
            if path.name == "DesignSystem.swift":
                names += TOKEN_PATTERN.findall(line)
            for name in names:
                checked += 1
                if name not in KNOWN:
                    failures.append(f"{path.relative_to(ROOT)}:{number}: '{name}' isn't an SF Symbol on iOS 26.0")

if checked == 0:
    print("::error::The symbol check found no symbol names, so it checked nothing.")
    sys.exit(1)
for failure in failures:
    print(f"::error::{failure}")
if failures:
    sys.exit(1)
print(f"SF Symbols check passed ({checked} names).")
