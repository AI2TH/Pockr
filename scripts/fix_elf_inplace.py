#!/usr/bin/env python3
"""
In-place ELF modification (no restructuring):
  1. Zero out DT_RUNPATH / DT_RPATH in .dynamic
     OR repurpose DT_RUNPATH as DT_NEEDED (with --add-needed)
  2. Deversion NEEDED strings: libfoo.so.1 → libfoo.so (in .dynstr)

Usage:
  fix_elf_inplace.py [--add-needed LIBNAME] file1.so file2.so ...

  --add-needed LIBNAME
      Instead of zeroing DT_RUNPATH, repurpose it as DT_NEEDED for LIBNAME:
      overwrite the RUNPATH string in .dynstr with LIBNAME and change d_tag
      from DT_RUNPATH(29) → DT_NEEDED(1), keeping d_val (string offset) the same.
      Only the first DT_RUNPATH entry is repurposed; any DT_RPATH is still cleared.
"""
import struct, sys, re, os


def fix_elf(path, add_needed=None):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    if data[:4] != b'\x7fELF':
        return
    if data[4] != 2 or data[5] != 1:   # must be 64-bit LE
        return

    e_phoff     = struct.unpack_from('<Q', data, 32)[0]
    e_phentsize = struct.unpack_from('<H', data, 54)[0]
    e_phnum     = struct.unpack_from('<H', data, 56)[0]
    e_shoff     = struct.unpack_from('<Q', data, 40)[0]
    e_shentsize = struct.unpack_from('<H', data, 58)[0]
    e_shnum     = struct.unpack_from('<H', data, 60)[0]

    # Find PT_DYNAMIC (type=2)
    dynamic_offset = dynamic_filesz = None
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        if struct.unpack_from('<I', data, o)[0] == 2:
            dynamic_offset = struct.unpack_from('<Q', data, o + 8)[0]
            dynamic_filesz = struct.unpack_from('<Q', data, o + 32)[0]
            break
    if dynamic_offset is None:
        return

    # Find .dynstr via SHT_DYNAMIC → sh_link
    dynstr_offset = dynstr_size = None
    if e_shoff > 0:
        for i in range(e_shnum):
            o = e_shoff + i * e_shentsize
            sh_type = struct.unpack_from('<I', data, o + 4)[0]
            sh_link = struct.unpack_from('<I', data, o + 40)[0]
            if sh_type == 6:    # SHT_DYNAMIC
                if 0 < sh_link < e_shnum:
                    ds = e_shoff + sh_link * e_shentsize
                    dynstr_offset = struct.unpack_from('<Q', data, ds + 24)[0]
                    dynstr_size   = struct.unpack_from('<Q', data, ds + 32)[0]
                break

    if dynstr_offset is None:
        print(f"  WARNING: no .dynstr found, skipping {os.path.basename(path)}")
        return

    DT_NULL, DT_NEEDED, DT_RPATH, DT_RUNPATH = 0, 1, 15, 29
    modified = False
    already_converted = False   # track if we've repurposed one RUNPATH slot

    for i in range(dynamic_filesz // 16):
        eo = dynamic_offset + i * 16
        d_tag = struct.unpack_from('<q', data, eo)[0]
        d_val = struct.unpack_from('<Q', data, eo + 8)[0]

        if d_tag == DT_NULL:
            break

        if d_tag in (DT_RPATH, DT_RUNPATH):
            rp_str = ""
            try:
                rp_off = dynstr_offset + d_val
                end    = data.index(0, rp_off)
                rp_str = data[rp_off:end].decode('utf-8', errors='replace')
            except Exception:
                pass

            tag_name = 'RUNPATH' if d_tag == DT_RUNPATH else 'RPATH'

            if add_needed is not None and d_tag == DT_RUNPATH and not already_converted:
                # Repurpose this DT_RUNPATH entry as DT_NEEDED for add_needed.
                rp_off    = dynstr_offset + d_val
                end       = data.index(0, rp_off)
                slot_size = end - rp_off + 1   # bytes available (including null)

                new_bytes = add_needed.encode('utf-8') + b'\x00'
                if len(new_bytes) > slot_size:
                    print(f"  ERROR: '{add_needed}' ({len(new_bytes)} B) doesn't fit "
                          f"in DT_RUNPATH slot ({slot_size} B) in {os.path.basename(path)}")
                    sys.exit(1)

                # Overwrite .dynstr slot with new lib name + zero padding
                data[rp_off:rp_off + slot_size] = (
                    new_bytes + b'\x00' * (slot_size - len(new_bytes))
                )
                # Change d_tag DT_RUNPATH(29) → DT_NEEDED(1); d_val stays the same
                struct.pack_into('<q', data, eo, DT_NEEDED)
                print(f"  DT_RUNPATH→DT_NEEDED: '{rp_str}' → '{add_needed}' "
                      f"(slot {slot_size} B, name {len(new_bytes)} B)")
                already_converted = True
                modified = True
            else:
                # Keep d_tag (do NOT set to DT_NULL — that breaks the .dynamic chain!)
                # Point d_val to offset 0 in .dynstr → empty string ""
                struct.pack_into('<Q', data, eo + 8, 0)
                print(f"  Cleared DT_{tag_name}: {rp_str}")
                modified = True

        elif d_tag == DT_NEEDED:
            try:
                str_off = dynstr_offset + d_val
                end     = data.index(0, str_off)
                lib     = data[str_off:end].decode('utf-8', errors='replace')
            except Exception:
                continue

            # Strip version suffix: libfoo.so.1 → libfoo.so
            new_lib = re.sub(r'(\.so)\.\d+(\.\d+)*$', r'\1', lib)
            if new_lib != lib:
                orig_len  = end - str_off + 1   # including null terminator
                new_bytes = new_lib.encode('utf-8') + b'\x00'
                assert len(new_bytes) <= orig_len, \
                    f"new name longer than original for {lib}"
                data[str_off:str_off + orig_len] = (
                    new_bytes + b'\x00' * (orig_len - len(new_bytes))
                )
                print(f"  NEEDED: {lib} → {new_lib}")
                modified = True

    if add_needed is not None and not already_converted:
        print(f"  WARNING: no DT_RUNPATH entry found to repurpose for '{add_needed}'")

    if modified:
        with open(path, 'wb') as f:
            f.write(data)
        print(f"  ✓ Written")
    else:
        print(f"  (no changes)")


if __name__ == '__main__':
    args = sys.argv[1:]
    add_needed = None

    if args and args[0] == '--add-needed':
        if len(args) < 2:
            print("ERROR: --add-needed requires a library name argument")
            sys.exit(1)
        add_needed = args[1]
        args = args[2:]

    for p in args:
        print(f"\n{os.path.basename(p)}")
        fix_elf(p, add_needed=add_needed)
