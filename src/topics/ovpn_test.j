# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the ovpn topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testOvpnServerFromRow() {
    def row as map of string to string init {
        "enabled": "true",
        "port": "1194",
        "mode": "ip",
        "certificate": "router-le-cert",
        "default-profile": "default"
    };
    def s as OvpnServer init ovpnServerFromRow($row);
    testing.assertTrue($s.enabled);
    testing.assertEqual($s.port, 1194);
    testing.assertEqual($s.mode, "ip");
    testing.assertEqual($s.certificate, "router-le-cert");
}

func testOvpnClientFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "ovpnto-hq",
        "connect-to": "vpn.example.org",
        "user": "branch",
        "running": "true",
        "comment": "to HQ"
    };
    def cl as OvpnClient init ovpnClientFromRow($row);
    testing.assertEqual($cl.name, "ovpnto-hq");
    testing.assertEqual($cl.user, "branch");
    testing.assertTrue($cl.running);
    testing.assertEqual($cl.comment, "to HQ");
}

# Verbs: local validation before any I/O

func failEnableOvpnServerBadPort() {
    enableOvpnServer(offlineClient(), "ovpn-cert", 65536);
}

func testEnableOvpnServerRejectsBadPort() {
    testing.assertThrows("failEnableOvpnServerBadPort", "routeros");
}

func failAddOvpnClientSpacedName() {
    addOvpnClient(offlineClient(), "ovpn out", "vpn.example.org", "alice", "secret");
}

func testAddOvpnClientRejectsSpacedName() {
    testing.assertThrows("failAddOvpnClientSpacedName", "routeros");
}

# OpenVPN clients took RouterOS's default, no certificate check.
func testAddOvpnClientVerifiesByDefault() {
    def f as Fake init fakeStart(fakeRouter());
    def c as Client init fakeClient($f);
    addOvpnClient($c, "ovpnout", "vpn.example.org", "bob", "pw12345678");
    def log as list of string init fakeLog($c, $f);
    def added as string init "";
    for (def s in $log) {
        if (strings.startsWith($s, OVPN_CLIENT_PATH + "/add")) {
            $added = $s;
        }
    }
    testing.assertTrue(strings.contains($added, "=verify-server-certificate=yes"));
}

func testAddOvpnClientWithOptOut() {
    def f as Fake init fakeStart(fakeRouter());
    def c as Client init fakeClient($f);
    addOvpnClientWith($c, "ovpnout", "vpn.example.org", "bob", "pw12345678", false);
    def log as list of string init fakeLog($c, $f);
    def added as string init "";
    for (def s in $log) {
        if (strings.startsWith($s, OVPN_CLIENT_PATH + "/add")) {
            $added = $s;
        }
    }
    testing.assertTrue(strings.contains($added, "=verify-server-certificate=no"));
}

# Re-enabling on another port kept the input rule on the old port
# (the rule was found by comment and left alone).
func testEnableOvpnServerMovesFirewallPort() {
    def f as Fake init fakeStart(fakeWithRows(
        fakeWithRows(fakeRouter(), CERTIFICATE_PATH, [{".id": "*1", "name": "vpncert"}]),
        FIREWALL_PATH,
        [
            {
                ".id": "*9",
                "chain": "input",
                "action": "accept",
                "protocol": "tcp",
                "dst-port": "443",
                "comment": "ovpn: server"
            }
        ]));
    def c as Client init fakeClient($f);
    enableOvpnServer($c, "vpncert", 8443);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, FIREWALL_PATH + "/set =dst-port=8443"));
    testing.assertFalse(fakeSaw($log, FIREWALL_PATH + "/add"));
}
