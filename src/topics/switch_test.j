# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the switch topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testSwitchChipFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "switch1",
        "type": "Atheros-8327"
    };
    def sw as SwitchChip init switchChipFromRow($row);
    testing.assertEqual($sw.id, "*1");
    testing.assertEqual($sw.name, "switch1");
    testing.assertEqual($sw.kind, "Atheros-8327");
}

func testSwitchHostFromRow() {
    def row as map of string to string init {
        "mac-address": "AA:BB:CC:DD:EE:FF",
        "ports": "ether3",
        "vlan-id": "10",
        "dynamic": "true"
    };
    def h as SwitchHost init switchHostFromRow($row);
    testing.assertEqual($h.mac, "AA:BB:CC:DD:EE:FF");
    testing.assertEqual($h.ports, "ether3");
    testing.assertEqual($h.vlanId, 10);
    testing.assertTrue($h.dynamic);
}

func testSwitchHostFromSparseRow() {
    def row as map of string to string init {"mac-address": "11:22:33:44:55:66", "ports": "ether1"};
    def h as SwitchHost init switchHostFromRow($row);
    testing.assertEqual($h.vlanId, 0);
    testing.assertFalse($h.dynamic);
}

# Verbs: reads that fall back to an empty list

# A never-connected client used to read as "no switch chip": the readers
# swallowed every error. Only a router !trap (missing menu) is empty now.
func failSwitchHostsOffline() {
    switchHosts(offlineClient());
}

func failSwitchChipsOffline() {
    switchChips(offlineClient());
}

func failLteInterfacesOffline() {
    lteInterfaces(offlineClient());
}

func failWifiInterfacesOffline() {
    wifiInterfaces(offlineClient());
}

func failWifiRegistrationsOffline() {
    wifiRegistrations(offlineClient());
}

func failWireguardInterfacesOffline() {
    wireguardInterfaces(offlineClient());
}

func failWireguardPeersOffline() {
    wireguardPeers(offlineClient());
}

func failWirelessInterfacesOffline() {
    wirelessInterfaces(offlineClient());
}

func failWifiClientsOffline() {
    wifiClients(offlineClient());
}

func testOptionalMenuReadersRethrowClosed() {
    testing.assertThrows("failSwitchHostsOffline", "closed");
    testing.assertThrows("failSwitchChipsOffline", "closed");
    testing.assertThrows("failLteInterfacesOffline", "closed");
    testing.assertThrows("failWifiInterfacesOffline", "closed");
    testing.assertThrows("failWifiRegistrationsOffline", "closed");
    testing.assertThrows("failWireguardInterfacesOffline", "closed");
    testing.assertThrows("failWireguardPeersOffline", "closed");
    testing.assertThrows("failWirelessInterfacesOffline", "closed");
    testing.assertThrows("failWifiClientsOffline", "closed");
}

func testIsMissingMenuOnlyForTrap() {
    testing.assertTrue(isMissingMenu("mikrotik", "trap"));
    testing.assertFalse(isMissingMenu("mikrotik", "fatal"));
    testing.assertFalse(isMissingMenu("closed", ""));
    testing.assertFalse(isMissingMenu("net", ""));
    testing.assertFalse(isMissingMenu("timeout", ""));
    testing.assertFalse(isMissingMenu("limit", ""));
}

func testOptionalMenuMissingReadsEmpty() {
    def f as Fake init fakeStart(fakeWithTrap(
        fakeRouter(),
        WIREGUARD_PATH + "/print",
        "0",
        "no such command prefix"));
    def c as Client init fakeClient($f);
    testing.assertEqual(len(wireguardInterfaces($c)), 0);
    fakeLog($c, $f);
}
