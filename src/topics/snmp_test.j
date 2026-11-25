# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the snmp topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testSnmpFromRow() {
    def row as map of string to string init {
        "enabled": "true",
        "contact": "noc@example.org",
        "location": "rack 3, office Berlin"
    };
    def st as SnmpSettings init snmpFromRow($row);
    testing.assertTrue($st.enabled);
    testing.assertEqual($st.contact, "noc@example.org");
    testing.assertEqual($st.location, "rack 3, office Berlin");
}

func testSnmpFromSparseRow() {
    def row as map of string to string init {"enabled": "false"};
    def st as SnmpSettings init snmpFromRow($row);
    testing.assertFalse($st.enabled);
    testing.assertEqual($st.contact, "");
}

func testSnmpCommunityFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "mon",
        "addresses": "10.0.9.0/24",
        "read-access": "true",
        "write-access": "false",
        "disabled": "false"
    };
    def com as SnmpCommunity init snmpCommunityFromRow($row);
    testing.assertEqual($com.id, "*1");
    testing.assertEqual($com.name, "mon");
    testing.assertEqual($com.addresses, "10.0.9.0/24");
    testing.assertTrue($com.readAccess);
    testing.assertFalse($com.writeAccess);
    testing.assertFalse($com.disabled);
}

func testSnmpCommunityFromRowDefaultPublic() {
    def row as map of string to string init {".id": "*2", "name": "public", "read-access": "true"};
    def com as SnmpCommunity init snmpCommunityFromRow($row);
    testing.assertEqual($com.name, "public");
    testing.assertEqual($com.addresses, "");
    testing.assertFalse($com.writeAccess);
}

# Verbs: local validation before any I/O

func failEnableSnmpSpacedCommunity() {
    enableSnmp(offlineClient(), "public ro", "");
}

func testEnableSnmpRejectsSpacedCommunity() {
    testing.assertThrows("failEnableSnmpSpacedCommunity", "routeros");
}

func failEnableSnmpBadAddress() {
    enableSnmp(offlineClient(), "monitoring", "192.168.88.0/33");
}

func testEnableSnmpRejectsBadAddress() {
    testing.assertThrows("failEnableSnmpBadAddress", "routeros");
}

# The community string is the secret: enableSnmp's lookup query and its
# add/set attribute must not show it in the verbose log.
func testSnmpCommunityRedactedInLog() {
    def q as string init formatQueriesFor(SNMP_COMMUNITY_PATH, ["?name=s3cret"]);
    testing.assertFalse(strings.contains($q, "s3cret"));
    def a as string init formatAttrsFor(
        SNMP_COMMUNITY_PATH + "/add",
        {"name": "s3cret", "addresses": snmpAllowedAddresses("")});
    testing.assertFalse(strings.contains($a, "s3cret"));
    testing.assertTrue(strings.contains($a, "addresses=0.0.0.0/0,::/0"));
}

# An empty sources argument used to send addresses="".
func testSnmpAllowedAddresses() {
    testing.assertEqual(snmpAllowedAddresses(" "), "0.0.0.0/0,::/0");
    testing.assertEqual(snmpAllowedAddresses("10.0.9.0/24, 10.0.8.1"), "10.0.9.0/24,10.0.8.1");
}
