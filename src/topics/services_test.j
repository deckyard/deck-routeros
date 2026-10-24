# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - white-box tests for the services topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testServiceFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "winbox",
        "port": "8291",
        "address": "10.0.9.0/24",
        "disabled": "false",
        "invalid": "false"
    };
    def s as Service init serviceFromRow($row);
    testing.assertEqual($s.id, "*1");
    testing.assertEqual($s.name, "winbox");
    testing.assertEqual($s.port, 8291);
    testing.assertEqual($s.address, "10.0.9.0/24");
    testing.assertEqual($s.certificate, "");
    testing.assertFalse($s.invalid);
    testing.assertFalse($s.disabled);
}

func testServiceFromRowSslWithoutCertIsInvalid() {
    def row as map of string to string init {
        ".id": "*2",
        "name": "www-ssl",
        "port": "443",
        "invalid": "true",
        "disabled": "true"
    };
    def s as Service init serviceFromRow($row);
    testing.assertEqual($s.port, 443);
    testing.assertTrue($s.invalid);
    testing.assertTrue($s.disabled);
    testing.assertEqual($s.address, "");
}

func testEnsureServiceNameAcceptsKnown() {
    ensureServiceName("api");
    ensureServiceName("api-ssl");
    ensureServiceName("ssh");
    ensureServiceName("winbox");
    ensureServiceName("telnet");
    testing.assertTrue(true);
}

func failServiceNameUnknown() {
    ensureServiceName("http");
}

func testEnsureServiceNameRejectsUnknown() {
    testing.assertThrows("failServiceNameUnknown", "routeros");
}

func testServiceUsingPortFindsOtherService() {
    def rows as list of map of string to string init [
        {"name": "ssh", "port": "22"},
        {"name": "www", "port": "80"}
    ];
    testing.assertEqual(serviceUsingPort($rows, 80, "ssh"), "www");
    testing.assertEqual(serviceUsingPort($rows, 2200, "ssh"), "");
}

func testServiceUsingPortIgnoresOwnPort() {
    def rows as list of map of string to string init [{"name": "ssh", "port": "22"}];
    testing.assertEqual(serviceUsingPort($rows, 22, "ssh"), "");
    testing.assertEqual(serviceUsingPort($rows, 22, "www"), "ssh");
}

# Verbs: local validation before any I/O

func failDisableServiceUnknown() {
    disableService(offlineClient(), "http");
}

func testDisableServiceRejectsUnknownName() {
    testing.assertThrows("failDisableServiceUnknown", "routeros");
}

func failEnableServiceUnknown() {
    enableService(offlineClient(), "SSH");
}

func testEnableServiceRejectsUnknownName() {
    testing.assertThrows("failEnableServiceUnknown", "routeros");
}

func failRestrictServiceBadAddress() {
    restrictService(offlineClient(), "winbox", "192.168.88.0/33");
}

func testRestrictServiceRejectsBadAddress() {
    testing.assertThrows("failRestrictServiceBadAddress", "routeros");
}

func failServiceByNameUnknown() {
    serviceByName(offlineClient(), "smtp");
}

func testServiceByNameRejectsUnknownName() {
    testing.assertThrows("failServiceByNameUnknown", "routeros");
}

func failSetServicePortZero() {
    setServicePort(offlineClient(), "ssh", 0);
}

func testSetServicePortRejectsZero() {
    testing.assertThrows("failSetServicePortZero", "routeros");
}
