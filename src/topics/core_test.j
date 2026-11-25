# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the core topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

# A client that never connected: its zero-value session has no socket, so a
# verb that got past its local validation fails with kind "closed" instead of
# reaching the network. The verb tests in every topic build on it.
func offlineClient() {
    def c as Client;
    return $c;
}

func testApiPathAddsLeadingSlash() {
    testing.assertEqual(apiPath("interface"), "/interface");
}

func testApiPathKeepsGoodPath() {
    testing.assertEqual(apiPath("/ip/firewall/filter"), "/ip/firewall/filter");
}

func testApiPathStripsTrailingSlashes() {
    testing.assertEqual(apiPath("/interface/bridge//"), "/interface/bridge");
}

func testApiPathTrimsWhitespace() {
    testing.assertEqual(apiPath("  /interface  "), "/interface");
}

func failApiPathEmpty() {
    apiPath("   ");
}

func testApiPathRejectsEmpty() {
    testing.assertThrows("failApiPathEmpty", "routeros");
}

func failApiPathRoot() {
    apiPath("/");
}

func testApiPathRejectsRoot() {
    testing.assertThrows("failApiPathRoot", "routeros");
}

func testBoolWord() {
    testing.assertEqual(boolWord(true), "yes");
    testing.assertEqual(boolWord(false), "no");
}

func testRowValueReadsPresentKey() {
    def row as map of string to string init {"name": "ether1"};
    testing.assertEqual(rowValue($row, "name"), "ether1");
}

func testRowValueDefaultsMissingKey() {
    def row as map of string to string init {"name": "ether1"};
    testing.assertEqual(rowValue($row, "comment"), "");
}

func testRowBoolAcceptsBothSpellings() {
    def row as map of string to string init {"a": "true", "b": "yes", "c": "false", "d": "no"};
    testing.assertTrue(rowBool($row, "a"));
    testing.assertTrue(rowBool($row, "b"));
    testing.assertFalse(rowBool($row, "c"));
    testing.assertFalse(rowBool($row, "d"));
}

func testRowBoolMissingKeyIsFalse() {
    def row as map of string to string init {"name": "ether1"};
    testing.assertFalse(rowBool($row, "running"));
}

func testFindRowByFieldFindsMatch() {
    def rows as list of map of string to string init [
        {".id": "*1", "name": "ether1"},
        {".id": "*2", "name": "ether2"}
    ];
    def row as map of string to string init findRowByField($rows, "name", "ether2");
    testing.assertEqual(rowValue($row, ".id"), "*2");
}

func testFindRowByFieldReturnsFirstMatch() {
    def rows as list of map of string to string init [
        {".id": "*1", "bridge": "brlan"},
        {".id": "*2", "bridge": "brlan"}
    ];
    def row as map of string to string init findRowByField($rows, "bridge", "brlan");
    testing.assertEqual(rowValue($row, ".id"), "*1");
}

func testFindRowByFieldMissReturnsEmptyMap() {
    def rows as list of map of string to string init [{".id": "*1", "name": "ether1"}];
    def row as map of string to string init findRowByField($rows, "name", "ether9");
    testing.assertEqual(len($row), 0);
}

func failEnsureNameEmpty() {
    ensureName("   ", "bridge");
}

func testEnsureNameRejectsEmpty() {
    testing.assertThrows("failEnsureNameEmpty", "routeros");
}

func failEnsureNameSpaces() {
    ensureName("br lan", "bridge");
}

func testEnsureNameRejectsSpaces() {
    testing.assertThrows("failEnsureNameSpaces", "routeros");
}

func testEnsureNameAcceptsPlainName() {
    ensureName("brlan", "bridge");
    testing.assertTrue(true);
}

func failEnsureIdEmpty() {
    ensureId("");
}

func testEnsureIdRejectsEmpty() {
    testing.assertThrows("failEnsureIdEmpty", "routeros");
}

func failEnsurePortZero() {
    ensurePort(0);
}

func testEnsurePortRejectsZero() {
    testing.assertThrows("failEnsurePortZero", "routeros");
}

func failEnsurePortTooBig() {
    ensurePort(65536);
}

func testEnsurePortRejectsTooBig() {
    testing.assertThrows("failEnsurePortTooBig", "routeros");
}

