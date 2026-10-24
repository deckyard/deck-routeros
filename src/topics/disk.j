# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - disks: USB / NVMe / SATA storage.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the disk list. */
export def const DISK_PATH as string init "/disk";

def const DISK_FILESYSTEMS as list of string init ["ext4", "fat32", "exfat", "btrfs", "vfat"];

# RouterOS renamed the format command: "/disk/format-drive" on the older
# v7 builds, plain "/disk/format" from 7.21 on (7.21.5 answers the old
# spelling with "no such command"). formatDisk tries the current name and
# falls back, so one call works on both.
def const DISK_FORMAT_COMMAND as string init "/format";
def const DISK_FORMAT_COMMAND_LEGACY as string init "/format-drive";

/**
 * One storage device attached to the router.
 *
 * `name` is what `diskByName`, `formatDisk` and `ejectDisk` take.
 * RouterOS (7.21.5 at least) leaves its own `name` property empty on plain
 * USB storage and reports the usual label ("usb1", "usb1-part1") in
 * `slot`, so `name` falls back to `slot` and the lookups accept either.
 *
 * @field id {string}        internal RouterOS id
 * @field name {string}      the device name (e.g. "usb1", "nvme1"), from `slot` when unnamed
 * @field model {string}     the disk model / label as reported
 * @field kind {string}      the device type as reported ("hardware", "partition", "raid", ...)
 * @field fs {string}        the filesystem ("ext4", "fat32", "", ...)
 * @field sizeBytes {int} total capacity in bytes (0 when not reported)
 * @field freeBytes {int} free space in bytes (0 when not reported)
 * @field slot {string}      the physical slot / interface as reported
 */
export def struct Disk {
    id as string,
    name as string,
    model as string,
    kind as string,
    fs as string,
    sizeBytes as int,
    freeBytes as int,
    slot as string
};

/**
 * List the storage devices on the router.
 *
 * Returns an empty list when the router has no storage or the disk menu
 * cannot be read (any read error, a dropped connection included).
 *
 * @param c {Client} an open client
 * @return {list of Disk} all disks
 */
export func disks(c as Client) {
    def out as list of Disk init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, DISK_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = diskFromRow($row);
    }
    return $out;
}

/**
 * Look one disk up by its name.
 *
 * Matches RouterOS's `name` property first, then the `slot` label, so
 * the name `disks(c)` reports always finds the disk again (see `Disk`).
 *
 * @param c {Client}    an open client
 * @param name {string} the disk name (e.g. "usb1")
 * @return {Disk} the disk
 * @throws {Error} kind "routeros" on an empty name or when no disk has
 *                 that name
 */
export func diskByName(c as Client, name as string) {
    def row as map of string to string init diskRowByName($c, $name);
    if (len($row) == 0) {
        raiseError("the disk \"" + $name + "\" was not found on the router");
    }
    return diskFromRow($row);
}

/**
 * Format a storage device, erasing everything on it.
 *
 * Irreversible, with no confirmation: every file, backup and container
 * filesystem on the disk is lost. Check the name against `disks(c)`
 * first.
 *
 * "ext4" suits a router-only disk (containers, logs); "exfat" or "fat32"
 * a disk also read on a PC. The whole device ("usb1") and its partition
 * ("usb1-part1") are different targets; a container root-dir lives on
 * the partition. Tries `/disk/format` (RouterOS 7.21+) and falls back to
 * `/disk/format-drive` when the router answers "no such command".
 *
 * @param c {Client}          an open client
 * @param name {string}       the disk to format
 * @param filesystem {string} "ext4", "fat32", "exfat", "btrfs", or "vfat"
 * @param label {string}      a volume label ("" for none)
 * @throws {Error} kind "routeros" on an unknown filesystem, an empty name
 *                 or an unknown disk, kind "mikrotik" when the format fails
 * @example
 *   mt.formatDisk($c, "usb1", "ext4", "container-storage");
 */
