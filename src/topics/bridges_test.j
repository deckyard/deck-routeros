# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the bridges topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testBridgeFromRow() {
    def row as map of string to string init {
        ".id": "*2",
        "name": "brlan",
        "mac-address": "AA:BB:CC:00:11:22",
        "running": "yes",
        "disabled": "no",
        "comment": "house lan"
    };
    def b as Bridge init bridgeFromRow($row);
    testing.assertEqual($b.id, "*2");
    testing.assertEqual($b.name, "brlan");
    testing.assertEqual($b.mac, "AA:BB:CC:00:11:22");
    testing.assertTrue($b.running);
    testing.assertFalse($b.disabled);
    testing.assertEqual($b.comment, "house lan");
}

func testBridgePortFromRow() {
    def row as map of string to string init {
        ".id": "*3",
        "bridge": "brlan",
        "interface": "ether2",
        "disabled": "false"
    };
    def p as BridgePort init bridgePortFromRow($row);
    testing.assertEqual($p.id, "*3");
    testing.assertEqual($p.bridge, "brlan");
    testing.assertEqual($p.interfaceName, "ether2");
    testing.assertFalse($p.disabled);
}

func testBridgeVlanFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "bridge": "brlan",
        "vlan-ids": "10",
        "tagged": "ether1,brlan",
        "untagged": "ether2,ether3",
        "dynamic": "false"
    };
    def bv as BridgeVlan init bridgeVlanFromRow($row);
    testing.assertEqual($bv.bridge, "brlan");
    testing.assertEqual($bv.vlanIds, "10");
    testing.assertEqual($bv.tagged, "ether1,brlan");
    testing.assertEqual($bv.untagged, "ether2,ether3");
    testing.assertFalse($bv.dynamic);
}

func testNormalizedPortListForms() {
    testing.assertEqual(normalizedPortList("ether1"), "ether1");
    testing.assertEqual(normalizedPortList(" ether1 , ether2 "), "ether1,ether2");
}

func failPortListSpaced() {
    normalizedPortList("ether 1");
}

func testNormalizedPortListRejectsSpaced() {
    testing.assertThrows("failPortListSpaced", "routeros");
}

func testFindBridgeVlanRowMatchesBoth() {
    def rows as list of map of string to string init [
        {".id": "*1", "bridge": "brlan", "vlan-ids": "10"},
        {".id": "*2", "bridge": "brguest", "vlan-ids": "10"},
        {".id": "*3", "bridge": "brlan", "vlan-ids": "20"}
    ];
    def row as map of string to string init findBridgeVlanRow($rows, "brlan", 20);
    testing.assertEqual(rowValue($row, ".id"), "*3");
}

func testBridgePortRowMatchesBridgeAndPort() {
    def rows as list of map of string to string init [
        {".id": "*1", "bridge": "brlan", "interface": "ether2"},
        {".id": "*2", "bridge": "brlan", "interface": "ether3"}
    ];
    def row as map of string to string init bridgePortRow($rows, "brlan", "ether3");
    testing.assertEqual(rowValue($row, ".id"), "*2");
    def miss as map of string to string init bridgePortRow($rows, "brguest", "ether2");
    testing.assertEqual(len($miss), 0);
}

func testBridgePortFromRowHardwareOffload() {
    def row as map of string to string init {
        ".id": "*1",
        "bridge": "brlan",
        "interface": "ether2",
        "hw": "yes",
        "disabled": "false"
    };
    def p as BridgePort init bridgePortFromRow($row);
    testing.assertEqual($p.bridge, "brlan");
    testing.assertEqual($p.interfaceName, "ether2");
    testing.assertTrue($p.hardwareOffload);
    testing.assertFalse($p.disabled);
}

func testBridgePortFromRowSoftwareForwarding() {
    def row as map of string to string init {
        ".id": "*2",
        "bridge": "brlan",
        "interface": "vlanoffice",
        "hw": "no"
    };
    def p as BridgePort init bridgePortFromRow($row);
    testing.assertFalse($p.hardwareOffload);
}

# Verbs: local validation before any I/O

func failAddBridgeSpacedName() {
    addBridge(offlineClient(), "br lan");
}

func testAddBridgeRejectsSpacedName() {
    testing.assertThrows("failAddBridgeSpacedName", "routeros");
}

func failAddBridgePortEmptyInterface() {
    addBridgePort(offlineClient(), "brlan", "");
}

func testAddBridgePortRejectsEmptyInterface() {
    testing.assertThrows("failAddBridgePortEmptyInterface", "routeros");
}

func failSetPortPvidOutOfRange() {
    setPortPvid(offlineClient(), "brlan", "ether2", 4095);
}

func testSetPortPvidRejectsOutOfRange() {
    testing.assertThrows("failSetPortPvidOutOfRange", "routeros");
}

func testVlanIdsContainListsAndRanges() {
    testing.assertTrue(vlanIdsContain("10", 10));
    testing.assertTrue(vlanIdsContain("10,20", 20));
    testing.assertTrue(vlanIdsContain("5, 30-40", 35));
    testing.assertFalse(vlanIdsContain("30-40", 41));
    testing.assertFalse(vlanIdsContain("", 1));
}

func bridgeVlanFake() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        BRIDGE_PATH,
        [{".id": "*B", "name": "brlan"}]);
    return fakeWithRows(
        $r,
        BRIDGE_VLAN_PATH,
        [
            {
                ".id": "*D1",
                "bridge": "brlan",
                "vlan-ids": "10",
                "untagged": "ether2",
                "dynamic": "true"
            },
            {".id": "*S1", "bridge": "brlan", "vlan-ids": "20,30", "tagged": "brlan,ether1"}
        ]);
}

func testAddBridgeVlanSkipsDynamicEntries() {
    def f as Fake init fakeStart(bridgeVlanFake());
    def c as Client init fakeClient($f);
    testing.assertEqual(addBridgeVlan($c, "brlan", 10, "ether1", ""), "*F1");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw(
        $log,
        "/interface/bridge/vlan/add =bridge=brlan =vlan-ids=10 =tagged=ether1"));
}

func testAddBridgeVlanFindsIdInsideAList() {
    def f as Fake init fakeStart(bridgeVlanFake());
    def c as Client init fakeClient($f);
    testing.assertEqual(addBridgeVlan($c, "brlan", 20, "ether1", ""), "*S1");
    def log as list of string init fakeLog($c, $f);
    testing.assertFalse(fakeSaw($log, "/interface/bridge/vlan/add"));
}

func testRemoveBridgeVlanRefusesASharedEntry() {
    def f as Fake init fakeStart(bridgeVlanFake());
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        removeBridgeVlan($c, "brlan", 30);
    } catch (e) {
        $got = $e.kind;
    }
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual($got, "routeros");
    testing.assertFalse(fakeSaw($log, "/interface/bridge/vlan/remove"));
}

func testRemoveBridgePortFiltersOnTheRouter() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        BRIDGE_PORT_PATH,
        [{".id": "*1", "bridge": "brlan", "interface": "ether2"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    removeBridgePort($c, "ether2");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/interface/bridge/port/print ?interface=ether2"));
    testing.assertTrue(fakeSaw($log, "/interface/bridge/port/remove =.id=*1"));
}