func testEnsurePortAcceptsBounds() {
    ensurePort(1);
    ensurePort(65535);
    testing.assertTrue(true);
}

func testEnsurePortSpecAcceptsForms() {
    ensurePortSpec("80");
    ensurePortSpec("80,443");
    ensurePortSpec("8000-8100");
    testing.assertTrue(true);
}

func failEnsurePortSpecLetters() {
    ensurePortSpec("80a");
}

func testEnsurePortSpecRejectsLetters() {
    testing.assertThrows("failEnsurePortSpecLetters", "routeros");
}

func failEnsurePortSpecEmpty() {
    ensurePortSpec("");
}

func testEnsurePortSpecRejectsEmpty() {
    testing.assertThrows("failEnsurePortSpecEmpty", "routeros");
}

func testMergeRowsLaterRowsWin() {
    def rows as list of map of string to string init [
        {"status": "checking for updates"},
        {"status": "downloading changelog", "channel": "stable"},
        {"status": "finished", "installed-version": "7.15.2", "latest-version": "7.16"}
    ];
    def merged as map of string to string init mergeRows($rows);
    testing.assertEqual($merged["status"], "finished");
    testing.assertEqual($merged["channel"], "stable");
    testing.assertEqual($merged["installed-version"], "7.15.2");
    testing.assertEqual($merged["latest-version"], "7.16");
    testing.assertEqual(len($merged), 4);
}

func testMergeRowsEmptyInput() {
    def rows as list of map of string to string init [];
    def merged as map of string to string init mergeRows($rows);
    testing.assertEqual(len($merged), 0);
}

func testEnsureIpAddressAcceptsBothVersions() {
    ensureIpAddress("192.168.88.1");
    ensureIpAddress("2001:db8::1");
    ensureIpAddress("  10.0.0.1  ");
    testing.assertTrue(true);
}

func failEnsureIpAddressWords() {
    ensureIpAddress("not-an-ip");
}

func testEnsureIpAddressRejectsWords() {
    testing.assertThrows("failEnsureIpAddressWords", "routeros");
}

func failEnsureIpAddressBadOctet() {
    ensureIpAddress("10.0.0.999");
}

func testEnsureIpAddressRejectsBadOctet() {
    testing.assertThrows("failEnsureIpAddressBadOctet", "routeros");
}

func testEnsureCidrAcceptsNetwork() {
    ensureCidr("192.168.88.0/24");
    ensureCidr("2001:db8::/64");
    testing.assertTrue(true);
}

func failEnsureCidrNoPrefix() {
    ensureCidr("192.168.88.0");
}

func testEnsureCidrRejectsMissingPrefix() {
    testing.assertThrows("failEnsureCidrNoPrefix", "routeros");
}

func failEnsureCidrBadPrefix() {
    ensureCidr("192.168.88.0/33");
}

func testEnsureCidrRejectsBadPrefix() {
    testing.assertThrows("failEnsureCidrBadPrefix", "routeros");
}

func testEnsureInNetworkAcceptsMember() {
    ensureInNetwork("192.168.77.0/24", "192.168.77.10", "gateway");
    testing.assertTrue(true);
}

func failEnsureInNetworkOutside() {
    ensureInNetwork("192.168.77.0/24", "192.168.78.1", "gateway");
}

func testEnsureInNetworkRejectsOutsider() {
    testing.assertThrows("failEnsureInNetworkOutside", "routeros");
}

func testEnsureMacAcceptsBothCases() {
    ensureMac("AA:BB:CC:DD:EE:FF");
    ensureMac("aa:bb:cc:0d:ee:0f");
    testing.assertTrue(true);
}

func failEnsureMacNoColons() {
    ensureMac("AABBCCDDEEFF");
}

func testEnsureMacRejectsMissingColons() {
    testing.assertThrows("failEnsureMacNoColons", "routeros");
}

func failEnsureMacTooShort() {
    ensureMac("AA:BB:CC:DD:EE");
}

func testEnsureMacRejectsFivePairs() {
    testing.assertThrows("failEnsureMacTooShort", "routeros");
}

func failEnsureMacBadHex() {
    ensureMac("AA:BB:CC:DD:EE:GG");
}

