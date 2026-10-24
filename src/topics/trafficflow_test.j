# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

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
        "address": "10.0.9.30",
        "port": "2055",
        "version": "ipfix",
        "disabled": "false"
    };
    def t as FlowTarget init flowTargetFromRow($row);
    testing.assertEqual($t.address, "10.0.9.30");
    testing.assertEqual($t.port, "2055");
    testing.assertEqual($t.version, "ipfix");
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
