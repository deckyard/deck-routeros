<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Disks

File: `src/topics/disk.j`. Path: `/disk` (`DISK_PATH`).
Reference: [cheatsheet](cheatsheet.md#disks).

RouterOS v7 lists attached storage (USB, NVMe, SATA) under `/disk`.
Container filesystems, backups, downloaded files and disk logging live
there. `disks(c)` returns an empty list when the router has no storage,
and also when the read fails for any reason, a dropped connection
included.

```jennifer
def ds as list of mt.Disk init mt.disks($c);
for (def d in $ds) {
    io.printf("%s (%s) %s: %d of %d bytes free\n",
        $d.name, $d.model, $d.fs, $d.freeBytes, $d.sizeBytes);
}

mt.formatDisk($c, "usb1", "ext4", "container-storage");   # erases the disk
mt.ejectDisk($c, "usb1");
```

`sizeBytes` and `freeBytes` are 0 when not reported; `fs` is `""` on an
unformatted disk. The device (`usb1`) and its partition (`usb1-part1`)
are separate entries; a container root-dir lives on the partition.

## Names

RouterOS 7.21.5 reports a USB stick as `name=` (empty) and `slot=usb1`.
`Disk.name` falls back to `slot`, and `diskByName`, `formatDisk` and
`ejectDisk` match either property, so a name printed by `disks(c)` always
finds the disk again. The generic verbs filter on `name` on the router:
`mt.findByName($c, "/disk", "usb1")` finds nothing.

## formatDisk

- Erases everything, with no undo and no prompt. Check the name against
  `disks(c)` and never run it on data that exists nowhere else.
- Filesystems: `ext4`, `fat32`, `exfat`, `btrfs`, `vfat`; anything else
  is rejected locally. `ext4` for a router-only disk (POSIX permissions);
  `exfat` or `fat32` for a disk also read on a PC (no permissions, fat32
  caps files at 4 GB).
- RouterOS up to 7.20 names the command `/disk/format-drive`; 7.21 renamed
  it `/disk/format` and answers the old name with `!trap: no such
  command`. `formatDisk` tries the new name and falls back.

## Notes

- Cheap USB sticks wear out under disk logging or a busy container; use
  decent media, or NVMe where the board has it.
- Ejecting a disk in use (a running container's root-dir, active disk
  logging) can fail or corrupt data; stop the user first.
