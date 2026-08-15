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
    needle = "  esac\n}"
    addition = (
        "  esac\n"
        "  # Reproducible builds: the linker (or cv2pdb on GitHub Actions)\n"
        "  # stamps a random CodeView PDB GUID into the .debug section of\n"
        "  # every executable. Drop it at the very end of build(), after\n"
        "  # the PDB/strip step, so a rebuild on the same SDK snapshot is\n"
        "  # byte-identical. objcopy only accepts one input file, so run it\n"
        "  # once per executable (in-place).\n"
        '  find . -name "*.exe" -exec objcopy --remove-section=.debug {} \\;\n'
        "}"
    )
    if needle not in s:
        sys.stderr.write(f"pattern {needle!r} not found in {path}\n")
        return 1
    s = s.replace(needle, addition, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
