#!/usr/bin/env python3
"""Attribute a file offset to a PE section and show the section layout.

Usage: pe-segments.py <exe> [first_diff_offset]

Prints every section with its raw pointer/size and, when a decimal
first-diff offset is given, states which section (if any) contains it.
This works even for sections that objcopy cannot extract from a PE
(such as .reloc).
"""
import struct
import sys


def read_pe(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"MZ":
        raise SystemExit("not a PE file")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    coff = pe_off + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    sec_off = opt + opt_size
    sections = []
    for i in range(nsec):
        base = sec_off + i * 40
        name = data[base:base + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, base + 8)
        sections.append((name, vaddr, vsize, raw_ptr, raw_size))
    return data, sections


def main():
    path = sys.argv[1]
    off = int(sys.argv[2], 0) if len(sys.argv) > 2 else None
    data, sections = read_pe(path)
    total = len(data)
    for name, vaddr, vsize, raw_ptr, raw_size in sections:
        lo = raw_ptr
        hi = raw_ptr + raw_size
        mark = ""
        if off is not None and lo <= off < hi:
            mark = "  <== first diff here (offset %#x inside section)" % (off - lo)
        print(f"  {name:8s} vaddr={vaddr:#10x} vsize={vsize:#8x} "
              f"raw_ptr={raw_ptr:#10x} raw_size={raw_size:#8x}{mark}")
    if off is not None:
        # file size vs last section end (padding beyond the last section)
        last = sections[-1]
        last_end = last[4] + last[3]  # raw_ptr + raw_size
        if off >= last_end:
            print(f"  first diff {off:#x} is beyond the last section "
                  f"(end {last_end:#x}), in trailing padding ({total - last_end} bytes)")
        elif off < 0x600:
            print(f"  first diff {off:#x} is inside the PE header")


if __name__ == "__main__":
    main()
