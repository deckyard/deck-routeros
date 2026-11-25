# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the trafficflow topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testTrafficFlowFromRow() {
    def row as map of string to string init {"enabled": "true", "interfaces": "all"};
    def s as TrafficFlowSettings init trafficFlowFromRow($row);
    testing.assertTrue($s.enabled);
    testing.assertEqual($s.interfaces, "all");
}

func testFlowTargetFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "dst-address": "10.0.9.30",
        "port": "2055",
        "version": "IPFIX",
        "disabled": "false"
    };
    def t as FlowTarget init flowTargetFromRow($row);
    testing.assertEqual($t.address, "10.0.9.30");
    testing.assertEqual($t.port, "2055");
    testing.assertEqual($t.version, "IPFIX");
    testing.assertFalse($t.disabled);
}

# Verbs: local validation before any I/O

func failAddFlowTargetHostname() {
    addFlowTarget(offlineClient(), "collector.lan", 2055, "9");
}

func testAddFlowTargetRejectsHostname() {
    testing.assertThrows("failAddFlowTargetHostname", "routeros");
}

func failAddFlowTargetBadVersion() {
    addFlowTarget(offlineClient(), "192.168.88.10", 2055, "8");
}

func testAddFlowTargetRejectsUnknownVersion() {
    testing.assertThrows("failAddFlowTargetBadVersion", "routeros");
}

func failAddFlowTargetBadPort() {
    addFlowTarget(offlineClient(), "192.168.88.10", 0, "9");
}

func testAddFlowTargetRejectsBadPort() {
    testing.assertThrows("failAddFlowTargetBadPort", "routeros");
}

# The target's collector is "dst-address"; "address" was rejected by the
# router and always read back as "".
func testAddFlowTargetSendsDstAddressAndIpfix() {
    def f as Fake init fakeStart(fakeRouter());
    def c as Client init fakeClient($f);
    addFlowTarget($c, "10.0.9.30", 4739, "ipfix");
    def log as list of string init fakeLog($c, $f);
    def added as string init "";
    for (def s in $log) {
        if (strings.startsWith($s, TRAFFIC_FLOW_TARGET_PATH + "/add")) {
            $added = $s;
        }
    }
    testing.assertTrue(strings.contains($added, "=dst-address=10.0.9.30"));
    testing.assertTrue(strings.contains($added, "=version=IPFIX"));
    testing.assertFalse(strings.contains($added, "=address="));
}

func testAddFlowTargetFindsExistingByDstAddress() {
    def rows as list of map of string to string init [
        {".id": "*4", "dst-address": "10.0.9.30", "port": "2055", "version": "9"}
    ];
    def f as Fake init fakeStart(fakeWithRows(fakeRouter(), TRAFFIC_FLOW_TARGET_PATH, $rows));
    def c as Client init fakeClient($f);
    testing.assertEqual(addFlowTarget($c, "10.0.9.30", 2055, "9"), "*4");
    removeFlowTarget($c, "10.0.9.30");
    def log as list of string init fakeLog($c, $f);
    testing.assertFalse(fakeSaw($log, TRAFFIC_FLOW_TARGET_PATH + "/add"));
    testing.assertTrue(fakeSaw($log, TRAFFIC_FLOW_TARGET_PATH + "/remove =.id=*4"));
}

func testFlowTargetAddressLegacyForm() {
    testing.assertEqual(flowTargetAddress({"address": "10.0.9.30:2055"}), "10.0.9.30");
    testing.assertEqual(flowTargetAddress({"dst-address": "10.0.9.31"}), "10.0.9.31");
    testing.assertEqual(flowVersionWord("IPFIX"), "IPFIX");
    testing.assertEqual(flowVersionWord("9"), "9");
}
