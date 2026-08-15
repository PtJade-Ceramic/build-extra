#!/usr/bin/env python3
"""Parse the .rsrc resource directory of a raw section dump.

Usage: parse-rsrc.py <file.bin>
Reads the bytes of a PE .rsrc section (as extracted by
`objcopy -O binary --only-section=.rsrc`) and prints the resource
directory tree: for each resource, its type, name, and data offset+size
within the section. Used by the reproducible-build verification to see
which resource differs between two builds.
"""
import struct
import sys

WORD_FMT = '<H'
DWORD_FMT = '<I'


def word(data, off):
    return struct.unpack_from(WORD_FMT, data, off)[0]


def dword(data, off):
    return struct.unpack_from(DWORD_FMT, data, off)[0]


TYPE_NAMES = {
    1: 'RT_CURSOR',
    2: 'RT_BITMAP',
    3: 'RT_ICON',
    4: 'RT_MENU',
    5: 'RT_DIALOG',
    6: 'RT_STRING',
    7: 'RT_FONTDIR',
    8: 'RT_FONT',
    9: 'RT_ACCELERATOR',
    10: 'RT_RCDATA',
    11: 'RT_MESSAGETABLE',
    12: 'RT_GROUP_CURSOR',
    14: 'RT_GROUP_ICON',
    16: 'RT_VERSION',
    17: 'RT_DLGINCLUDE',
    19: 'RT_PLUGPLAY',
    20: 'RT_VXD',
    21: 'RT_ANICURSOR',
    22: 'RT_ANIICON',
    23: 'RT_HTML',
    24: 'RT_MANIFEST',
}


def walk(data, dir_off, depth, path, rva):
    n_named = word(data, dir_off + 12)
    n_id = word(data, dir_off + 14)
    indent = '  ' * depth
    print('%sDIR @0x%x named=%d id=%d' % (indent, dir_off, n_named, n_id))
    off = dir_off + 16
    for _ in range(n_named + n_id):
        name = dword(data, off)
        offset = dword(data, off + 4)
        off += 8
        is_dir = bool(offset & 0x80000000)
        target = offset & 0x7fffffff
        if name & 0x80000000:
            # named entry: offset to name string
            name_off = name & 0x7fffffff
            length = word(data, name_off)
            raw = data[name_off + 2:name_off + 2 + length * 2]
            try:
                label = raw.decode('utf-16-le')
            except UnicodeDecodeError:
                label = '<undecodable>'
        else:
            label = TYPE_NAMES.get(name, 'ID_%d' % name)
        if is_dir:
            print('%s  entry name=0x%x (%s) -> DIR @0x%x' % (indent, name, label, target))
            walk(data, target, depth + 1, path + [label], rva)
        else:
            # IMAGE_RESOURCE_DATA_ENTRY
            data_off = dword(data, target)
            size = dword(data, target + 4)
            # data_off is an RVA; convert to an offset within the extracted
            # section by subtracting the section's RVA (passed in).
            sec_off = data_off - rva
            tail = b''
            head = b''
            if 0 <= sec_off < len(data):
                head = data[sec_off:sec_off + 24]
                if sec_off + size <= len(data):
                    tail = data[sec_off + size - 8:sec_off + size]
            crlf = b''
            if 0 <= sec_off < len(data):
                chunk = data[sec_off:sec_off + size]
                crlf = b'CRLF' if b'\r\n' in chunk else b'LF'
            print('%s  entry name=0x%x (%s) -> DATA rva=0x%x sec_off=0x%x size=%d (end=0x%x) eol=%s'
                  % (indent, name, label, data_off, sec_off, size, sec_off + size,
                     crlf.decode()))
            print('%s    head: %s' % (indent, head.hex()))
            print('%s    tail: %s' % (indent, tail.hex()))


def main():
    rva = 0
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == '--rva':
        rva = int(args[1], 0)
        args = args[2:]
    if len(args) != 1:
        print('usage: parse-rsrc.py [--rva <section-rva>] <raw .rsrc section file>',
              file=sys.stderr)
        return 1
    with open(args[0], 'rb') as f:
        data = f.read()
    print('section size: %d (0x%x)' % (len(data), len(data)))
    # The root resource directory starts at offset 0.
    walk(data, 0, 0, [], rva)
    return 0


if __name__ == '__main__':
    sys.exit(main())
