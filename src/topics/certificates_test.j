# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the certificates topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testDurationToDaysForms() {
    testing.assertEqual(durationToDays("52w"), 364);
    testing.assertEqual(durationToDays("4w2d"), 30);
    testing.assertEqual(durationToDays("1d12h"), 1);
    testing.assertEqual(durationToDays("23h59m"), 0);
    testing.assertEqual(durationToDays("90"), 0);
    testing.assertEqual(durationToDays("2d"), 2);
}

func testCertificateFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "router-lan",
        "common-name": "router.lan",
        "issuer": "CN=router.lan",
        "expires-after": "51w6d",
        "invalid-after": "2027-07-20 12:00:00",
        "private-key": "true",
        "trusted": "true",
        "ca": "false"
    };
    def cert as Certificate init certificateFromRow($row);
    testing.assertEqual($cert.id, "*1");
    testing.assertEqual($cert.name, "router-lan");
    testing.assertEqual($cert.commonName, "router.lan");
    testing.assertEqual($cert.issuer, "CN=router.lan");
    testing.assertEqual($cert.expiresAfter, "51w6d");
    testing.assertTrue($cert.hasPrivateKey);
    testing.assertTrue($cert.trusted);
    testing.assertFalse($cert.isCa);
}

func testCertificateFromSparseRow() {
    def row as map of string to string init {".id": "*2", "name": "template"};
    def cert as Certificate init certificateFromRow($row);
    testing.assertEqual($cert.expiresAfter, "");
    testing.assertFalse($cert.hasPrivateKey);
    testing.assertFalse($cert.isCa);
}

func testExpiringFromFilters() {
    def certs as list of Certificate init [
        Certificate{
            id: "*1",
            name: "old",
            commonName: "a",
            issuer: "x",
            expiresAfter: "2w",
            invalidAfter: "",
            hasPrivateKey: true,
            trusted: false,
            isCa: false,
            expired: false
        },
        Certificate{
            id: "*2",
            name: "fresh",
            commonName: "b",
            issuer: "x",
            expiresAfter: "51w6d",
            invalidAfter: "",
            hasPrivateKey: true,
            trusted: false,
            isCa: false,
            expired: false
        },
        Certificate{
            id: "*3",
            name: "unknown",
            commonName: "c",
            issuer: "x",
            expiresAfter: "",
            invalidAfter: "",
            hasPrivateKey: false,
            trusted: false,
            isCa: false,
            expired: false
        }
    ];
    def soon as list of Certificate init expiringFrom($certs, 30);
    testing.assertEqual(len($soon), 1);
    testing.assertEqual($soon[0].name, "old");
}

func failPemCertificateJunk() {
    ensurePemCertificate("not a pem");
}

func testEnsurePemCertificateRejectsJunk() {
    testing.assertThrows("failPemCertificateJunk", "routeros");
}

func testEnsurePemCertificateAcceptsPem() {
    ensurePemCertificate("-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----\n");
    testing.assertTrue(true);
}

func failPemKeyJunk() {
    ensurePemKey("-----BEGIN CERTIFICATE-----");
}

func testEnsurePemKeyRejectsCertificate() {
    testing.assertThrows("failPemKeyJunk", "routeros");
}

func testEnsurePemKeyAcceptsForms() {
    ensurePemKey("-----BEGIN PRIVATE KEY-----\nMIG...\n-----END PRIVATE KEY-----\n");
    ensurePemKey("-----BEGIN EC PRIVATE KEY-----\nMHc...\n-----END EC PRIVATE KEY-----\n");
    testing.assertTrue(true);
}

# Verbs: local validation before any I/O

func failAssignServiceCertificateSsh() {
    assignServiceCertificate(offlineClient(), "ssh", "webcert");
}

func testAssignServiceCertificateRejectsNonTlsService() {
    testing.assertThrows("failAssignServiceCertificateSsh", "routeros");
}

func failEnableLetsEncryptSpacedName() {
    enableLetsEncrypt(offlineClient(), "router example.org");
}

func testEnableLetsEncryptRejectsSpacedName() {
    testing.assertThrows("failEnableLetsEncryptSpacedName", "routeros");
}

func failGenerateSelfSignedTooLong() {
    generateSelfSigned(offlineClient(), "webcert", "router.example.org", 7301);
}

