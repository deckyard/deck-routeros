# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the addresslist topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testNormalizedListAddressForms() {
    testing.assertEqual(normalizedListAddress("203.0.113.7"), "203.0.113.7");
    testing.assertEqual(normalizedListAddress(" 203.0.113.7/32 "), "203.0.113.7");
    testing.assertEqual(normalizedListAddress("10.0.0.5/24"), "10.0.0.0/24");
    testing.assertEqual(normalizedListAddress("203.0.113.0/24"), "203.0.113.0/24");
    testing.assertEqual(normalizedListAddress("bad.example.org"), "bad.example.org");
}

func failListAddressWithSpaces() {
    normalizedListAddress("bad host");
}

func testNormalizedListAddressRejectsSpaces() {
    testing.assertThrows("failListAddressWithSpaces", "routeros");
}

func failListAddressBadCidr() {
    normalizedListAddress("203.0.113.0/99");
}

func testNormalizedListAddressRejectsBadCidr() {
    testing.assertThrows("failListAddressBadCidr", "routeros");
}

func failListAddressV6() {
    normalizedListAddress("2001:db8::1");
}

func failListAddressV6Net() {
    normalizedListAddress("2001:db8::/32");
}

func testNormalizedListAddressRejectsIpv6() {
    testing.assertThrows("failListAddressV6", "routeros");
    testing.assertThrows("failListAddressV6Net", "routeros");
}

func addressListFake() {
    return fakeWithRows(
        fakeRouter(),
        ADDRESS_LIST_PATH,
        [
            {".id": "*1", "list": "blocklist", "address": "203.0.113.7"},
            {".id": "*2", "list": "vpnusers", "address": "203.0.113.7"},
            {".id": "*3", "list": "blocklist", "address": "198.51.100.1"},
            {".id": "*4", "list": "blocklist", "address": "192.0.2.9", "dynamic": "true"}
        ]);
}

func testAddToAddressListFindsNormalizedEntry() {
    def f as Fake init fakeStart(addressListFake());
    def c as Client init fakeClient($f);
    testing.assertEqual(addToAddressList($c, "blocklist", "203.0.113.7/32", ""), "*1");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw(
        $log,
        "/ip/firewall/address-list/print ?list=blocklist ?address=203.0.113.7"));
    testing.assertFalse(fakeSaw($log, "/ip/firewall/address-list/add"));
}

func testAddressListEntriesFiltersOnTheRouter() {
    def f as Fake init fakeStart(addressListFake());
    def c as Client init fakeClient($f);
    testing.assertEqual(len(addressListEntries($c, "vpnusers")), 1);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/ip/firewall/address-list/print ?list=vpnusers"));
}

func testClearAddressListBatchesStaticEntries() {
    def f as Fake init fakeStart(addressListFake());
    def c as Client init fakeClient($f);
    clearAddressList($c, "blocklist");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/ip/firewall/address-list/remove =.id=*1,*3"));
    testing.assertFalse(fakeSaw($log, "/ip/firewall/address-list/remove =.id=*1,*3,*4"));
}

func testAddressListsReadsOnlyTheListColumn() {
    def f as Fake init fakeStart(addressListFake());
    def c as Client init fakeClient($f);
    testing.assertEqual(len(addressLists($c)), 2);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/ip/firewall/address-list/print =.proplist=list"));
}

func testDistinctListsDeduplicatesInOrder() {
    def rows as list of map of string to string init [
        {".id": "*1", "list": "blocklist", "address": "203.0.113.7"},
        {".id": "*2", "list": "vpnusers", "address": "10.100.0.2"},
        {".id": "*3", "list": "blocklist", "address": "198.51.100.1"}
    ];
    def names as list of string init distinctLists($rows);
    testing.assertEqual(len($names), 2);
    testing.assertEqual($names[0], "blocklist");
    testing.assertEqual($names[1], "vpnusers");
}

func testDistinctListsEmptyRows() {
    def rows as list of map of string to string init [];
    testing.assertEqual(len(distinctLists($rows)), 0);
}

func testAddressListEntryFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "list": "blocklist",
        "address": "203.0.113.7",
        "timeout": "23h59m50s",
        "dynamic": "false",
        "disabled": "false",
        "comment": "ssh scanner"
    };
    def a as AddressListEntry init addressListEntryFromRow($row);
    testing.assertEqual($a.id, "*1");
    testing.assertEqual($a.listName, "blocklist");
    testing.assertEqual($a.address, "203.0.113.7");
    testing.assertEqual($a.timeout, "23h59m50s");
    testing.assertFalse($a.dynamic);
    testing.assertFalse($a.disabled);
    testing.assertEqual($a.comment, "ssh scanner");
}

func testAddressListEntryFromSparseRow() {
    def row as map of string to string init {
        ".id": "*2",
        "list": "vpnusers",
        "address": "10.100.0.0/24"
    };
    def a as AddressListEntry init addressListEntryFromRow($row);
    testing.assertEqual($a.timeout, "");
    testing.assertFalse($a.dynamic);
    testing.assertEqual($a.comment, "");
}

# Verbs: local validation before any I/O. offlineClient() has no socket, so a
# verb that got past its checks would fail with kind "closed", not "routeros".

func failAddToAddressListSpacedName() {
    addToAddressList(offlineClient(), "bad actors", "203.0.113.7", "");
}

func testAddToAddressListRejectsSpacedName() {
    testing.assertThrows("failAddToAddressListSpacedName", "routeros");
}

func failAddToAddressListBadAddress() {
    addToAddressList(offlineClient(), "blocked", "203.0.113.0/40", "");
}

func testAddToAddressListRejectsBadNetwork() {
    testing.assertThrows("failAddToAddressListBadAddress", "routeros");
}

func failAddToAddressListTimedBadTimeout() {
    addToAddressListTimed(offlineClient(), "blocked", "203.0.113.7", "soon", "");
}

func testAddToAddressListTimedRejectsBadTimeout() {
    testing.assertThrows("failAddToAddressListTimedBadTimeout", "routeros");
}

func failDropAddressListEmptyName() {
    dropAddressList(offlineClient(), "", CHAIN_INPUT, "drop");
}

func testDropAddressListRejectsEmptyName() {
    testing.assertThrows("failDropAddressListEmptyName", "routeros");
}

func failDropAddressListEmptyChain() {
    dropAddressList(offlineClient(), "blocked", " ", "drop");
}

func testDropAddressListRejectsEmptyChain() {
    testing.assertThrows("failDropAddressListEmptyChain", "routeros");
}
