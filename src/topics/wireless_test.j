# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - white-box tests for the wireless topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testEnsureSsidAcceptsSpacesAndLimit() {
    ensureSsid("My Home WiFi");
    ensureSsid("x");
    ensureSsid("abcdefghijklmnopqrstuvwxyzabcdef");
    testing.assertTrue(true);
}

func failEnsureSsidEmpty() {
    ensureSsid("   ");
}

func testEnsureSsidRejectsEmpty() {
    testing.assertThrows("failEnsureSsidEmpty", "routeros");
}

func failEnsureSsidTooLong() {
    ensureSsid("abcdefghijklmnopqrstuvwxyzabcdefg");
}

func testEnsureSsidRejectsTooLong() {
    testing.assertThrows("failEnsureSsidTooLong", "routeros");
}

func testEnsureWifiPasswordAcceptsBounds() {
    ensureWifiPassword("12345678");
    ensureWifiPassword("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk");
    testing.assertTrue(true);
}

func failEnsureWifiPasswordTooShort() {
    ensureWifiPassword("1234567");
}

func testEnsureWifiPasswordRejectsTooShort() {
    testing.assertThrows("failEnsureWifiPasswordTooShort", "routeros");
}

func failEnsureWifiPasswordTooLong() {
    ensureWifiPassword("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl");
}

func testEnsureWifiPasswordRejectsTooLong() {
    testing.assertThrows("failEnsureWifiPasswordTooLong", "routeros");
}

func testWifiProfileNameIsDeterministic() {
    testing.assertEqual(wifiProfileName("wlan1"), "routeros-wlan1");
    testing.assertEqual(wifiProfileName("wlanguest"), "routeros-wlanguest");
}

func testWirelessFromRowPhysicalRadio() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "wlan1",
        "ssid": "My Home WiFi",
        "mode": "ap-bridge",
        "band": "5ghz-a/n/ac",
        "frequency": "auto",
        "security-profile": "routeros-wlan1",
        "running": "true",
        "disabled": "false",
        "comment": "living room"
    };
    def w as WirelessInterface init wirelessFromRow($row);
    testing.assertEqual($w.id, "*1");
    testing.assertEqual($w.name, "wlan1");
    testing.assertEqual($w.ssid, "My Home WiFi");
    testing.assertEqual($w.mode, "ap-bridge");
    testing.assertEqual($w.band, "5ghz-a/n/ac");
    testing.assertEqual($w.frequency, "auto");
    testing.assertEqual($w.securityProfile, "routeros-wlan1");
    testing.assertEqual($w.masterInterface, "");
    testing.assertTrue($w.running);
    testing.assertFalse($w.disabled);
    testing.assertEqual($w.comment, "living room");
}

func testWirelessFromRowVirtualAp() {
    def row as map of string to string init {
        ".id": "*2",
        "name": "wlanguest",
        "ssid": "Guest",
        "master-interface": "wlan1",
        "disabled": "false"
    };
    def w as WirelessInterface init wirelessFromRow($row);
    testing.assertEqual($w.masterInterface, "wlan1");
    testing.assertEqual($w.band, "");
    testing.assertFalse($w.running);
}

func testWifiClientFromRow() {
    def row as map of string to string init {
        "interface": "wlan1",
        "mac-address": "AA:BB:CC:DD:EE:FF",
        "signal-strength": "-52dBm",
        "tx-rate": "866Mbps",
        "rx-rate": "780Mbps",
        "uptime": "1h2m3s"
    };
    def w as WifiClient init wifiClientFromRow($row);
    testing.assertEqual($w.interfaceName, "wlan1");
    testing.assertEqual($w.mac, "AA:BB:CC:DD:EE:FF");
    testing.assertEqual($w.signalStrength, "-52dBm");
    testing.assertEqual($w.txRate, "866Mbps");
    testing.assertEqual($w.rxRate, "780Mbps");
    testing.assertEqual($w.uptime, "1h2m3s");
}

# Verbs: local validation before any I/O. offlineClient() has no socket, so a
# verb that got past its checks would fail with kind "closed", not "routeros".

func failSetupWifiAccessPointEmptySsid() {
    setupWifiAccessPoint(offlineClient(), "wlan1", "  ", "correct-horse");
}

func testSetupWifiAccessPointRejectsEmptySsid() {
    testing.assertThrows("failSetupWifiAccessPointEmptySsid", "routeros");
}

func failSetupWifiAccessPointShortPassword() {
    setupWifiAccessPoint(offlineClient(), "wlan1", "home", "1234567");
}

func testSetupWifiAccessPointRejectsShortPassword() {
    testing.assertThrows("failSetupWifiAccessPointShortPassword", "routeros");
}

func failSetWifiSsidTooLong() {
    setWifiSsid(offlineClient(), "wlan1", strings.repeat("a", 33));
}

func testSetWifiSsidRejectsTooLong() {
    testing.assertThrows("failSetWifiSsidTooLong", "routeros");
}

func failSetWifiPasswordTooShort() {
    setWifiPassword(offlineClient(), "wlan1", "short");
}

func testSetWifiPasswordRejectsTooShort() {
    testing.assertThrows("failSetWifiPasswordTooShort", "routeros");
}

func failAddVirtualApSpacedName() {
    addVirtualAp(offlineClient(), "wlan1", "guest ap", "guests", "guest-pass-1");
}

func testAddVirtualApRejectsSpacedName() {
    testing.assertThrows("failAddVirtualApSpacedName", "routeros");
}

func failAddVirtualApLongPassword() {
    addVirtualAp(offlineClient(), "wlan1", "wlanguest", "guests", strings.repeat("p", 64));
}

func testAddVirtualApRejectsLongPassword() {
    testing.assertThrows("failAddVirtualApLongPassword", "routeros");
}

# The readers treat a menu they cannot read as absent (a router without the
# classic wireless package) and return an empty list instead of throwing.

func testWirelessInterfacesEmptyWhenMenuUnreadable() {
    testing.assertEqual(len(wirelessInterfaces(offlineClient())), 0);
}

func testWifiClientsEmptyWhenMenuUnreadable() {
    testing.assertEqual(len(wifiClients(offlineClient())), 0);
}
