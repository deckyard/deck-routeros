# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the wireguard topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testEnsureWireguardKeyAcceptsValidKey() {
    ensureWireguardKey("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopo=");
    ensureWireguardKey("  hIe5R2FTPjvrIrVXfy41chvUJ4CyOTdBEI3pQGea0R0=  ");
    testing.assertTrue(true);
}

func failWireguardKeyTooShort() {
    ensureWireguardKey("ABCDEF=");
}

func testEnsureWireguardKeyRejectsTooShort() {
    testing.assertThrows("failWireguardKeyTooShort", "routeros");
}

func failWireguardKeyNoPadding() {
    ensureWireguardKey("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqA");
}

func testEnsureWireguardKeyRejectsMissingPadding() {
    testing.assertThrows("failWireguardKeyNoPadding", "routeros");
}

func failWireguardKeyBadCharacter() {
    ensureWireguardKey("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop!=");
}

func testEnsureWireguardKeyRejectsBadCharacter() {
    testing.assertThrows("failWireguardKeyBadCharacter", "routeros");
}

func testNormalizedAllowedAddressForms() {
    testing.assertEqual(normalizedAllowedAddress("10.100.0.2/32"), "10.100.0.2/32");
    testing.assertEqual(
        normalizedAllowedAddress(" 10.100.0.0/24 , 192.168.88.0/24 "),
        "10.100.0.0/24,192.168.88.0/24");
    testing.assertEqual(normalizedAllowedAddress("0.0.0.0/0"), "0.0.0.0/0");
}

func failAllowedAddressBareIp() {
    normalizedAllowedAddress("10.100.0.2");
}

func testNormalizedAllowedAddressRejectsBareIp() {
    testing.assertThrows("failAllowedAddressBareIp", "routeros");
}

func failAllowedAddressEmptyEntry() {
    normalizedAllowedAddress("10.100.0.2/32,,10.100.0.3/32");
}

func testNormalizedAllowedAddressRejectsEmptyEntry() {
    testing.assertThrows("failAllowedAddressEmptyEntry", "routeros");
}

func testWireguardFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "wgvpn",
        "public-key": "hIe5R2FTPjvrIrVXfy41chvUJ4CyOTdBEI3pQGea0R0=",
        "listen-port": "13231",
        "mtu": "1420",
        "running": "true",
        "disabled": "false",
        "comment": "road warriors"
    };
    def w as WireguardInterface init wireguardFromRow($row);
    testing.assertEqual($w.id, "*1");
    testing.assertEqual($w.name, "wgvpn");
    testing.assertEqual($w.publicKey, "hIe5R2FTPjvrIrVXfy41chvUJ4CyOTdBEI3pQGea0R0=");
    testing.assertEqual($w.listenPort, 13231);
    testing.assertEqual($w.mtu, "1420");
    testing.assertTrue($w.running);
    testing.assertFalse($w.disabled);
    testing.assertEqual($w.comment, "road warriors");
}

