# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the disk topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testDiskFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "usb1",
        "disk": "SanDisk Ultra",
        "type": "hardware",
        "fs": "ext4",
        "size": "64023257088",
        "free": "51200000000",
        "slot": "usb1"
    };
    def d as Disk init diskFromRow($row);
    testing.assertEqual($d.name, "usb1");
    testing.assertEqual($d.model, "SanDisk Ultra");
    testing.assertEqual($d.kind, "hardware");
    testing.assertEqual($d.fs, "ext4");
    testing.assertEqual($d.sizeBytes, 64023257088);
    testing.assertEqual($d.freeBytes, 51200000000);
    testing.assertEqual($d.slot, "usb1");
}

func testDiskFromSparseRow() {
    def row as map of string to string init {".id": "*2", "name": "nvme1", "disk": "unformatted"};
    def d as Disk init diskFromRow($row);
    testing.assertEqual($d.fs, "");
    testing.assertEqual($d.sizeBytes, 0);
    testing.assertEqual($d.freeBytes, 0);
}

func testDiskFromRowNameFallsBackToSlot() {
    # RouterOS 7.21.5 leaves "name" empty on plain USB storage.
    def row as map of string to string init {
        ".id": "*1",
        "type": "hardware",
        "fs": "-",
        "size": "31037849600",
        "slot": "usb1"
    };
    def d as Disk init diskFromRow($row);
    testing.assertEqual($d.name, "usb1");
    testing.assertEqual($d.slot, "usb1");
}

func testDiskRowMatchingPrefersName() {
    def rows as list of map of string to string init [
        {".id": "*1", "name": "usb1", "slot": "usb2"},
        {".id": "*2", "name": "other", "slot": "usb1"}
    ];
    def row as map of string to string init diskRowMatching($rows, "usb1");
    testing.assertEqual(rowValue($row, ".id"), "*1");
}

func testDiskRowMatchingFallsBackToSlot() {
    def rows as list of map of string to string init [
        {".id": "*1", "slot": "usb1"},
        {".id": "*2", "slot": "usb1-part1"}
    ];
    testing.assertEqual(rowValue(diskRowMatching($rows, "usb1-part1"), ".id"), "*2");
}

func testDiskRowMatchingMissIsEmpty() {
    def rows as list of map of string to string init [{".id": "*1", "slot": "usb1"}];
    testing.assertEqual(len(diskRowMatching($rows, "nvme1")), 0);
}

func diskFake() {
    return fakeWithRows(fakeRouter(), DISK_PATH, [{".id": "*1", "slot": "usb1"}]);
}

func testFormatDiskFallsBackOnAMissingCommand() {
    def r as FakeRouter init fakeWithTrap(diskFake(), "/disk/format", "0", "no such command");
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    formatDisk($c, "usb1", "ext4", "");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/disk/format-drive =.id=*1 =file-system=ext4"));
}

func testFormatDiskKeepsARealFailure() {
    def r as FakeRouter init fakeWithTrap(diskFake(), "/disk/format", "1", "no such command");
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        formatDisk($c, "usb1", "ext4", "");
    } catch (e) {
        $got = $e.kind;
    }
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual($got, "mikrotik");
    testing.assertFalse(fakeSaw($log, "/disk/format-drive"));
}

func testFormatDiskReportsTheCurrentCommandWhenBothAreMissing() {
    def r as FakeRouter init fakeWithTrap(diskFake(), "/disk/format", "", "disk is busy");
    $r = fakeWithTrap($r, "/disk/format-drive", "0", "no such command");
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        formatDisk($c, "usb1", "ext4", "");
    } catch (e) {
        $got = $e.routerMessage;
    }
    fakeLog($c, $f);
    testing.assertEqual($got, "disk is busy");
}

func testMaybeUnknownCommandReadsFieldsOnly() {
    testing.assertTrue(maybeUnknownCommand("mikrotik", "trap", "0"));
    testing.assertTrue(maybeUnknownCommand("mikrotik", "trap", ""));
    testing.assertFalse(maybeUnknownCommand("mikrotik", "trap", "1"));
    testing.assertFalse(maybeUnknownCommand("mikrotik", "fatal", ""));
    testing.assertFalse(maybeUnknownCommand("closed", "", ""));
}

func testDisksRethrowsADroppedConnection() {
    def f as Fake init fakeStart(fakeWithClose(fakeRouter(), "/disk/print"));
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        disks($c);
    } catch (e) {
        $got = $e.kind;
    }
    fakeLog($c, $f);
    testing.assertTrue($got != "");
}

func testDisksEmptyWhenMenuMissing() {
    def f as Fake init fakeStart(fakeWithTrap(fakeRouter(), "/disk/print", "0", "no such command"));
    def c as Client init fakeClient($f);
    testing.assertEqual(len(disks($c)), 0);
    fakeLog($c, $f);
}

# Verbs: local validation before any I/O

func failFormatDiskNtfs() {
    formatDisk(offlineClient(), "usb1", "ntfs", "data");
}

func testFormatDiskRejectsUnknownFilesystem() {
    testing.assertThrows("failFormatDiskNtfs", "routeros");
}

