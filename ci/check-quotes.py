#!/usr/bin/env python3
"""Scan the workflow for stray single quotes inside --login -c '...' blocks."""
import re
import sys

path = r"c:\Users\tbyta\GitHub\build-extra\.github\workflows\reproducible-verify.yml"
lines = open(path, encoding="utf-8").read().splitlines()

in_block = False
block_start = 0
for i, l in enumerate(lines, 1):
    if "--login -c '" in l:
        in_block = True
        block_start = i
        continue
    if in_block:
        s = l.strip()
        # End of block: closing quote followed by 'bash ...' or a redirect.
        if "' bash " in l or re.match(r"^'(\s|>|$)", s):
            in_block = False
            continue
        if "'" in l:
            print(f"line {i} (block starts {block_start}): {l.strip()[:120]}")
            sys.exit(1)

print("OK: no stray single quotes inside --login -c blocks")