func testGenerateSelfSignedRejectsOverlongValidity() {
    testing.assertThrows("failGenerateSelfSignedTooLong", "routeros");
}

func failGenerateSelfSignedNoCommonName() {
    generateSelfSigned(offlineClient(), "webcert", "  ", 365);
}

func testGenerateSelfSignedRejectsEmptyCommonName() {
    testing.assertThrows("failGenerateSelfSignedNoCommonName", "routeros");
}

func failImportCertificatePemJunkKey() {
    importCertificatePem(
        offlineClient(),
        "webcert",
        "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n",
        "not a key");
}

func testImportCertificatePemRejectsJunkKey() {
    testing.assertThrows("failImportCertificatePemJunkKey", "routeros");
}

func testSubjectAltNameForNamesAndAddresses() {
    # Go's TLS verification ignores the common name, so a self-signed
    # certificate without a SAN never verified with connectTLSWithCA.
    testing.assertEqual(subjectAltNameFor("router.lan"), "DNS:router.lan");
    testing.assertEqual(subjectAltNameFor(" 192.168.88.1 "), "IP:192.168.88.1");
    testing.assertEqual(subjectAltNameFor("fd00::1"), "IP:fd00::1");
}

func testImportCertificateRemovesFilesWhenImportFails() {
    def r as FakeRouter init fakeWithTrap(
        fakeRouter(),
        "/certificate/import",
        "",
        "no certificates found");
    $r = fakeWithRows(
        $r,
        FILE_PATH,
        [{".id": "*7", "name": "web.crt"}, {".id": "*8", "name": "web.key"}]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        importCertificatePem(
            $c,
            "web",
            "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n",
            "-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n");
    } catch (e) {
        $got = $e.kind;
    }
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual($got, "mikrotik");
    testing.assertTrue(fakeSaw($log, "/file/remove =.id=*7"));
    testing.assertTrue(fakeSaw($log, "/file/remove =.id=*8"));
}

func testDurationToDaysMoreForms() {
    testing.assertEqual(durationToDays("8w2d03:32:06"), 58);
    testing.assertEqual(durationToDays("-3d"), -3);
    testing.assertEqual(durationToDays("-1s"), -1);
    testing.assertEqual(durationToDays("500ms"), 0);
    testing.assertEqual(durationToDays("1d00:00:05.250"), 1);
}

func failDurationHuge() {
    durationToDays("99999999999999999999w");
}

func failDurationEmpty() {
    durationToDays("");
}

func failDurationWord() {
    durationToDays("soon");
}

func failDurationUnit() {
    durationToDays("10q");
}

func failDurationBareUnit() {
    durationToDays("w");
}

func testDurationToDaysRejectsJunkAsRouteros() {
    testing.assertThrows("failDurationHuge", "routeros");
    testing.assertThrows("failDurationEmpty", "routeros");
    testing.assertThrows("failDurationWord", "routeros");
    testing.assertThrows("failDurationUnit", "routeros");
    testing.assertThrows("failDurationBareUnit", "routeros");
}

func testExpiringFromKeepsExpired() {
    def certs as list of Certificate init [
        certificateFromRow({".id": "*1", "name": "gone", "expired": "true"}),
        certificateFromRow({".id": "*2", "name": "past", "expires-after": "-2d"}),
        certificateFromRow({".id": "*3", "name": "later", "expires-after": "51w"}),
        certificateFromRow({".id": "*4", "name": "junk", "expires-after": "soon"})
    ];
    def soon as list of Certificate init expiringFrom($certs, 30);
    testing.assertEqual(len($soon), 2);
    testing.assertEqual($soon[0].name, "gone");
    testing.assertEqual($soon[1].name, "past");
}

func testCertificateAuthorityFlag() {
    testing.assertTrue(certificateFromRow({"name": "ca", "authority": "true"}).isCa);
    testing.assertFalse(certificateFromRow({"name": "srv", "ca": "my-ca"}).isCa);
}

func failSelfSignedCommaCn() {
    generateSelfSigned(offlineClient(), "web", "a.lan,IP:0.0.0.0", 365);
}

func testSelfSignedRefusesCommaInCn() {
    testing.assertThrows("failSelfSignedCommaCn", "routeros");
}