func testEnsureMacRejectsBadHex() {
    testing.assertThrows("failEnsureMacBadHex", "routeros");
}

func failEnsureMacUnevenPair() {
    ensureMac("AA:BB:CC:DD:EE:F");
}

func testEnsureMacRejectsUnevenPair() {
    testing.assertThrows("failEnsureMacUnevenPair", "routeros");
}

func testNormalizedAddressListSingle() {
    testing.assertEqual(normalizedAddressList("1.1.1.1"), "1.1.1.1");
}

func testNormalizedAddressListTrimsSpaces() {
    testing.assertEqual(normalizedAddressList(" 1.1.1.1 , 9.9.9.9 "), "1.1.1.1,9.9.9.9");
}

func failNormalizedAddressListEmptyEntry() {
    normalizedAddressList("1.1.1.1,,9.9.9.9");
}

func testNormalizedAddressListRejectsEmptyEntry() {
    testing.assertThrows("failNormalizedAddressListEmptyEntry", "routeros");
}

func failNormalizedAddressListBadEntry() {
    normalizedAddressList("1.1.1.1,example.com");
}

func testNormalizedAddressListRejectsHostname() {
    testing.assertThrows("failNormalizedAddressListBadEntry", "routeros");
}

func testIsIpAddress() {
    testing.assertTrue(isIpAddress("192.168.88.254"));
    testing.assertTrue(isIpAddress("2001:db8::1"));
    testing.assertTrue(isIpAddress("  10.0.0.1  "));
    testing.assertFalse(isIpAddress("ether1"));
    testing.assertFalse(isIpAddress("10.0.0.999"));
    testing.assertFalse(isIpAddress(""));
}

func testRowIntParsesAndDefaults() {
    def row as map of string to string init {"sent": "4", "junk": "many"};
    testing.assertEqual(rowInt($row, "sent"), 4);
    testing.assertEqual(rowInt($row, "missing"), 0);
    testing.assertEqual(rowInt($row, "junk"), 0);
}

func testEnsureHostAcceptsNamesAndAddresses() {
    ensureHost("1.1.1.1");
    ensureHost("router.lan");
    ensureHost("2001:db8::1");
    testing.assertTrue(true);
}

func failEnsureHostEmpty() {
    ensureHost("");
}

func testEnsureHostRejectsEmpty() {
    testing.assertThrows("failEnsureHostEmpty", "routeros");
}

func failEnsureHostSpaces() {
    ensureHost("my router");
}

func testEnsureHostRejectsSpaces() {
    testing.assertThrows("failEnsureHostSpaces", "routeros");
}

# a self-move is caught before the request reaches the router, so the
# zero-value client is never dialled
func failMoveRuleOntoItself() {
    def c as Client;
    moveRule($c, "/ip/firewall/filter", "*A", "*A");
}

func testMoveRuleRejectsSelfMove() {
    testing.assertThrows("failMoveRuleOntoItself", "routeros");
}

func failMoveRuleEmptyId() {
    def c as Client;
    moveRule($c, "/ip/firewall/filter", "   ", "*A");
}

func testMoveRuleRejectsEmptyId() {
    testing.assertThrows("failMoveRuleEmptyId", "routeros");
}

func failMoveRuleEmptyPath() {
    def c as Client;
    moveRule($c, "", "*A", "*B");
}

func testMoveRuleRejectsEmptyPath() {
    testing.assertThrows("failMoveRuleEmptyPath", "routeros");
}

func testSetVerboseReturnsACopy() {
    def c as Client;
    testing.assertFalse(isVerbose($c));
    def loud as Client init setVerbose($c, true);
    testing.assertTrue(isVerbose($loud));
    # value semantics: the original is untouched
    testing.assertFalse(isVerbose($c));
    testing.assertEqual($loud.user, $c.user);
}

func testSetVerboseCanTurnItOffAgain() {
    def c as Client;
    def loud as Client init setVerbose($c, true);
    def quiet as Client init setVerbose($loud, false);
    testing.assertTrue(isVerbose($loud));
    testing.assertFalse(isVerbose($quiet));
}

func testFormatAttrsRendersPairsInOrder() {
    def attrs as map of string to string init {"chain": "forward", "action": "drop"};
    testing.assertEqual(formatAttrsFor("/x/add", $attrs), " chain=forward action=drop");
}

