#!/usr/bin/env python3
"""Inspect the .debug section and Debug directory of a PE file.

Usage: pe-debug.py <exe>

Prints whether the file has a .debug section, its size, and the Debug
data-directory entry (CodeView / RSDS) if present.
"""
import struct
import sys


def read_pe(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"MZ":
        raise SystemExit("not a PE file")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off:pe_off + 4] != b"PE\x00\x00":
        raise SystemExit("no PE signature")
    coff = pe_off + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    if magic == 0x20B:  # PE32+
        dd_off = opt + 112
    elif magic == 0x10B:  # PE32
        dd_off = opt + 96
    else:
        raise SystemExit(f"unknown optional header magic {magic:#x}")
    n_dd = struct.unpack_from("<I", data, opt + 92)[0] if magic == 0x20B else \
        struct.unpack_from("<I", data, opt + 92)[0]
    debug_rva, debug_size = struct.unpack_from("<II", data, dd_off + 6 * 8)
    sec_off = opt + opt_size
    sections = []
    for i in range(nsec):
        base = sec_off + i * 40
        name = data[base:base + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, base + 8)
        sections.append((name, vaddr, vsize, raw_ptr, raw_size))
    print(f"sections: {', '.join(s[0] for s in sections)}")
    debug_sec = [s for s in sections if s[0] == ".debug"]
    if debug_sec:
        name, vaddr, vsize, raw_ptr, raw_size = debug_sec[0]
        print(f".debug section: vaddr={vaddr:#x} vsize={vsize:#x} "
              f"raw_ptr={raw_ptr:#x} raw_size={raw_size:#x}")
        raw = data[raw_ptr:raw_ptr + raw_size]
        if raw[:4] == b"RSDS":
            guid = raw[4:20]
            age = struct.unpack_from("<I", raw, 20)[0]
            pdb = raw[24:].split(b"\x00")[0]
            print(f"  CodeView RSDS: guid={guid.hex()} age={age} pdb={pdb!r}")
        else:
            print(f"  .debug content head: {raw[:32].hex()}")
    else:
        print(".debug section: ABSENT")
    if debug_rva:
        print(f"Debug data directory: rva={debug_rva:#x} size={debug_size:#x}")
        # find which section contains debug_rva
        for name, vaddr, vsize, raw_ptr, raw_size in sections:
            if vaddr <= debug_rva < vaddr + max(vsize, raw_size):
                print(f"  -> inside section {name}")
                break
    else:
        print("Debug data directory: ABSENT")


if __name__ == "__main__":
    read_pe(sys.argv[1])
