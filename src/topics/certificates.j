# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

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
 * @field isCa {bool}          true for a CA certificate (the `authority` flag)
 * @field expired {bool}       true when the router flags it expired
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
    isCa as bool,
    expired as bool
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
 * Already expired certificates are included (flagged `expired`, or with a
 * negative time left). Certificates whose expiry is absent or does not
 * parse are left out.
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
 * manually (`connectTLSWithCA` with the certificate's PEM). The router
 * generates the key while signing, which blocks for a few seconds. Key
 * usage is digital-signature, key-encipherment, tls-server. `commonName`
 * also goes into the subject alternative name (`IP:` for an address,
 * `DNS:` otherwise), which TLS clients match against the dialled host;
 * they ignore the common name.
 *
 * @param c {Client}          an open client
 * @param name {string}       store name for the certificate
 * @param commonName {string} the name or IP address clients dial (e.g.
 *        "router.lan", "192.168.88.1")
 * @param days {int}       validity in days (e.g. 1095)
 * @return {string} the RouterOS id of the certificate
 * @throws {Error} kind "routeros" on a bad name, a CN that is empty or
 *                 holds a space or comma, days outside 1-7300, or a name
 *                 already taken
 */
export func generateSelfSigned(c as Client, name as string, commonName as string, days as int) {
    ensureName($name, "certificate");
    if (strings.trim($commonName) == "") {
        raiseError("the common name must not be empty - use the name clients will connect to");
    }
    ensureName(strings.trim($commonName), "common");
    if (strings.contains($commonName, ",")) {
        raiseError("the common name must not contain \",\" - it would add another subject alternative name");
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
            "subject-alt-name": subjectAltNameFor($commonName),
            "days-valid": convert.toString($days),
            "key-usage": "digital-signature,key-encipherment,tls-server"
        });
    apiTalk($c, CERTIFICATE_PATH + "/sign", {".id": $id});
    return $id;
}

/**
 * The RouterOS `subject-alt-name` value for a certificate's common name.
 *
 * @param commonName {string} a DNS name or an IP address
 * @return {string} "IP:<address>" for an address, "DNS:<name>" otherwise
 * @internal
 */
func subjectAltNameFor(commonName as string) {
    def name as string init strings.trim($commonName);
    try {
        ipnet.parseAddress($name);
        return "IP:" + $name;
    } catch (e) {
        return "DNS:" + $name;
    }
    return "DNS:" + $name;
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
 * removed so the key does not stay on flash, also when a write or the
 * import fails (the failure is then rethrown).
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
    def files as list of string init [$name + ".crt", $name + ".key"];
    try {
        writeFileText($c, $files[0], $certPem);
        writeFileText($c, $files[1], $keyPem);
        for (def file in $files) {
            apiTalk(
                $c,
                CERTIFICATE_PATH + "/import",
                {"file-name": $file, "passphrase": "", "name": $name});
        }
    } catch (e) {
        discardFiles($c, $files);
        throw $e;
    }
    for (def file in $files) {
        removeFile($c, $file);
    }
}

/**
 * Remove files that may or may not exist, on a path that is already
 * failing.
 *
 * Used to take a private key back off the router after a failed import.
 * A failure here is not reported: the caller rethrows the error that
 * caused the cleanup, which says more.
 *
 * @param c {Client} an open client
 * @param names {list of string} the file names
 * @internal
 */
