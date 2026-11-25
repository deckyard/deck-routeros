# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

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
    setWifiSsid(offlineClient(), "wlan1", strings.replicate("a", 33));
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
    addVirtualAp(offlineClient(), "wlan1", "wlanguest", "guests", strings.replicate("p", 64));
}

func testAddVirtualApRejectsLongPassword() {
    testing.assertThrows("failAddVirtualApLongPassword", "routeros");
}

# The readers treat a menu they cannot read as absent (a router without the
# classic wireless package) and return an empty list instead of throwing.

# A profile shared with another radio was rewritten (password, mode and
# authentication types) for every radio on it.
func testProfileIsShared() {
    def rows as list of map of string to string init [
        {"name": "wlan1", "security-profile": "corp"},
        {"name": "wlan2", "security-profile": "corp"},
        {"name": "wlan3", "security-profile": "solo"},
        {"name": "wlan4", "security-profile": "default"}
    ];
    testing.assertTrue(profileIsShared($rows, "wlan1", "corp"));
    testing.assertFalse(profileIsShared($rows, "wlan3", "solo"));
    testing.assertTrue(profileIsShared($rows, "wlan4", "default"));
    testing.assertTrue(profileIsShared($rows, "wlan4", ""));
}

func testSetWifiPasswordMovesSharedProfileAside() {
    def rows as list of map of string to string init [
        {".id": "*1", "name": "wlan1", "security-profile": "corp"},
        {".id": "*2", "name": "wlan2", "security-profile": "corp"}
    ];
    def f as Fake init fakeStart(fakeWithRows(
        fakeWithRows(fakeRouter(), WIRELESS_PATH, $rows),
        WIRELESS_SECURITY_PATH,
        [{".id": "*5", "name": "corp", "mode": "dynamic-keys"}]));
    def c as Client init fakeClient($f);
    setWifiPassword($c, "wlan1", "new-secret-1");
    def log as list of string init fakeLog($c, $f);
    testing.assertFalse(fakeSaw($log, WIRELESS_SECURITY_PATH + "/set =.id=*5"));
    testing.assertTrue(fakeSaw($log, WIRELESS_SECURITY_PATH + "/add"));
    testing.assertTrue(fakeSaw($log, WIRELESS_PATH + "/set"));
}

func testSetWifiPasswordOwnProfileOnlyKey() {
    def rows as list of map of string to string init [
        {".id": "*1", "name": "wlan1", "security-profile": "corp"}
    ];
    def f as Fake init fakeStart(fakeWithRows(
        fakeWithRows(fakeRouter(), WIRELESS_PATH, $rows),
        WIRELESS_SECURITY_PATH,
        [{".id": "*5", "name": "corp", "mode": "dynamic-keys"}]));
    def c as Client init fakeClient($f);
    setWifiPassword($c, "wlan1", "new-secret-1");
    def log as list of string init fakeLog($c, $f);
    def sets as list of string init [];
    for (def s in $log) {
        if (strings.startsWith($s, WIRELESS_SECURITY_PATH + "/set")) {
            $sets[] = $s;
        }
    }
    testing.assertEqual(len($sets), 1);
    testing.assertFalse(strings.contains($sets[0], "authentication-types"));
    testing.assertFalse(strings.contains($sets[0], "=mode="));
    testing.assertTrue(strings.contains($sets[0], "=wpa2-pre-shared-key=new-secret-1"));
}

func failSsidTooManyBytes() {
    ensureSsid("ääääääääääääääääääää");
}

func failWifiPasswordNonAscii() {
    ensureWifiPassword("passwört123");
}

# len counts characters: 20 umlauts (40 bytes) and a non-ASCII
# passphrase passed and the router refused them.
func testWifiValidatorsCountBytesAndAscii() {
    testing.assertThrows("failSsidTooManyBytes", "routeros");
    testing.assertThrows("failWifiPasswordNonAscii", "routeros");
    ensureSsid("Café");
    ensureWifiPassword("correct horse battery");
}
