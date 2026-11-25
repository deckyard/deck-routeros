# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the neighbor topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testNeighborFromRow() {
    def row as map of string to string init {
        "interface": "ether2",
        "address": "10.0.9.31",
        "mac-address": "AA:BB:CC:DD:EE:31",
        "identity": "sw-lobby",
        "platform": "MikroTik",
        "board": "CRS328",
        "version": "7.15.2"
    };
    def n as Neighbor init neighborFromRow($row);
    testing.assertEqual($n.interfaceName, "ether2");
    testing.assertEqual($n.address, "10.0.9.31");
    testing.assertEqual($n.mac, "AA:BB:CC:DD:EE:31");
    testing.assertEqual($n.identity, "sw-lobby");
    testing.assertEqual($n.platform, "MikroTik");
    testing.assertEqual($n.board, "CRS328");
    testing.assertEqual($n.version, "7.15.2");
}

func testNeighborFromLayer2Row() {
    def row as map of string to string init {
        "interface": "ether1",
        "mac-address": "AA:BB:CC:DD:EE:01",
        "platform": "Cisco"
    };
    def n as Neighbor init neighborFromRow($row);
    testing.assertEqual($n.address, "");
    testing.assertEqual($n.platform, "Cisco");
}

# v7 lists a neighbor behind a bridge port as "ether2,bridge"; an exact
# match found it on neither.
func testNeighborOnInterfaceCommaList() {
    testing.assertTrue(neighborOnInterface("ether2,bridge", "ether2"));
    testing.assertTrue(neighborOnInterface("ether2,bridge", "bridge"));
    testing.assertTrue(neighborOnInterface("ether1", "ether1"));
    testing.assertFalse(neighborOnInterface("ether12,bridge", "ether1"));
    testing.assertFalse(neighborOnInterface("ether1", ""));
}