func testWireguardPeerFromRowDialIn() {
    def row as map of string to string init {
        ".id": "*2",
        "interface": "wgvpn",
        "public-key": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq=",
        "allowed-address": "10.100.0.2/32",
        "last-handshake": "1m2s",
        "rx": "1048576",
        "tx": "2097152",
        "disabled": "false",
        "comment": "laptop"
    };
    def p as WireguardPeer init wireguardPeerFromRow($row);
    testing.assertEqual($p.interfaceName, "wgvpn");
    testing.assertEqual($p.publicKey, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq=");
    testing.assertEqual($p.endpointAddress, "");
    testing.assertEqual($p.allowedAddress, "10.100.0.2/32");
    testing.assertEqual($p.lastHandshake, "1m2s");
    testing.assertEqual($p.rx, "1048576");
    testing.assertEqual($p.tx, "2097152");
    testing.assertEqual($p.comment, "laptop");
}

func testWireguardPeerFromRowDialOut() {
    def row as map of string to string init {
        ".id": "*3",
        "interface": "wghome",
        "public-key": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq=",
        "endpoint-address": "vpn.example.org",
        "endpoint-port": "13231",
        "allowed-address": "10.100.0.0/24",
        "persistent-keepalive": "25s"
    };
    def p as WireguardPeer init wireguardPeerFromRow($row);
    testing.assertEqual($p.endpointAddress, "vpn.example.org");
    testing.assertEqual($p.endpointPort, "13231");
    testing.assertEqual($p.keepalive, "25s");
    testing.assertEqual($p.lastHandshake, "");
    testing.assertFalse($p.disabled);
}

# Verbs: local validation before any I/O

func failAddWireguardSpacedName() {
    addWireguard(offlineClient(), "wg home", 13231);
}

func testAddWireguardRejectsSpacedName() {
    testing.assertThrows("failAddWireguardSpacedName", "routeros");
}

func failAddWireguardPortZero() {
    addWireguard(offlineClient(), "wghome", 0);
}

func testAddWireguardRejectsPortZero() {
    testing.assertThrows("failAddWireguardPortZero", "routeros");
}

func failSetupWireguardServerNoPrefix() {
    setupWireguardServer(offlineClient(), "wghome", 13231, "10.10.0.1");
}

func testSetupWireguardServerRejectsAddressWithoutPrefix() {
    testing.assertThrows("failSetupWireguardServerNoPrefix", "routeros");
}

# A re-run with another port left the interface and the rule on the old
# one; the address was skipped when it existed on any other interface.
func testSetupWireguardServerMovesPortAndAddsOwnAddress() {
    def f as Fake init fakeStart(fakeWithRows(
        fakeWithRows(
            fakeWithRows(
                fakeRouter(),
                WIREGUARD_PATH,
                [{".id": "*3", "name": "wgvpn", "listen-port": "13231"}]),
            IP_ADDRESS_PATH,
            [{".id": "*8", "address": "10.100.0.1/24", "interface": "ether9"}]),
        FIREWALL_PATH,
        [
            {
                ".id": "*9",
                "chain": "input",
                "action": "accept",
                "protocol": "udp",
                "dst-port": "13231",
                "comment": "wireguard: wgvpn"
            }
        ]));
    def c as Client init fakeClient($f);
    setupWireguardServer($c, "wgvpn", 51820, "10.100.0.1/24");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, WIREGUARD_PATH + "/set =listen-port=51820 =.id=*3"));
    testing.assertTrue(fakeSaw($log, IP_ADDRESS_PATH + "/add"));
    testing.assertTrue(fakeSaw($log, FIREWALL_PATH + "/set"));
    testing.assertFalse(fakeSaw($log, FIREWALL_PATH + "/add"));
}

func testRemoveWireguardRemovesEveryStaticAddress() {
    def f as Fake init fakeStart(fakeWithRows(
        fakeWithRows(fakeRouter(), WIREGUARD_PATH, [{".id": "*3", "name": "wgvpn"}]),
        IP_ADDRESS_PATH,
        [
            {".id": "*1", "address": "10.100.0.1/24", "interface": "wgvpn"},
            {".id": "*2", "address": "10.101.0.1/24", "interface": "wgvpn"},
            {".id": "*4", "address": "10.102.0.1/24", "interface": "ether1"}
        ]));
    def c as Client init fakeClient($f);
    removeWireguard($c, "wgvpn");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, IP_ADDRESS_PATH + "/remove =.id=*1,*2"));
    testing.assertFalse(fakeSaw($log, IP_ADDRESS_PATH + "/remove =.id=*4"));
}

func failWireguardKeyAllPadding() {
    ensureWireguardKey("============================================");
}

func failWireguardKeyInnerPadding() {
    ensureWireguardKey("ABCDEFGHIJ=LMNOPQRSTUVWXYZabcdefghijklmnopq=");
}

# 44 "=" or a "=" inside passed the length and alphabet checks.
func testEnsureWireguardKeyRejectsBadPadding() {
    testing.assertThrows("failWireguardKeyAllPadding", "routeros");
    testing.assertThrows("failWireguardKeyInnerPadding", "routeros");
}