func testFormatAttrsEmptyIsEmptyString() {
    def attrs as map of string to string init {};
    testing.assertEqual(formatAttrsFor("/x/add", $attrs), "");
}

func testFormatQueries() {
    def q as list of string init ["?name=ether1"];
    testing.assertEqual(formatQueriesFor("/interface", $q), " ?name=ether1");
    def none as list of string init [];
    testing.assertEqual(formatQueriesFor("/interface", $none), "");
}

# verbose mode prints what goes on the wire, and that includes credentials
func testSecretKeysAreRedacted() {
    testing.assertTrue(isSecretKey("password"));
    testing.assertTrue(isSecretKey("secret"));
    testing.assertTrue(isSecretKey("passphrase"));
    testing.assertTrue(isSecretKey("ipsec-secret"));
    testing.assertTrue(isSecretKey("private-key"));
    testing.assertTrue(isSecretKey("wpa2-pre-shared-key"));
    testing.assertTrue(isSecretKey("wpa-pre-shared-key"));
    testing.assertTrue(isSecretKey("security.passphrase"));
}

# the near-misses: none of these carry a credential
func testNonSecretKeysAreNotRedacted() {
    testing.assertFalse(isSecretKey("public-key"));
    testing.assertFalse(isSecretKey("key-usage"));
    testing.assertFalse(isSecretKey("passive"));
    testing.assertFalse(isSecretKey("passthrough"));
    testing.assertFalse(isSecretKey("user"));
    testing.assertFalse(isSecretKey("address"));
}

func testFormatAttrsRedactsTheValueNotTheKey() {
    def attrs as map of string to string init {"user": "router", "password": "hunter2"};
    testing.assertEqual(formatAttrsFor("/x/add", $attrs), " user=router password=<redacted>");
}

func testLoggedValuePassesThroughOrdinaryValues() {
    testing.assertEqual(
        loggedValueFor("/ip/address/add", "address", "192.168.88.1/24"),
        "192.168.88.1/24");
    testing.assertEqual(loggedValueFor("/user/add", "password", "hunter2"), "<redacted>");
}

func testTruthyWordAcceptsAffirmatives() {
    testing.assertTrue(truthyWord("1"));
    testing.assertTrue(truthyWord("yes"));
    testing.assertTrue(truthyWord("true"));
    testing.assertTrue(truthyWord("on"));
    testing.assertTrue(truthyWord("  YES  "));
    testing.assertTrue(truthyWord("True"));
}

func testTruthyWordRejectsEverythingElse() {
    testing.assertFalse(truthyWord(""));
    testing.assertFalse(truthyWord("0"));
    testing.assertFalse(truthyWord("no"));
    testing.assertFalse(truthyWord("false"));
    testing.assertFalse(truthyWord("maybe"));
}

# Verbs: local validation before any I/O

func failConnectWithPortZero() {
    connectWith("192.168.88.1", 0, "admin", "secret", false, true);
}

func testConnectWithRejectsPortZero() {
    testing.assertThrows("failConnectWithPortZero", "routeros");
}

func failConnectWithPortTooBig() {
    connectWith("192.168.88.1", 70000, "admin", "secret", true, false);
}

func testConnectWithRejectsPortTooBig() {
    testing.assertThrows("failConnectWithPortTooBig", "routeros");
}

func failConnectPlain() {
    connect("192.168.88.1", "admin", "secret");
}

func testConnectRefusesPlainLogin() {
    testing.assertThrows("failConnectPlain", "routeros");
}

func failConnectWithPlainNotAllowed() {
    connectWith("192.168.88.1", 8728, "admin", "secret", false, false);
}

func testConnectWithRefusesPlainWithoutAllowInsecureAuth() {
    testing.assertThrows("failConnectWithPlainNotAllowed", "routeros");
}

# A plain login opted into gets past mikrotik's own plain-TCP refusal (kind
# "mikrotik") to the dial. The port was free a moment ago and is closed
# again, so the local kernel refuses it and nothing leaves the machine: kind
# "net".
func failConnectWithPlainAllowed() {
    def listener as net.Listener init net.listen("127.0.0.1:0");
    def port as int init convert.toInt(strings.split(net.address($listener), ":")[1]);
    net.close($listener);
    connectWith("127.0.0.1", $port, "admin", "secret", false, true);
}