export func formatDisk(c as Client, name as string, filesystem as string, label as string) {
    if (not lists.contains(DISK_FILESYSTEMS, $filesystem)) {
        raiseError("unknown filesystem \"" + $filesystem + "\" - use one of: " +
            strings.join(DISK_FILESYSTEMS, ", "));
    }
    def id as string init requiredDiskId($c, $name);
    def attrs as map of string to string init {".id": $id, "file-system": $filesystem};
    if (strings.trim($label) != "") {
        $attrs["label"] = $label;
    }
    try {
        apiRun($c, DISK_PATH + DISK_FORMAT_COMMAND, $attrs);
    } catch (e) {
        if (not isUnknownCommand($e.kind, $e.message)) {
            throw $e;
        }
        apiRun($c, DISK_PATH + DISK_FORMAT_COMMAND_LEGACY, $attrs);
    }
}

/**
 * Eject a removable disk so it is safe to unplug.
 *
 * @param c {Client}    an open client
 * @param name {string} the disk to eject
 * @throws {Error} kind "routeros" on an empty name or when no disk has
 *                 that name
 */
export func ejectDisk(c as Client, name as string) {
    apiRun($c, DISK_PATH + "/eject", {".id": requiredDiskId($c, $name)});
}

/**
 * Resolve a disk name to its RouterOS id.
 *
 * @param c {Client}    an open client
 * @param name {string} the disk name or slot label
 * @return {string} the disk id
 * @throws {Error} kind "routeros" when no disk matches
 * @internal
 */
func requiredDiskId(c as Client, name as string) {
    def row as map of string to string init diskRowByName($c, $name);
    if (len($row) == 0) {
        raiseError("the disk \"" + $name +
            "\" was not found on the router (neither its name nor its slot matched - `disks(c)` lists what is attached)");
    }
    return rowValue($row, ".id");
}

/**
 * Read the disk table and pick the row for a name.
 *
 * Reads the whole (tiny) table rather than filtering server-side on
 * `?name=`, because the `slot` fallback needs both properties.
 *
 * @param c {Client}    an open client
 * @param name {string} the disk name or slot label
 * @return {map of string to string} the matching row, or an empty map
 * @throws {Error} kind "routeros" on an empty name
 * @internal
 */
func diskRowByName(c as Client, name as string) {
    ensureName($name, "disk");
    return diskRowMatching(getAll($c, DISK_PATH), $name);
}

/**
 * Pick the disk row whose `name` - or, failing that, whose `slot` -
 * matches.
 *
 * @param rows {list of map of string to string} "/disk/print" rows
 * @param name {string} the disk name or slot label
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func diskRowMatching(rows as list of map of string to string, name as string) {
    def row as map of string to string init findRowByField($rows, "name", $name);
    if (len($row) > 0) {
        return $row;
    }
    return findRowByField($rows, "slot", $name);
}

/**
 * Tell a "the router has no such command" refusal from a real failure.
 *
 * Used to fall back to a command's older spelling without swallowing a
 * genuine error (a busy disk, a refused format).
 *
 * @param kind {string}    the error kind
 * @param message {string} the error message
 * @return {bool} true when the router did not recognise the command
 * @internal
 */
func isUnknownCommand(kind as string, message as string) {
    if ($kind != "mikrotik") {
        return false;
    }
    return strings.contains(strings.lower($message), "no such command");
}

/**
 * Fold a reply row into a Disk.
 *
 * @param row {map of string to string} a "/disk/print" row
 * @return {Disk} the typed disk
 * @internal
 */
func diskFromRow(row as map of string to string) {
    def label as string init rowValue($row, "name");
    if ($label == "") {
        $label = rowValue($row, "slot");
    }
    return Disk{
        id: rowValue($row, ".id"),
        name: $label,
        model: rowValue($row, "disk"),
        kind: rowValue($row, "type"),
        fs: rowValue($row, "fs"),
        sizeBytes: rowInt($row, "size"),
        freeBytes: rowInt($row, "free"),
        slot: rowValue($row, "slot")
    };
}