func discardFiles(c as Client, names as list of string) {
    for (def name in $names) {
        try {
            removeFileIfPresent($c, $name);
        } catch (e) { # lint-disable: L103
            # Deliberate: the import's own error is the one rethrown.
        }
    }
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

# Longest digit run a duration token may have: keeps every product and
# sum far inside int64.
def const DURATION_MAX_DIGITS as int init 9;

/**
 * Convert a RouterOS duration to whole days, rounded towards minus
 * infinity.
 *
 * Accepts unit tokens ("51w6d", "4w2d13h", "1d2h3m4s", "500ms"), a
 * trailing clock part ("8w2d03:32:06", "00:00:05.5"), bare seconds ("90")
 * and a leading "-" for a time already past ("-3d" is -3).
 *
 * @param value {string} the duration as reported
 * @return {int} days
 * @throws {Error} kind "routeros" when the value does not parse
 * @internal
 */
func durationToDays(value as string) {
    def seconds as int init durationSeconds($value);
    return $seconds // 86400;
}

/**
 * Convert a RouterOS duration to whole seconds (fractions dropped).
 *
 * @param value {string} the duration as reported
 * @return {int} seconds, negative for a leading "-"
 * @throws {Error} kind "routeros" when the value does not parse
 * @internal
 */
func durationSeconds(value as string) {
    def v as string init strings.trim($value);
    def sign as int init 1;
    if (strings.startsWith($v, "-")) {
        $sign = -1;
        $v = $v[1..];
    }
    if ($v == "") {
        badDuration($value);
    }
    def clock as string init "";
    def colon as int init strings.indexOf($v, ":");
    if ($colon >= 0) {
        # The clock part starts at the digits before the first colon.
        def start as int init $colon;
        while ($start > 0 and strings.contains(DIGIT_CHARS, $v[$start - 1..$start])) {
            $start = $start - 1;
        }
        $clock = $v[$start..];
        $v = $v[..$start];
    }
    def total as int init 0;
    def digits as string init "";
    def chars as list of string init strings.chars($v);
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if (strings.contains(DIGIT_CHARS, $ch)) {
            $digits = $digits + $ch;
            if (len($digits) > DURATION_MAX_DIGITS) {
                badDuration($value);
            }
        } else {
            if ($digits == "") {
                badDuration($value);
            }
            def n as int init convert.toInt($digits);
            $digits = "";
            def unit as string init $ch;
            if ($i + 1 < len($chars) and $chars[$i + 1] == "s" and
                ($ch == "m" or $ch == "u" or $ch == "n")) {
                $unit = $ch + "s";
                $i = $i + 1;
            }
            match ($unit) {
                when "w" { $total = $total + $n * 604800; }
                when "d" { $total = $total + $n * 86400; }
                when "h" { $total = $total + $n * 3600; }
                when "m" { $total = $total + $n * 60; }
                when "s" { $total = $total + $n; }
                when "ms" { $total = $total + $n // 1000; }
                when "us" { $total = $total + $n // 1000000; }
                when "ns" {
                }
                else { badDuration($value); }
            }
        }
        $i = $i + 1;
    }
    if ($digits != "") {
        if ($clock != "") {
            badDuration($value);
        }
        $total = $total + convert.toInt($digits);
    }
    if ($clock != "") {
        $total = $total + clockSeconds($value, $clock);
    }
    return $sign * $total;
}

/**
 * Convert the "HH:MM:SS[.fff]" part of a duration to seconds.
 *
 * @param value {string} the whole duration, for the error message
 * @param clock {string} the clock part
 * @return {int} seconds (fractions dropped)
 * @throws {Error} kind "routeros" on any other shape
 * @internal
 */
func clockSeconds(value as string, clock as string) {
    def parts as list of string init strings.split($clock, ":");
    if (len($parts) != 3) {
        badDuration($value);
    }
    def sec as string init $parts[2];
    def dot as int init strings.indexOf($sec, ".");
    if ($dot >= 0) {
        def frac as string init $sec[$dot + 1..];
        if (not allDigits($frac)) {
            badDuration($value);
        }
        $sec = $sec[..$dot];
    }
    def total as int init 0;
    def weights as list of int init [3600, 60, 1];
    for (def k in 0..3) {
        def part as string init $parts[$k];
        if ($k == 2) {
            $part = $sec;
        }
        if (not allDigits($part) or len($part) > DURATION_MAX_DIGITS) {
            badDuration($value);
        }
        $total = $total + convert.toInt($part) * $weights[$k];
    }
    return $total;
}

/**
 * Whether a string is one or more ASCII digits.
 *
 * @param value {string} the candidate
 * @return {bool} true for a non-empty digit run
 * @internal
 */
func allDigits(value as string) {
    if ($value == "") {
        return false;
    }
    for (def ch in strings.chars($value)) {
        if (not strings.contains(DIGIT_CHARS, $ch)) {
            return false;
        }
    }
    return true;
}

/**
 * Reject a duration that does not parse.
 *
 * @param value {string} the offending value
 * @throws {Error} always, kind "routeros"
 * @internal
 */
func badDuration(value as string) {
    raiseError("\"" + $value + "\" is not a RouterOS duration");
}

/**
 * Filter certificates down to those expiring within a horizon.
 *
 * Expired certificates are kept (flag or negative time left);
 * certificates with an absent or unparseable expiry are skipped.
 *
 * @param certs {list of Certificate} the candidates
 * @param withinDays {int} the horizon
 * @return {list of Certificate} the expiring ones, in order
 * @internal
 */
func expiringFrom(certs as list of Certificate, withinDays as int) {
    def out as list of Certificate init [];
    for (def cert in $certs) {
        if ($cert.expired or expiresWithin($cert.expiresAfter, $withinDays)) {
            $out[] = $cert;
        }
    }
    return $out;
}

/**
 * Whether a reported time left is at most a number of days.
 *
 * @param expiresAfter {string} the duration as reported, "" when absent
 * @param withinDays {int}      the horizon
 * @return {bool} true when it parses and is within the horizon; false for
 *         an absent or unparseable value
 * @internal
 */
func expiresWithin(expiresAfter as string, withinDays as int) {
    if ($expiresAfter == "") {
        return false;
    }
    try {
        return durationToDays($expiresAfter) <= $withinDays;
    } catch (e) {
        if ($e.kind != "routeros") {
            throw $e;
        }
    }
    return false;
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
        isCa: rowBool($row, "authority") or rowBool($row, "ca"),
        expired: rowBool($row, "expired")
    };
}
