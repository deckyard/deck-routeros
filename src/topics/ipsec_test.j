# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the ipsec topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testIpsecPeerFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "tobranch",
        "address": "203.0.113.99",
        "exchange-mode": "ike2",
        "disabled": "false"
    };
    def p as IpsecPeer init ipsecPeerFromRow($row);
    testing.assertEqual($p.id, "*1");
    testing.assertEqual($p.name, "tobranch");
    testing.assertEqual($p.address, "203.0.113.99");
    testing.assertEqual($p.exchangeMode, "ike2");
    testing.assertFalse($p.disabled);
}

func testIpsecPolicyFromRow() {
    def row as map of string to string init {
        ".id": "*2",
        "peer": "tobranch",
        "src-address": "192.168.10.0/24",
        "dst-address": "192.168.20.0/24",
        "tunnel": "true",
        "active": "true",
        "disabled": "false"
    };
    def pol as IpsecPolicy init ipsecPolicyFromRow($row);
    testing.assertEqual($pol.peer, "tobranch");
    testing.assertEqual($pol.srcAddress, "192.168.10.0/24");
    testing.assertEqual($pol.dstAddress, "192.168.20.0/24");
    testing.assertTrue($pol.tunnel);
    testing.assertTrue($pol.active);
}

func testIpsecPolicyFromRowInactive() {
    def row as map of string to string init {".id": "*3", "peer": "tobranch", "tunnel": "true"};
    def pol as IpsecPolicy init ipsecPolicyFromRow($row);
    testing.assertFalse($pol.active);
    testing.assertEqual($pol.srcAddress, "");
}

func testIpsecActiveFromRowEstablished() {
    def row as map of string to string init {
        "remote-address": "203.0.113.99",
        "state": "established",
        "uptime": "2h3m",
        "side": "initiator"
    };
    def a as IpsecActivePeer init ipsecActiveFromRow($row);
    testing.assertEqual($a.remoteAddress, "203.0.113.99");
    testing.assertTrue($a.established);
    testing.assertEqual($a.uptime, "2h3m");
    testing.assertEqual($a.side, "initiator");
}

func testIpsecActiveFromRowNegotiating() {
    def row as map of string to string init {
        "remote-address": "203.0.113.99",
        "state": "negotiating"
    };
    def a as IpsecActivePeer init ipsecActiveFromRow($row);
    testing.assertFalse($a.established);
    testing.assertEqual($a.uptime, "");
}

func testFirstChainRowIdFindsFirstInChain() {
    def rows as list of map of string to string init [
        {".id": "*1", "chain": "dstnat", "action": "dst-nat"},
        {".id": "*2", "chain": "srcnat", "action": "masquerade"},
        {".id": "*3", "chain": "srcnat", "action": "accept"}
    ];
    testing.assertEqual(firstChainRowId($rows, "srcnat"), "*2");
    testing.assertEqual(firstChainRowId($rows, "dstnat"), "*1");
}

func testFirstChainRowIdEmptyChain() {
    def rows as list of map of string to string init [
        {".id": "*1", "chain": "dstnat", "action": "dst-nat"}
    ];
    testing.assertEqual(firstChainRowId($rows, "srcnat"), "");
}

func testIpsecModeConfigPathConstant() {
    testing.assertEqual(IPSEC_MODE_CONFIG_PATH, "/ip/ipsec/mode-config");
}

# Verbs: local validation before any I/O

func failSetupIpsecTunnelEmptyPsk() {
    setupIpsecTunnel(
        offlineClient(),
        "site2",
        "203.0.113.2",
        "",
        "192.168.88.0/24",
        "192.168.89.0/24");
}

func testSetupIpsecTunnelRejectsEmptyPsk() {
    testing.assertThrows("failSetupIpsecTunnelEmptyPsk", "routeros");
}

func failSetupIpsecTunnelSubnetNoPrefix() {
    setupIpsecTunnel(
        offlineClient(),
        "site2",
        "203.0.113.2",
        "s3cret-psk",
        "192.168.88.0/24",
        "192.168.89.0");
}

func testSetupIpsecTunnelRejectsSubnetWithoutPrefix() {
    testing.assertThrows("failSetupIpsecTunnelSubnetNoPrefix", "routeros");
}

func failSetupIkev2ServerSpacedName() {
    setupIkev2Server(
        offlineClient(),
        "road warriors",
        "vpncert",
        "10.20.0.10-10.20.0.250",
        "1.1.1.1");
}

func testSetupIkev2ServerRejectsSpacedName() {
    testing.assertThrows("failSetupIkev2ServerSpacedName", "routeros");
}

func failTeardownIpsecTunnelEmptyName() {
    teardownIpsecTunnel(offlineClient(), "");
}

# An empty name matched every policy without a peer (the default template
# included) and removed them.
func testTeardownIpsecTunnelRejectsEmptyName() {
    testing.assertThrows("failTeardownIpsecTunnelEmptyName", "routeros");
}

func testHasPeerRowMatchesOnlyThatPeer() {
    def rows as list of map of string to string init [
        {".id": "*FFFFFE", "template": "true"},
        {".id": "*2", "peer": "office"}
    ];
    testing.assertTrue(hasPeerRow($rows, "office"));
    testing.assertFalse(hasPeerRow($rows, "branch"));
    testing.assertFalse(hasPeerRow($rows, ""));
}

func testTeardownIpsecTunnelKeepsPeerlessPolicies() {
    def f as Fake init fakeStart(fakeWithRows(
        fakeWithRows(fakeRouter(), IPSEC_PEER_PATH, [{".id": "*7", "name": "office"}]),
        IPSEC_POLICY_PATH,
        [{".id": "*FFFFFE", "template": "true"}, {".id": "*6", "peer": "office"}]));
    def c as Client init fakeClient($f);
    teardownIpsecTunnel($c, "office");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, IPSEC_POLICY_PATH + "/remove =.id=*6"));
    testing.assertFalse(fakeSaw($log, IPSEC_POLICY_PATH + "/remove =.id=*FFFFFE"));
    testing.assertTrue(fakeSaw($log, IPSEC_PEER_PATH + "/remove =.id=*7"));
}

# A run that stopped after the peer: calling again adds the identity and
# the policy instead of returning the peer id with nothing else.
func testSetupIpsecTunnelCompletesHalfBuiltTunnel() {
    def f as Fake init fakeStart(fakeWithRows(
        fakeRouter(),
        IPSEC_PEER_PATH,
        [{".id": "*7", "name": "office"}]));
    def c as Client init fakeClient($f);
    def id as string init setupIpsecTunnel(
        $c,
        "office",
        "203.0.113.9",
        "k3y",
        "10.1.0.0/24",
        "10.2.0.0/24");
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual($id, "*7");
    testing.assertFalse(fakeSaw($log, IPSEC_PEER_PATH + "/add"));
    testing.assertTrue(fakeSaw($log, IPSEC_IDENTITY_PATH + "/add"));
    testing.assertTrue(fakeSaw($log, IPSEC_POLICY_PATH + "/add"));
}