func testConnectWithPlainAllowedPassesMikrotiksRefusal() {
    testing.assertThrows("failConnectWithPlainAllowed", "net");
}

func failGetAllEmptyPath() {
    getAll(offlineClient(), "");
}

func testGetAllRejectsEmptyPath() {
    testing.assertThrows("failGetAllEmptyPath", "routeros");
}

func failAddRootPath() {
    add(offlineClient(), "/", {"name": "brlan"});
}

func testAddRejectsRootPath() {
    testing.assertThrows("failAddRootPath", "routeros");
}

func failSetEmptyId() {
    set(offlineClient(), "/interface/bridge", "", {"comment": "lan"});
}

func testSetRejectsEmptyId() {
    testing.assertThrows("failSetEmptyId", "routeros");
}

func failUpdateEmptyId() {
    update(offlineClient(), "/interface/bridge", "  ", {"comment": "lan"});
}

func testUpdateRejectsEmptyId() {
    testing.assertThrows("failUpdateEmptyId", "routeros");
}

func failRemoveEmptyId() {
    remove(offlineClient(), "/interface/bridge", "");
}

func testRemoveRejectsEmptyId() {
    testing.assertThrows("failRemoveEmptyId", "routeros");
}

func failEnableEmptyId() {
    enable(offlineClient(), "/ip/firewall/filter", "");
}

func testEnableRejectsEmptyId() {
    testing.assertThrows("failEnableEmptyId", "routeros");
}

func failDisableEmptyId() {
    disable(offlineClient(), "/ip/firewall/filter", "");
}

func testDisableRejectsEmptyId() {
    testing.assertThrows("failDisableEmptyId", "routeros");
}

func failFindByNameEmptyPath() {
    findByName(offlineClient(), "  ", "brlan");
}

func testFindByNameRejectsEmptyPath() {
    testing.assertThrows("failFindByNameEmptyPath", "routeros");
}

func failIdByNameRootPath() {
    idByName(offlineClient(), "/", "brlan");
}

func testIdByNameRejectsRootPath() {
    testing.assertThrows("failIdByNameRootPath", "routeros");
}

func failRemoveByNameEmptyPath() {
    removeByName(offlineClient(), "", "brlan");
}

func testRemoveByNameRejectsEmptyPath() {
    testing.assertThrows("failRemoveByNameEmptyPath", "routeros");
}

func failMoveRuleToTopEmptyId() {
    moveRuleToTop(offlineClient(), "/ip/firewall/filter", "");
}

func testMoveRuleToTopRejectsEmptyId() {
    testing.assertThrows("failMoveRuleToTopEmptyId", "routeros");
}

func failMoveRuleToBottomEmptyId() {
    moveRuleToBottom(offlineClient(), "/ip/firewall/filter", " ");
}

func testMoveRuleToBottomRejectsEmptyId() {
    testing.assertThrows("failMoveRuleToBottomEmptyId", "routeros");
}

# A self-signed certificate (SAN IP:127.0.0.1, DNS:localhost), valid to 2126.
def const TEST_CA_PEM as string init "-----BEGIN CERTIFICATE-----\n" +
    "MIIBfzCCASSgAwIBAgIUAhr1ZW5i6HXmzEYKoR3hGSYiBhgwCgYIKoZIzj0EAwIw\n" +
    "FjEUMBIGA1UEAwwLcm91dGVyLnRlc3QwIBcNMjYxMTE5MjAxNDQxWhgPMjEyNjEw\n" +
    "MjYyMDE0NDFaMBYxFDASBgNVBAMMC3JvdXRlci50ZXN0MFkwEwYHKoZIzj0CAQYI\n" +
    "KoZIzj0DAQcDQgAEojlGEbTkhAtO38fwjqq8OIJnSzZynCp8/C1qlVTr/6EOci28\n" +
    "iQy0h//lcqQNsPUhtC5NwBLadir1aPmw2SozdKNOMEwwHQYDVR0OBBYEFOf60QHK\n" +
    "wlKe5wdy/bGNNSD9d6tMMA8GA1UdEwEB/wQFMAMBAf8wGgYDVR0RBBMwEYcEfwAA\n" +
    "AYIJbG9jYWxob3N0MAoGCCqGSM49BAMCA0kAMEYCIQChC2kUHEkp/0kgieSo5Gk4\n" +
    "bOx0wXpRYV+FHSY4ihs8dgIhANniB0yvBRFCQQgM+bJHKCcV1VjpkrcsQUcwTV+b\n" +
    "NRzf\n" +
    "-----END CERTIFICATE-----\n";

