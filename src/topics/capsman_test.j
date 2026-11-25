# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the capsman topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testManagedApFromRow() {
    def row as map of string to string init {
        "identity": "ap-lobby",
        "address": "10.0.9.31",
        "interface": "cap1",
        "state": "running"
    };
    def ap as ManagedAp init managedApFromRow($row);
    testing.assertEqual($ap.identity, "ap-lobby");
    testing.assertEqual($ap.address, "10.0.9.31");
    testing.assertEqual($ap.interfaceName, "cap1");
    testing.assertEqual($ap.state, "running");
}

func testManagedApFromSparseRow() {
    def row as map of string to string init {"identity": "ap-2"};
    def ap as ManagedAp init managedApFromRow($row);
    testing.assertEqual($ap.address, "");
    testing.assertEqual($ap.state, "");
}

# Verbs on a router without either CAPsMAN menu: the fake traps every
# read the way RouterOS answers an unknown menu.

func noCapsmanFake() {
    def r as FakeRouter init fakeWithTrap(
        fakeRouter(),
        WIFI_CAPSMAN_PATH + "/print",
        "0",
        "no such command prefix");
    $r = fakeWithTrap($r, CAPSMAN_PATH + "/print", "0", "no such command prefix");
    $r = fakeWithTrap($r, WIFI_CAP_PATH + "/print", "0", "no such command prefix");
    return fakeWithTrap($r, CAPSMAN_REMOTE_PATH + "/print", "0", "no such command prefix");
}

func testCapsmanStatusWithoutMenuIsVersionZero() {
    def f as Fake init fakeStart(noCapsmanFake());
    def c as Client init fakeClient($f);
    def s as CapsmanStatus init capsmanStatus($c);
    fakeLog($c, $f);
    testing.assertFalse($s.enabled);
    testing.assertEqual($s.version, 0);
    testing.assertEqual($s.managedAps, 0);
}

func testEnableCapsmanRejectsRouterWithoutMenu() {
    def f as Fake init fakeStart(noCapsmanFake());
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        enableCapsman($c);
    } catch (e) {
        $got = $e.kind;
    }
    fakeLog($c, $f);
    testing.assertEqual($got, "routeros");
}

func testManagedApsEmptyWithoutMenu() {
    def f as Fake init fakeStart(noCapsmanFake());
    def c as Client init fakeClient($f);
    testing.assertEqual(len(managedAps($c)), 0);
    fakeLog($c, $f);
}

func testCapsmanStatusRethrowsADroppedConnection() {
    def f as Fake init fakeStart(fakeWithClose(fakeRouter(), WIFI_CAPSMAN_PATH + "/print"));
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        capsmanStatus($c);
    } catch (e) {
        $got = $e.kind;
    }
    fakeLog($c, $f);
    testing.assertTrue($got != "" and $got != "routeros");
}

func testDisableCapsmanUsesTheV2Menu() {
    def r as FakeRouter init fakeWithRows(fakeRouter(), WIFI_CAPSMAN_PATH, [{"enabled": "true"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    disableCapsman($c);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/interface/wifi/capsman/set =enabled=no"));
}
