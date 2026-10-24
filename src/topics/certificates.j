# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - certificates: TLS for the router's own services.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the certificate store. */
export def const CERTIFICATE_PATH as string init "/certificate";

def const SSL_SERVICES as list of string init ["api-ssl", "www-ssl"];

/**
 * One certificate in the router's store.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          store name (the handle everything binds to)
 * @field commonName {string}    the subject CN (usually the DNS name)
 * @field issuer {string}        who signed it, "" for a template not yet signed
 * @field expiresAfter {string}  time until expiry as reported (e.g. "51w6d")
 * @field invalidAfter {string}  the absolute expiry date as reported
 * @field hasPrivateKey {bool} true when the router holds the key (usable for serving)
 * @field trusted {bool}       true when marked trusted
 * @field isCa {bool}          true for a CA certificate
 */
export def struct Certificate {
    id as string,
    name as string,
    commonName as string,
    issuer as string,
    expiresAfter as string,
    invalidAfter as string,
    hasPrivateKey as bool,
    trusted as bool,
    isCa as bool
};

/**
 * List every certificate in the store.
 *
 * @param c {Client} an open client
 * @return {list of Certificate} all certificates
 */
export func certificates(c as Client) {
    def rows as list of map of string to string init getAll($c, CERTIFICATE_PATH);
    def out as list of Certificate init [];
    for (def row in $rows) {
        $out[] = certificateFromRow($row);
    }
    return $out;
}

/**
 * Look one certificate up by its store name.
 *
 * @param c {Client}    an open client
 * @param name {string} the certificate's name
 * @return {Certificate} the certificate
 * @throws {Error} kind "routeros" when no certificate has that name
 */
export func certificateByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, CERTIFICATE_PATH, $name);
    if (len($row) == 0) {
        raiseError("the certificate \"" + $name + "\" was not found on the router");
    }
    return certificateFromRow($row);
}

/**
 * List the certificates that expire within a number of days.
 *
 * Certificates whose expiry is absent or does not parse are left out.
 *
 * @param c {Client}          an open client
 * @param withinDays {int} the horizon in days (e.g. 30)
 * @return {list of Certificate} certificates expiring within the horizon
 */
export func expiringCertificates(c as Client, withinDays as int) {
    return expiringFrom(certificates($c), $withinDays);
}

/**
 * Create and sign a self-signed certificate on the router.
 *
 * Suits LAN-only services (api-ssl, WebFig) whose clients trust it
 * manually. The router generates the key while signing, which blocks for
 * a few seconds. Key usage is digital-signature, key-encipherment,
 * tls-server.
 *
 * @param c {Client}          an open client
 * @param name {string}       store name for the certificate
 * @param commonName {string} the name it certifies (e.g. "router.lan")
 * @param days {int}       validity in days (e.g. 1095)
 * @return {string} the RouterOS id of the certificate
 * @throws {Error} kind "routeros" on a bad name, CN, days outside
 *                 1-7300, or a name already taken
 */
export func generateSelfSigned(c as Client, name as string, commonName as string, days as int) {
    ensureName($name, "certificate");
    if (strings.trim($commonName) == "") {
        raiseError("the common name must not be empty - use the name clients will connect to");
    }
    if ($days < 1 or $days > 7300) {
        raiseError("the validity must be between 1 and 7300 days");
    }
    if (idByName($c, CERTIFICATE_PATH, $name) != "") {
        raiseError("the certificate \"" + $name + "\" already exists");
    }
    def id as string init add(
        $c,
        CERTIFICATE_PATH,
        {
            "name": $name,
            "common-name": $commonName,
            "days-valid": convert.toString($days),
            "key-usage": "digital-signature,key-encipherment,tls-server"
        });
    apiTalk($c, CERTIFICATE_PATH + "/sign", {".id": $id});
    return $id;
}

/**
 * Obtain a Let's Encrypt certificate with RouterOS's built-in ACME client.
 *
 * Needs RouterOS v7 and port 80 reachable from the internet under
 * `dnsName`: the router solves the http-01 challenge and renews by itself.
 * Blocks until issued or failed. Behind NAT, use the Jennifer `acme`
 * module and `importCertificatePem` instead.
 *
 * @param c {Client}       an open client
 * @param dnsName {string} the public DNS name (e.g. from `routerDnsName`)
 * @throws {Error} kind "routeros" on an empty or spaced name,
 *                 kind "mikrotik" when the challenge fails (port 80
 *                 unreachable, wrong name)
 */
export func enableLetsEncrypt(c as Client, dnsName as string) {
    def target as string init strings.trim($dnsName);
    ensureHost($target);
    apiTalk($c, "/certificate/enable-ssl-certificate", {"dns-name": $target});
}

/**
 * Import a certificate and its private key from PEM text.
 *
 * For certificates obtained elsewhere (the Jennifer `acme` module, your
 * own CA). The PEMs are written to temporary files `<name>.crt` and
 * `<name>.key` on the router, imported under `name`, and the files are
 * removed so the key does not stay on flash.
 *
 * @param c {Client}       an open client
 * @param name {string}    store name for the certificate
 * @param certPem {string} the certificate (chain) as PEM text
 * @param keyPem {string}  the private key as PEM text
 * @throws {Error} kind "routeros" on a bad name, a certificate PEM without
 *                 "BEGIN CERTIFICATE" or a key PEM without "PRIVATE KEY"
 */