func testOptionsWithCACarryTheCertificate() {
    def o as mikrotik.Options init optionsWithCA("10.0.0.1", 18729, "admin", "secret", TEST_CA_PEM);
    testing.assertTrue($o.tls);
    testing.assertFalse($o.skipVerify);
    testing.assertEqual($o.host, "10.0.0.1");
    testing.assertEqual($o.port, 18729);
    testing.assertEqual($o.user, "admin");
    testing.assertEqual(encoding.decode("utf-8", $o.caCert), TEST_CA_PEM);
}

func failConnectTLSWithCANoPem() {
    connectTLSWithCA("192.168.88.1", "admin", "secret", "");
}

func failConnectTLSWithCAKeyOnly() {
    connectTLSWithCA("192.168.88.1", "admin", "secret", "-----BEGIN PRIVATE KEY-----\n");
}

func failConnectWithCAPortZero() {
    connectWithCA("192.168.88.1", 0, "admin", "secret", TEST_CA_PEM);
}

func testConnectWithCAValidatesBeforeDialling() {
    testing.assertThrows("failConnectTLSWithCANoPem", "routeros");
    testing.assertThrows("failConnectTLSWithCAKeyOnly", "routeros");
    testing.assertThrows("failConnectWithCAPortZero", "routeros");
}

# Nothing listens on loopback port 1, so nothing leaves the machine. The
# certificate is accepted by the TLS layer (an unparseable one would fail
# there with kind "runtime"), and the dial fails with kind "net".
func failDialWithCA() {
    mikrotik.connect(optionsWithCA("127.0.0.1", 1, "admin", "secret", TEST_CA_PEM));
}

func testConnectWithCAReachesTheDial() {
    testing.assertThrows("failDialWithCA", "net");
}

