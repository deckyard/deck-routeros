# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the ethernet topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testEthernetFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "uplink",
        "default-name": "ether1",
        "mac-address": "AA:BB:CC:DD:EE:01",
        "mtu": "1500",
        "auto-negotiation": "true",
        "poe-out": "auto-on",
        "running": "true",
        "slave": "false",
        "disabled": "false",
        "comment": "to the switch"
    };
    def p as EthernetPort init ethernetFromRow($row);
    testing.assertEqual($p.id, "*1");
    testing.assertEqual($p.name, "uplink");
    testing.assertEqual($p.defaultName, "ether1");
    testing.assertEqual($p.mac, "AA:BB:CC:DD:EE:01");
    testing.assertEqual($p.mtu, "1500");
    testing.assertTrue($p.autoNegotiation);
    testing.assertEqual($p.poeOut, "auto-on");
    testing.assertTrue($p.running);
    testing.assertFalse($p.slave);
    testing.assertFalse($p.disabled);
    testing.assertEqual($p.comment, "to the switch");
}

func testEthernetFromRowBridgeSlaveNoPoe() {
    def row as map of string to string init {
        ".id": "*2",
        "name": "ether2",
        "default-name": "ether2",
        "slave": "true",
        "running": "false"
    };
    def p as EthernetPort init ethernetFromRow($row);
    testing.assertTrue($p.slave);
    testing.assertFalse($p.running);
    testing.assertEqual($p.poeOut, "");
    testing.assertFalse($p.autoNegotiation);
}

func testLinkStatusFromRowUp() {
    def row as map of string to string init {
        "name": "ether1",
        "status": "link-ok",
        "rate": "1Gbps",
        "full-duplex": "true",
        "auto-negotiation": "done"
    };
    def ls as LinkStatus init linkStatusFromRow($row);
    testing.assertEqual($ls.name, "ether1");
    testing.assertTrue($ls.up);
    testing.assertEqual($ls.status, "link-ok");
    testing.assertEqual($ls.rate, "1Gbps");
    testing.assertTrue($ls.fullDuplex);
    testing.assertEqual($ls.autoNegotiation, "done");
}

func testLinkStatusFromRowDown() {
    def row as map of string to string init {"name": "ether5", "status": "no-link"};
    def ls as LinkStatus init linkStatusFromRow($row);
    testing.assertFalse($ls.up);
    testing.assertEqual($ls.status, "no-link");
    testing.assertEqual($ls.rate, "");
    testing.assertFalse($ls.fullDuplex);
}

func testEnsureEthernetSpeedAcceptsKnown() {
    ensureEthernetSpeed("10Mbps");
    ensureEthernetSpeed("100Mbps");
    ensureEthernetSpeed("1Gbps");
    ensureEthernetSpeed("10Gbps");
    testing.assertTrue(true);
}

func failEthernetSpeedUnknown() {
    ensureEthernetSpeed("11Gbps");
}

func testEnsureEthernetSpeedRejectsUnknown() {
    testing.assertThrows("failEthernetSpeedUnknown", "routeros");
}

func failEthernetSpeedBareNumber() {
    ensureEthernetSpeed("1000");
}

func testEnsureEthernetSpeedRejectsBareNumber() {
    testing.assertThrows("failEthernetSpeedBareNumber", "routeros");
}

func testEnsurePoeModeAcceptsKnown() {
    ensurePoeMode("auto-on");
    ensurePoeMode("forced-on");
    ensurePoeMode("off");
    testing.assertTrue(true);
}

func failPoeModeUnknown() {
    ensurePoeMode("on");
}

func testEnsurePoeModeRejectsUnknown() {
    testing.assertThrows("failPoeModeUnknown", "routeros");
}

func testEnsureMtuAcceptsBounds() {
    ensureMtu(68);
    ensureMtu(1500);
    ensureMtu(9000);
    ensureMtu(65535);
    testing.assertTrue(true);
}

func failMtuTooSmall() {
    ensureMtu(67);
}

func testEnsureMtuRejectsTooSmall() {
    testing.assertThrows("failMtuTooSmall", "routeros");
}

func failMtuTooBig() {
    ensureMtu(65536);
}

func testEnsureMtuRejectsTooBig() {
    testing.assertThrows("failMtuTooBig", "routeros");
}

# Verbs: local validation before any I/O

func failForceEthernetLinkUnknownSpeed() {
    forceEthernetLink(offlineClient(), "ether1", "1000Mbps", true);
}

func testForceEthernetLinkRejectsUnknownSpeed() {
    testing.assertThrows("failForceEthernetLinkUnknownSpeed", "routeros");
}

func failSetEthernetMtuTooSmall() {
    setEthernetMtu(offlineClient(), "ether1", 67);
}

func testSetEthernetMtuRejectsTooSmall() {
    testing.assertThrows("failSetEthernetMtuTooSmall", "routeros");
}

func failSetEthernetMtuTooBig() {
    setEthernetMtu(offlineClient(), "ether1", 65536);
}

func testSetEthernetMtuRejectsTooBig() {
    testing.assertThrows("failSetEthernetMtuTooBig", "routeros");
}

func failSetPoeUnknownMode() {
    setPoe(offlineClient(), "ether5", "on");
}

func testSetPoeRejectsUnknownMode() {
    testing.assertThrows("failSetPoeUnknownMode", "routeros");
}

func testEthernetLinkModeMapsRates() {
    testing.assertEqual(ethernetLinkMode("100Mbps", true), "100M-baseT-full");
    testing.assertEqual(ethernetLinkMode("10Mbps", false), "10M-baseT-half");
    testing.assertEqual(ethernetLinkMode("1Gbps", true), "1G-baseT-full");
    testing.assertEqual(ethernetLinkMode("2.5Gbps", true), "2.5G-baseT");
    testing.assertEqual(ethernetLinkMode("10G-baseSR-LR", true), "10G-baseSR-LR");
}

func failLinkModeHalfAt10G() {
    ethernetLinkMode("10Gbps", false);
}

func failLinkModeDuplexMismatch() {
    ethernetLinkMode("100M-baseT-half", true);
}

func testEthernetLinkModeRejectsImpossibleDuplex() {
    testing.assertThrows("failLinkModeHalfAt10G", "routeros");
    testing.assertThrows("failLinkModeDuplexMismatch", "routeros");
}

func ethernetFake() {
    return fakeWithRows(fakeRouter(), ETHERNET_PATH, [{".id": "*1", "name": "ether4"}]);
}

func testForceEthernetLinkSendsTheV7Mode() {
    def f as Fake init fakeStart(ethernetFake());
    def c as Client init fakeClient($f);
    forceEthernetLink($c, "ether4", "100Mbps", true);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw(
        $log,
        "/interface/ethernet/set =auto-negotiation=no =speed=100M-baseT-full =.id=*1"));
}

func testForceEthernetLinkFallsBackToTheOldForm() {
    def r as FakeRouter init fakeWithTrap(
        ethernetFake(),
        "/interface/ethernet/set",
        "1",
        "invalid value");
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        forceEthernetLink($c, "ether4", "100Mbps", true);
    } catch (e) {
        $got = $e.routerMessage;
    }
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw(
        $log,
        "/interface/ethernet/set =auto-negotiation=no =speed=100Mbps =full-duplex=yes =.id=*1"));
    testing.assertEqual($got, "invalid value");
}