export func importCertificatePem(c as Client, name as string, certPem as string, keyPem as string) {
    ensureName($name, "certificate");
    ensurePemCertificate($certPem);
    ensurePemKey($keyPem);
    writeFileText($c, $name + ".crt", $certPem);
    writeFileText($c, $name + ".key", $keyPem);
    apiTalk(
        $c,
        CERTIFICATE_PATH + "/import",
        {"file-name": $name + ".crt", "passphrase": "", "name": $name});
    apiTalk(
        $c,
        CERTIFICATE_PATH + "/import",
        {"file-name": $name + ".key", "passphrase": "", "name": $name});
    removeFile($c, $name + ".crt");
    removeFile($c, $name + ".key");
}

/**
 * Bind a certificate to an SSL management service.
 *
 * Clears the `invalid` flag on api-ssl / www-ssl (see the services
 * topic).
 *
 * @param c {Client}           an open client
 * @param serviceName {string} "api-ssl" or "www-ssl"
 * @param certName {string}    the certificate's store name
 * @throws {Error} kind "routeros" on a non-SSL service or unknown certificate
 */
export func assignServiceCertificate(c as Client, serviceName as string, certName as string) {
    if (not lists.contains(SSL_SERVICES, $serviceName)) {
        raiseError("\"" + $serviceName + "\" takes no certificate - use one of: " +
            strings.join(SSL_SERVICES, ", "));
    }
    requiredId($c, CERTIFICATE_PATH, $certName, "certificate");
    set(
        $c,
        SERVICE_PATH,
        requiredId($c, SERVICE_PATH, $serviceName, "service"),
        {"certificate": $certName});
}

/**
 * Delete a certificate from the store.
 *
 * Services still referencing it fall back to none and go `invalid`.
 *
 * @param c {Client}    an open client
 * @param name {string} the certificate's store name
 * @throws {Error} kind "routeros" when no certificate has that name
 */
export func removeCertificate(c as Client, name as string) {
    remove($c, CERTIFICATE_PATH, requiredId($c, CERTIFICATE_PATH, $name, "certificate"));
}

/**
 * Convert a RouterOS duration ("51w6d", "4w2d13h", "90") to whole days.
 *
 * @param value {string} the duration as reported
 * @return {int} full days, or -1 when the value does not parse
 * @internal
 */
func durationToDays(value as string) {
    def v as string init strings.trim($value);
    if ($v == "") {
        return -1;
    }
    def digits as string init "";
    def total as int init 0;
    def chars as list of string init strings.chars($v);
    for (def ch in $chars) {
        if (strings.contains(DIGIT_CHARS, $ch)) {
            $digits = $digits + $ch;
        } elseif (strings.contains("wdhms", $ch)) {
            if ($digits == "") {
                return -1;
            }
            def n as int init convert.toInt($digits);
            $digits = "";
            match ($ch) {
                when "w" { $total = $total + $n * 604800; }
                when "d" { $total = $total + $n * 86400; }
                when "h" { $total = $total + $n * 3600; }
                when "m" { $total = $total + $n * 60; }
                else { $total = $total + $n; }
            }
        } else {
            return -1;
        }
    }
    if ($digits != "") {
        $total = $total + convert.toInt($digits);
    }
    return $total // 86400;
}

/**
 * Filter certificates down to those expiring within a horizon.
 *
 * Certificates with an unparseable or absent expiry are skipped.
 *
 * @param certs {list of Certificate} the candidates
 * @param withinDays {int} the horizon
 * @return {list of Certificate} the expiring ones, in order
 * @internal
 */
func expiringFrom(certs as list of Certificate, withinDays as int) {
    def out as list of Certificate init [];
    for (def cert in $certs) {
        if ($cert.expiresAfter != "") {
            def days as int init durationToDays($cert.expiresAfter);
            if ($days >= 0 and $days <= $withinDays) {
                $out[] = $cert;
            }
        }
    }
    return $out;
}

/**
 * Require PEM text to look like a certificate.
 *
 * @param pem {string} the candidate
 * @throws {Error} kind "routeros" when it does not
 * @internal
 */
func ensurePemCertificate(pem as string) {
    if (not strings.contains($pem, "BEGIN CERTIFICATE")) {
        raiseError("the certificate PEM contains no \"BEGIN CERTIFICATE\" block");
    }
}

/**
 * Require PEM text to look like a private key.
 *
 * @param pem {string} the candidate
 * @throws {Error} kind "routeros" when it does not
 * @internal
 */
func ensurePemKey(pem as string) {
    if (not strings.contains($pem, "PRIVATE KEY")) {
        raiseError("the key PEM contains no \"PRIVATE KEY\" block");
    }
}

/**
 * Fold a reply row into a Certificate.
 *
 * @param row {map of string to string} a "/certificate/print" row
 * @return {Certificate} the typed certificate
 * @internal
 */
func certificateFromRow(row as map of string to string) {
    return Certificate{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        commonName: rowValue($row, "common-name"),
        issuer: rowValue($row, "issuer"),
        expiresAfter: rowValue($row, "expires-after"),
        invalidAfter: rowValue($row, "invalid-after"),
        hasPrivateKey: rowBool($row, "private-key"),
        trusted: rowBool($row, "trusted"),
        isCa: rowBool($row, "ca")
    };
}