func testFakeRouterRoundTrip() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        "/interface",
        [{".id": "*1", "name": "ether1"}, {".id": "*2", "name": "ether2"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    testing.assertEqual(idByName($c, "/interface", "ether2"), "*2");
    testing.assertEqual(add($c, "/interface/bridge", {"name": "br"}), "*F1");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/interface/print ?name=ether2"));
    testing.assertTrue(fakeSaw($log, "/interface/bridge/add =name=br"));
}

func testFindRowByFieldNeverMatchesEmptyOrAbsent() {
    def rows as list of map of string to string init [
        {".id": "*1", "chain": "input"},
        {".id": "*2", "comment": ""},
        {".id": "*3", "comment": "drop all"}
    ];
    testing.assertEqual(len(findRowByField($rows, "comment", "")), 0);
    testing.assertEqual(rowValue(findRowByField($rows, "comment", "drop all"), ".id"), "*3");
}

func testRequiredIdByCommentRefusesEmptyBeforeIo() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        "/ip/firewall/filter",
        [{".id": "*1", "chain": "input", "action": "accept"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        removeFirewallRuleByComment($c, "");
    } catch (e) {
        $got = $e.kind;
    }
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual($got, "routeros");
    testing.assertFalse(fakeSaw($log, "/ip/firewall/filter/remove"));
}

func testRequiredIdByCommentFiltersOnTheRouter() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        "/ip/firewall/filter",
        [{".id": "*1", "chain": "input"}, {".id": "*2", "comment": "drop all"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    removeFirewallRuleByComment($c, "drop all");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw(
        $log,
        "/ip/firewall/filter/print =.proplist=.id,comment ?comment=drop all"));
    testing.assertTrue(fakeSaw($log, "/ip/firewall/filter/remove =.id=*2"));
}

func testFindByNameEmptySendsNothing() {
    def f as Fake init fakeStart(fakeRouter());
    def c as Client init fakeClient($f);
    testing.assertEqual(idByName($c, "/interface", ""), "");
    def log as list of string init fakeLog($c, $f);
    testing.assertFalse(fakeSaw($log, "/interface/print"));
}

func testRemoveManyBatchesIds() {
    def ids as list of string init [];
    for (def i in 1..251) {
        $ids[] = "*" + convert.toString($i);
    }
    def f as Fake init fakeStart(fakeRouter());
    def c as Client init fakeClient($f);
    testing.assertEqual(removeMany($c, "/ip/firewall/connection", $ids), 250);
    def log as list of string init fakeLog($c, $f);
    def removes as int init 0;
    for (def s in $log) {
        if (strings.startsWith($s, "/ip/firewall/connection/remove =.id=")) {
            $removes = $removes + 1;
        }
    }
    testing.assertEqual($removes, 3);
    testing.assertTrue(fakeSaw($log, "/ip/firewall/connection/remove =.id=*1,*2,"));
}

func failEnsurePortSpecLoneDash() {
    ensurePortSpec("-");
}

func failEnsurePortSpecEmptyEntry() {
    ensurePortSpec("80,,443");
}

func failEnsurePortSpecTooHigh() {
    ensurePortSpec("99999");
}

func failEnsurePortSpecZero() {
    ensurePortSpec("0");
}

func failEnsurePortSpecBackwards() {
    ensurePortSpec("9000-8000");
}

func testEnsurePortSpecRejectsMalformedEntries() {
    testing.assertThrows("failEnsurePortSpecLoneDash", "routeros");
    testing.assertThrows("failEnsurePortSpecEmptyEntry", "routeros");
    testing.assertThrows("failEnsurePortSpecTooHigh", "routeros");
    testing.assertThrows("failEnsurePortSpecZero", "routeros");
    testing.assertThrows("failEnsurePortSpecBackwards", "routeros");
    ensurePortSpec("1-65535,80");
}

func failEnsureNameNewline() {
    ensureName("a\nb", "bridge");
}

func failEnsureNameTab() {
    ensureName("a\tb", "bridge");
}

func testEnsureNameRejectsControlChars() {
    testing.assertThrows("failEnsureNameNewline", "routeros");
    testing.assertThrows("failEnsureNameTab", "routeros");
}

func failEnsureIpv4OnV6() {
    ensureIpv4Address("2001:db8::1", "gateway");
}

func testEnsureIpv4AddressRejectsV6() {
    testing.assertThrows("failEnsureIpv4OnV6", "routeros");
    ensureIpv4Address("192.0.2.1", "gateway");
}

func testMoreSecretKeysAreRedacted() {
    testing.assertTrue(isSecretKey("preshared-key"));
    testing.assertTrue(isSecretKey("tcp-md5-key"));
    testing.assertTrue(isSecretKey("pin"));
    testing.assertTrue(isSecretKey("contents"));
    testing.assertTrue(isSecretKey("authentication-key"));
    testing.assertFalse(isSecretKey("public-key"));
    testing.assertFalse(isSecretKey("key-usage"));
    testing.assertFalse(isSecretKey("key"));
}

func testPathSecretsAreRedacted() {
    testing.assertEqual(
        formatAttrsFor("/container/envs/add", {"list": "db", "key": "PW", "value": "hunter2"}),
        " list=db key=PW value=<redacted>");
    testing.assertEqual(
        formatAttrsFor("/ip/dhcp-server/option/add", {"value": "0x01"}),
        " value=0x01");
    testing.assertEqual(
        formatAttrsFor("/snmp/community/add", {"name": "s3cret", "read-access": "yes"}),
        " name=<redacted> read-access=yes");
    testing.assertEqual(
        loggedValueFor("/file/add", "contents", "-----BEGIN PRIVATE KEY-----"),
        "<redacted>");
}

func testQueryWordsOnSecretsAreRedacted() {
    testing.assertEqual(formatQueriesFor("/snmp/community", ["?name=s3cret"]), " ?name=<redacted>");
    testing.assertEqual(
        formatQueriesFor("/ppp/secret", ["?password=x", "?name=bob", "?#|"]),
        " ?password=<redacted> ?name=bob ?#|");
    testing.assertEqual(formatQueriesFor("/interface", ["?name=ether1"]), " ?name=ether1");
}
