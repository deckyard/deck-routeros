# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the files topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testFileFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "nightly.backup",
        "type": "backup",
        "size": "182348",
        "creation-time": "2026-07-24 03:30:01"
    };
    def f as RouterFile init fileFromRow($row);
    testing.assertEqual($f.name, "nightly.backup");
    testing.assertEqual($f.kind, "backup");
    testing.assertEqual($f.size, 182348);
    testing.assertEqual($f.creationTime, "2026-07-24 03:30:01");
}

func testFileFromSparseRow() {
    def row as map of string to string init {".id": "*2", "name": "flash", "type": "directory"};
    def f as RouterFile init fileFromRow($row);
    testing.assertEqual($f.kind, "directory");
    testing.assertEqual($f.size, 0);
    testing.assertEqual($f.creationTime, "");
}

# Verbs: local validation before any I/O

func failSaveBackupSpacedName() {
    saveBackup(offlineClient(), "nightly backup");
}

func testSaveBackupRejectsSpacedName() {
    testing.assertThrows("failSaveBackupSpacedName", "routeros");
}

func failSaveBackupWithEmptyPassword() {
    saveBackupWith(offlineClient(), "nightly", "  ");
}

func testSaveBackupWithRejectsEmptyPassword() {
    testing.assertThrows("failSaveBackupWithEmptyPassword", "routeros");
}

func failWriteFileTextEmptyName() {
    writeFileText(offlineClient(), "", "hello");
}

func testWriteFileTextRejectsEmptyName() {
    testing.assertThrows("failWriteFileTextEmptyName", "routeros");
}

func testRemoveFileFiltersOnTheRouter() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        FILE_PATH,
        [{".id": "*1", "name": "a.txt", "contents": "x"}, {".id": "*2", "name": "b.txt"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    removeFile($c, "b.txt");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/file/print =.proplist=.id,name ?name=b.txt"));
    testing.assertTrue(fakeSaw($log, "/file/remove =.id=*2"));
}

func testFilesListSkipsContents() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        FILE_PATH,
        [{".id": "*1", "name": "a.txt", "type": ".txt file", "size": "1", "contents": "x"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    def got as list of RouterFile init files($c);
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual(len($got), 1);
    testing.assertTrue(fakeSaw($log, "/file/print =.proplist=name,type,size,creation-time"));
}
