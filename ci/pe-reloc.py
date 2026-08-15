#!/usr/bin/env python3
"""Dump the .reloc section layout of a PE file.

Shows the ImageBase, the .reloc section raw bytes in structured form
(IMAGE_BASE_RELOCATION blocks) and flags/suspicious content.
"""
import struct
import sys


def read_pe(path):
    with open(path, "rb") as f:
        data = f.read()
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    coff = pe_off + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    imagebase = struct.unpack_from("<Q", data, opt + 24)[0] if magic == 0x20B else \
        struct.unpack_from("<I", data, opt + 28)[0]
    sec_off = opt + opt_size
    sections = []
    for i in range(nsec):
        base = sec_off + i * 40
        name = data[base:base + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, base + 8)
        sections.append((name, vaddr, vsize, raw_ptr, raw_size))
    return data, imagebase, sections


def main():
    at = None
    args = sys.argv[1:]
    if args and args[0] == "--at":
        at = int(args[1], 0)
        args = args[2:]
    path = args[0]
    data, imagebase, sections = read_pe(path)
    reloc = [s for s in sections if s[0] == ".reloc"]
    if not reloc:
        print("no .reloc section")
        return
    name, vaddr, vsize, raw_ptr, raw_size = reloc[0]
    print(f".reloc: vaddr={vaddr:#x} vsize={vsize:#x} raw_ptr={raw_ptr:#x} "
          f"raw_size={raw_size:#x} imagebase={imagebase:#x}")
    raw = data[raw_ptr:raw_ptr + raw_size]
    off = 0
    nblocks = 0
    in_at = False
    while off + 8 <= len(raw):
        page_rva, block_size = struct.unpack_from("<II", raw, off)
        if page_rva == 0 and block_size == 0:
            break
        if at is not None and off <= at < off + block_size:
            in_at = True
            print(f"  *** first-diff offset {at:#x} is inside this block ***")
            print(f"  block @{off:#x}: page_rva={page_rva:#x} size={block_size:#x} "
                  f"entries={(block_size - 8) // 2}")
            # dump the bytes around the difference
            lo = max(off, at - 16)
            hi = min(off + block_size, at + 16)
            print(f"    bytes [{lo:#x}..{hi:#x}): {raw[lo:hi].hex()}")
        # dump first few entries
        ent = (block_size - 8) // 2
        shown = 0
        e = off + 8
        while e + 2 <= min(off + block_size, len(raw)) and shown < 4:
            entry = struct.unpack_from("<H", raw, e)[0]
            typ = entry >> 12
            va = page_rva + (entry & 0xFFF)
            print(f"    entry[{shown}] type={typ} (0x{typ:x}) "
                  f"offset={entry & 0xFFF:#x} -> va={va:#x}")
            e += 2
            shown += 1
        if ent > 4:
            print(f"    ... {ent - 4} more entries")
        off += block_size
        nblocks += 1
    # any trailing bytes after the last block?
    print(f"  total blocks: {nblocks}, consumed {off:#x} of {raw_size:#x}")
    if at is not None and not in_at:
        print(f"  first-diff offset {at:#x} is NOT inside any block "
              f"(trailing/padding region)")
    if off < len(raw):
        print(f"  trailing {len(raw) - off} bytes: {raw[off:].hex()}")


if __name__ == "__main__":
    main()
