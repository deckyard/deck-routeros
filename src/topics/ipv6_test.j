# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - white-box tests for the ipv6 topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testIpv6SettingsFromRow() {
    def row as map of string to string init {
        "disable-ipv6": "yes",
        "forward": "no",
        "accept-router-advertisements": "yes",
        "accept-redirects": "no",
        "max-neighbor-entries": "8192"
    };
    def s as Ipv6Settings init ipv6SettingsFromRow($row);
    testing.assertTrue($s.disabled);
    testing.assertFalse($s.forward);
    testing.assertTrue($s.acceptRouterAdvertisements);
    testing.assertEqual($s.maxNeighborEntries, 8192);
}

func testIpv6SettingsFromSparseRow() {
    def row as map of string to string init {"forward": "true"};
    def s as Ipv6Settings init ipv6SettingsFromRow($row);
    testing.assertFalse($s.disabled);
    testing.assertTrue($s.forward);
    testing.assertEqual($s.maxNeighborEntries, 0);
}

func testIpv6AddressFromRow() {
    def row as map of string to string init {
        ".id": "*3",
        "address": "2001:db8:1::1/64",
        "interface": "brlan",
        "advertise": "true",
        "eui-64": "false",
        "link-local": "false",
        "dynamic": "false",
        "disabled": "false",
        "comment": "lan gateway"
    };
    def a as Ipv6Address init ipv6AddressFromRow($row);
    testing.assertEqual($a.address, "2001:db8:1::1/64");
    testing.assertEqual($a.interfaceName, "brlan");
    testing.assertTrue($a.advertise);
    testing.assertFalse($a.dynamic);
    testing.assertEqual($a.comment, "lan gateway");
}

func testIpv6AddressFromRowLinkLocalIsDynamic() {
    def row as map of string to string init {
        ".id": "*1",
        "address": "fe80::1/64",
        "interface": "ether1",
        "link-local": "true",
        "dynamic": "true"
    };
    def a as Ipv6Address init ipv6AddressFromRow($row);
    testing.assertTrue($a.linkLocal);
    testing.assertTrue($a.dynamic);
    testing.assertFalse($a.advertise);
}

func testIpv6NdFromRow() {
    def row as map of string to string init {
        ".id": "*2",
        "interface": "brlan",
        "ra-interval": "3m20s-10m",
        "ra-lifetime": "30m",
        "managed-address-configuration": "false",
        "other-configuration": "true",
        "advertise-dns": "true",
        "disabled": "false"
    };
    def n as Ipv6Nd init ipv6NdFromRow($row);
    testing.assertEqual($n.interfaceName, "brlan");
    testing.assertEqual($n.raLifetime, "30m");
    testing.assertFalse($n.managed);
    testing.assertTrue($n.otherConfig);
    testing.assertTrue($n.advertiseDns);
}

func testIpv6CidrAcceptsIpv6() {
    ensureIpv6Cidr("2001:db8:1::1/64");
    ensureIpv6Cidr("fd00::/8");
    testing.assertTrue(true);
}

# the likely slip: passing the v4 address to a v6 call
func failIpv6CidrIsIpv4() {
    ensureIpv6Cidr("192.168.88.0/24");
}

func testIpv6CidrRejectsIpv4() {
    testing.assertThrows("failIpv6CidrIsIpv4", "routeros");
}

func failIpv6CidrNoPrefix() {
    ensureIpv6Cidr("2001:db8:1::1");
}

func testIpv6CidrRejectsMissingPrefix() {
    testing.assertThrows("failIpv6CidrNoPrefix", "routeros");
}

func failIpv6CidrGarbage() {
    ensureIpv6Cidr("not-an-address/64");
}

func testIpv6CidrRejectsGarbage() {
    testing.assertThrows("failIpv6CidrGarbage", "routeros");
}

# Verbs: local validation before any I/O

func failAddIpv6AddressIpv4() {
    addIpv6Address(offlineClient(), "192.168.88.1/24", "ether2");
}

func testAddIpv6AddressRejectsIpv4() {
    testing.assertThrows("failAddIpv6AddressIpv4", "routeros");
}

func failAddIpv6AddressWithEmptyInterface() {
    addIpv6AddressWith(offlineClient(), "2001:db8:1::1/64", "  ", true, false);
}

func testAddIpv6AddressWithRejectsEmptyInterface() {
    testing.assertThrows("failAddIpv6AddressWithEmptyInterface", "routeros");
}

func failRemoveIpv6AddressNoPrefix() {
    removeIpv6Address(offlineClient(), "2001:db8:1::1");
}

func testRemoveIpv6AddressRejectsMissingPrefix() {
    testing.assertThrows("failRemoveIpv6AddressNoPrefix", "routeros");
}

func failIpv6AddressesOnEmptyInterface() {
    ipv6AddressesOn(offlineClient(), "");
}

func testIpv6AddressesOnRejectsEmptyInterface() {
    testing.assertThrows("failIpv6AddressesOnEmptyInterface", "routeros");
}

func failAdvertiseIpv6OnSpacedInterface() {
    advertiseIpv6On(offlineClient(), "ether 2");
}

func testAdvertiseIpv6OnRejectsSpacedInterface() {
    testing.assertThrows("failAdvertiseIpv6OnSpacedInterface", "routeros");
}

func failStopAdvertisingIpv6OnEmptyInterface() {
    stopAdvertisingIpv6On(offlineClient(), "");
}

func testStopAdvertisingIpv6OnRejectsEmptyInterface() {
    testing.assertThrows("failStopAdvertisingIpv6OnEmptyInterface", "routeros");
}

func failSetIpv6NdFlagsEmptyInterface() {
    setIpv6NdFlags(offlineClient(), "", true, true);
}

func testSetIpv6NdFlagsRejectsEmptyInterface() {
    testing.assertThrows("failSetIpv6NdFlagsEmptyInterface", "routeros");
}
