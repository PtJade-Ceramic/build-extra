#!/usr/bin/env python3
"""Patch the mingw-w64-git PKGBUILD for reproducible verification.

Inserts a step into build() that strips the linker-generated CodeView
PDB GUID (the .debug section) from every executable before packaging,
so a second build on the same SDK snapshot is byte-identical. This
mirrors the change that an upstream reproducible-build effort would
make.

Idempotent: running it again on an already-patched PKGBUILD is a no-op.
"""

import sys


def main():
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        s = f.read()
    if "remove-section=.debug" in s:
        return 0
    needle = "  make $targets &&"
    addition = (
        "  # Reproducible builds: the linker stamps a random CodeView\n"
        "  # PDB GUID into the .debug section of every executable. Drop\n"
        "  # it before packaging so a rebuild on the same SDK snapshot\n"
        "  # is byte-identical. objcopy only accepts one input file, so\n"
        "  # run it once per executable (in-place).\n"
        '  find . -name "*.exe" -exec objcopy --remove-section=.debug {} \\;\n'
    )
    if needle not in s:
        sys.stderr.write(f"pattern {needle!r} not found in {path}\n")
        return 1
    s = s.replace(needle, needle + "\n" + addition, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
