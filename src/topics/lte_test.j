# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - white-box tests for the lte topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testLteFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "lte1",
        "running": "true",
        "disabled": "false",
        "comment": "backup uplink"
    };
    def l as LteInterface init lteFromRow($row);
    testing.assertEqual($l.name, "lte1");
    testing.assertTrue($l.running);
    testing.assertFalse($l.disabled);
    testing.assertEqual($l.comment, "backup uplink");
}

func testLteStatusFromRowRegistered() {
    def row as map of string to string init {
        "registration-status": "registered",
        "current-operator": "Example Mobile",
        "access-technology": "lte",
        "rssi": "-61dBm",
        "rsrp": "-90dBm",
        "rsrq": "-10dB",
        "sinr": "12dB"
    };
    def s as LteStatus init lteStatusFromRow($row);
    testing.assertEqual($s.status, "registered");
    testing.assertTrue($s.registered);
    testing.assertEqual($s.operator, "Example Mobile");
    testing.assertEqual($s.accessTechnology, "lte");
    testing.assertEqual($s.rsrp, "-90dBm");
    testing.assertEqual($s.sinr, "12dB");
}

func testLteStatusFromRowNotRegistered() {
    def row as map of string to string init {"registration-status": "searching"};
    def s as LteStatus init lteStatusFromRow($row);
    testing.assertFalse($s.registered);
    testing.assertEqual($s.operator, "");
}

# Verbs: local validation before any I/O

func failSetLteApnBlank() {
    setLteApn(offlineClient(), "lte1", "   ");
}

func testSetLteApnRejectsBlank() {
    testing.assertThrows("failSetLteApnBlank", "routeros");
}

# A router without the /interface/lte menu answers the read with an error;
# lteInterfaces turns any failed read into an empty list. The offline
# client's read fails too, so it lands on the same branch.
func testLteInterfacesEmptyWhenReadFails() {
    testing.assertEqual(len(lteInterfaces(offlineClient())), 0);
}
