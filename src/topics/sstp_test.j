# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the sstp topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testSstpServerFromRow() {
    def row as map of string to string init {
        "enabled": "true",
        "port": "443",
        "certificate": "router-le-cert",
        "default-profile": "default"
    };
    def s as SstpServer init sstpServerFromRow($row);
    testing.assertTrue($s.enabled);
    testing.assertEqual($s.port, 443);
    testing.assertEqual($s.certificate, "router-le-cert");
    testing.assertEqual($s.defaultProfile, "default");
}

func testSstpClientFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "sstpto-hq",
        "connect-to": "vpn.example.org",
        "user": "branch",
        "running": "false"
    };
    def cl as SstpClient init sstpClientFromRow($row);
    testing.assertEqual($cl.name, "sstpto-hq");
    testing.assertEqual($cl.connectTo, "vpn.example.org");
    testing.assertFalse($cl.running);
    testing.assertEqual($cl.comment, "");
}

# Verbs: local validation before any I/O

func failEnableSstpServerBadPort() {
    enableSstpServer(offlineClient(), "sstp-cert", 0);
}

func testEnableSstpServerRejectsBadPort() {
    testing.assertThrows("failEnableSstpServerBadPort", "routeros");
}

func failAddSstpClientEmptyPassword() {
    addSstpClient(offlineClient(), "sstpout", "vpn.example.org", "alice", "  ");
}

func testAddSstpClientRejectsEmptyPassword() {
    testing.assertThrows("failAddSstpClientEmptyPassword", "routeros");
}

func failAddSstpClientSpacedServer() {
    addSstpClient(offlineClient(), "sstpout", "vpn example.org", "alice", "secret");
}

func testAddSstpClientRejectsSpacedServer() {
    testing.assertThrows("failAddSstpClientSpacedServer", "routeros");
}

# SSTP clients were always created with verify-server-certificate=no.
func testAddSstpClientVerifiesByDefault() {
    def f as Fake init fakeStart(fakeRouter());
    def c as Client init fakeClient($f);
    addSstpClient($c, "sstpout", "vpn.example.org", "bob", "pw12345678");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, SSTP_CLIENT_PATH + "/add"));
    def added as string init "";
    for (def s in $log) {
        if (strings.startsWith($s, SSTP_CLIENT_PATH + "/add")) {
            $added = $s;
        }
    }
    testing.assertTrue(strings.contains($added, "=verify-server-certificate=yes"));
}

func testVerifyServerExtraOptOut() {
    testing.assertEqual(verifyServerExtra(false)["verify-server-certificate"], "no");
    testing.assertEqual(verifyServerExtra(true)["verify-server-certificate"], "yes");
}

func failAddSstpClientWithNoPassword() {
    addSstpClientWith(offlineClient(), "sstpout", "vpn.example.org", "bob", " ", false);
}

func testAddSstpClientWithRejectsEmptyPassword() {
    testing.assertThrows("failAddSstpClientWithNoPassword", "routeros");
}

# Re-enabling on another port kept the input rule on the old port
# (the rule was found by comment and left alone).
func testEnableSstpServerMovesFirewallPort() {
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
                "comment": "sstp: server"
            }
        ]));
    def c as Client init fakeClient($f);
    enableSstpServer($c, "vpncert", 8443);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, FIREWALL_PATH + "/set =dst-port=8443"));
    testing.assertFalse(fakeSaw($log, FIREWALL_PATH + "/add"));
}
