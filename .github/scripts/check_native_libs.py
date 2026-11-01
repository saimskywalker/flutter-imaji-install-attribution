#!/usr/bin/env python3
"""Checks the native libraries in a release app bundle.

    python3 .github/scripts/check_native_libs.py app-release.aab

The plugin ships no native code, so the only .so files expected are
Flutter's own (libflutter.so, libapp.so). Any other library is reported, and
every library must have 16 KB-aligned LOAD segments, the check Google's
check_elf_alignment.sh makes for Play's 16 KB page size requirement.
"""

import struct
import sys
import zipfile

FLUTTER_LIBS = {"libflutter.so", "libapp.so"}
PAGE = 16 * 1024


def load_alignments(data):
    """p_align of every PT_LOAD segment of an ELF file."""
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    is64 = data[4] == 2
    endian = "<" if data[5] == 1 else ">"
    if is64:
        phoff, = struct.unpack_from(endian + "Q", data, 0x20)
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x36)
    else:
        phoff, = struct.unpack_from(endian + "I", data, 0x1C)
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x2A)
    aligns = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, = struct.unpack_from(endian + "I", data, off)
        if p_type != 1:  # PT_LOAD
            continue
        if is64:
            p_align, = struct.unpack_from(endian + "Q", data, off + 0x30)
        else:
            p_align, = struct.unpack_from(endian + "I", data, off + 0x1C)
        aligns.append(p_align)
    return aligns


def main(path):
    failed = False
    with zipfile.ZipFile(path) as bundle:
        libs = sorted(n for n in bundle.namelist() if "/lib/" in n and n.endswith(".so"))
        if not libs:
            print("::error::no native libraries found; is this a Flutter app bundle?")
            return 1
        for name in libs:
            base = name.rsplit("/", 1)[1]
            aligns = load_alignments(bundle.read(name))
            ok = bool(aligns) and min(aligns) >= PAGE
            note = "" if base in FLUTTER_LIBS else "  (not from Flutter)"
            print(f"{'ok  ' if ok else 'FAIL'} {name}: LOAD align {sorted(set(aligns))}{note}")
            if base not in FLUTTER_LIBS:
                print(f"::warning::{name} is not one of Flutter's libraries; the plugin was expected to ship no native code")
            if not ok:
                print(f"::error::{name} is not 16 KB aligned")
                failed = True
    if failed:
        return 1
    print(f"All {len(libs)} native libraries are 16 KB aligned.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
