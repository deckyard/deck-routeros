# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - diagnostics: ping, traceroute, bandwidth test, fetch, e-mail.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API command that sends ICMP echo requests. */
export def const PING_COMMAND as string init "/ping";

/** RouterOS API command that traces the path to a host. */
export def const TRACEROUTE_COMMAND as string init "/tool/traceroute";

/** RouterOS API command that downloads a URL from the router. */
export def const FETCH_COMMAND as string init "/tool/fetch";

/** RouterOS API path of the e-mail (SMTP) settings. */
export def const EMAIL_PATH as string init "/tool/e-mail";

/** E-mail transport security: none, plain SMTP. */
export def const EMAIL_TLS_NONE as string init "no";

/** E-mail transport security: STARTTLS on a plain session (port 587). */
export def const EMAIL_TLS_STARTTLS as string init "starttls";

/** E-mail transport security: implicit TLS from the first byte (port 465). */
export def const EMAIL_TLS_IMPLICIT as string init "yes";

/**
 * The router's outgoing e-mail (SMTP) settings. There is no password
 * field: RouterOS stores it write-only.
 *
 * @field server {string} SMTP server, DNS name or IP, "" when unset
 * @field port {int} SMTP port, 0 when unset
 * @field from {string} From: address
 * @field user {string} SMTP login, "" when the relay needs none
 * @field tls {string} one of the EMAIL_TLS_* values
 */
export def struct EmailSettings {
    server as string,
    port as int,
    from as string,
    user as string,
    tls as string
};

/** RouterOS API command that runs a throughput test against a btest server. */
export def const BANDWIDTH_TEST_COMMAND as string init "/tool/bandwidth-test";

def const BTEST_DIRECTIONS as list of string init ["receive", "transmit", "both"];

/**
 * The outcome of a ping from the router.
 *
 * @field host {string} host that answered, usually the target
 * @field sent {int} probes sent
 * @field received {int} replies received
 * @field packetLoss {int} loss in percent, 0 when every reply arrived
 * @field minRtt {string} fastest round trip as RouterOS prints it, e.g. "1ms52us"
 * @field avgRtt {string} average round trip as RouterOS prints it
 * @field maxRtt {string} slowest round trip as RouterOS prints it
 * @field reachable {bool} computed: whether at least one reply arrived
 */
export def struct PingResult {
    host as string,
    sent as int,
    received as int,
    packetLoss as int,
    minRtt as string,
    avgRtt as string,
    maxRtt as string,
    reachable as bool
};

/**
 * The outcome of a bandwidth test. Rates are bits per second, as strings
 * the way the router reports them.
 *
 * @field status {string} final tester status, "done testing" on success
 * @field direction {string} "receive", "transmit" or "both"
 * @field txCurrent {string} transmit rate at the end of the test
 * @field txAverage {string} average transmit rate over the test
 * @field rxCurrent {string} receive rate at the end of the test
 * @field rxAverage {string} average receive rate over the test
 * @field lostPackets {int} packets lost during the test
 */
export def struct BandwidthResult {
    status as string,
    direction as string,
    txCurrent as string,
    txAverage as string,
    rxCurrent as string,
    rxAverage as string,
    lostPackets as int
};

/**
 * Ping a host from the router with 4 probes.
 *
 * Answers whether the router, not your host, reaches the target.
 *
 * @param c {Client} an open client
 * @param host {string} IP address or DNS name
 * @return {PingResult} the summary; check `reachable` first
 * @throws {Error} kind "routeros" on an empty host or one with spaces,
 *         kind "mikrotik" when the router cannot try (e.g. bad DNS name)
 * @example
 *   def p as mt.PingResult init mt.ping($c, "1.1.1.1");
 *   if (not $p.reachable) { io.printf("uplink down!\n"); }
 */
export func ping(c as Client, host as string) {
    return pingWith($c, $host, 4);
}

/**
 * Ping a host from the router with a chosen probe count.
 *
 * The count is always sent, because an unbounded RouterOS ping never
 * returns.
 *
 * @param c {Client} an open client
 * @param host {string} IP address or DNS name
 * @param count {int} probes to send, 1-100
 * @return {PingResult} the summary
 * @throws {Error} kind "routeros" on an empty host or a count outside 1-100
 */
export func pingWith(c as Client, host as string, count as int) {
    def target as string init strings.trim($host);
    ensureHost($target);
    if ($count < 1 or $count > 100) {
        raiseError("the ping count must be between 1 and 100");
    }
    def rows as list of map of string to string init apiTalk(
        $c,
        PING_COMMAND,
        {"address": $target, "count": convert.toString($count)});
    return pingResultFromRow(mergeRows($rows));
}

/**
 * Test whether the router can reach a host.
 *
 * @param c {Client} an open client
 * @param host {string} IP address or DNS name
 * @return {bool} whether at least one of 4 ping probes came back
 * @throws {Error} kind "routeros" on an empty host
 */
export func isReachable(c as Client, host as string) {
    def result as PingResult init ping($c, $host);
    return $result.reachable;
}

/**
 * Measure throughput between the router and a btest server.
 *
 * The target must run a bandwidth-test server: another MikroTik
 * ("/tool/bandwidth-server") or MikroTik's btest tool. The test
 * saturates the link and loads both CPUs while it runs; do not run it
 * on a production uplink during business hours. For a server that
 * needs credentials use `bandwidthTestWith`.
 *
 * @param c {Client} an open client
 * @param host {string} btest server
 * @param seconds {int} test duration, 1-300
 * @param direction {string} "receive" (to the router), "transmit" (from
 *        it) or "both"
 * @return {BandwidthResult} the measured rates
 * @throws {Error} kind "routeros" on a bad host, duration or direction,
 *         kind "mikrotik" when the server is unreachable or refuses
 */
export func bandwidthTest(c as Client, host as string, seconds as int, direction as string) {
    return bandwidthRun($c, $host, $seconds, $direction, "", "");
}

/**
 * Run `bandwidthTest` with credentials for the btest server.
 *
 * @param c {Client} an open client
 * @param host {string} btest server
 * @param seconds {int} test duration, 1-300
 * @param direction {string} "receive", "transmit" or "both"
 * @param user {string} user name on the btest server, "" to omit
 * @param password {string} password on the btest server, "" to omit
 * @return {BandwidthResult} the measured rates
 * @throws {Error} kind "routeros" on a bad host, duration or direction,
 *         kind "mikrotik" when the server is unreachable or refuses the
 *         credentials
 */
export func bandwidthTestWith(
    c as Client,
    host as string,
    seconds as int,
    direction as string,
    user as string,
    password as string) {
    return bandwidthRun($c, $host, $seconds, $direction, $user, $password);
}

/**
 * Fold the merged ping rows into a PingResult; `reachable` means at
 * least one reply arrived.
 *
 * @param row {map of string to string} the merged ping progress rows
 * @return {PingResult} the typed summary
 * @internal
 */
func pingResultFromRow(row as map of string to string) {
    def received as int init rowInt($row, "received");
    return PingResult{
        host: rowValue($row, "host"),
        sent: rowInt($row, "sent"),
        received: $received,
        packetLoss: rowInt($row, "packet-loss"),
        minRtt: rowValue($row, "min-rtt"),
        avgRtt: rowValue($row, "avg-rtt"),
        maxRtt: rowValue($row, "max-rtt"),
        reachable: $received > 0
    };
}

/**
 * Validate inputs and run the bandwidth test.
 *
 * @param c {Client} an open client
 * @param host {string} btest server
 * @param seconds {int} duration, 1-300
 * @param direction {string} "receive", "transmit" or "both"
 * @param user {string} btest user, "" to omit
 * @param password {string} btest password, "" to omit
 * @return {BandwidthResult} the folded result
 * @throws {Error} kind "routeros" on bad input
 * @internal
 */
func bandwidthRun(
    c as Client,
    host as string,
    seconds as int,
    direction as string,
    user as string,
    password as string) {
    def target as string init strings.trim($host);
    ensureHost($target);
    ensureBandwidthParams($seconds, $direction);
    def attrs as map of string to string init {
        "address": $target,
        "duration": convert.toString($seconds),
        "direction": $direction
    };
    if ($user != "") {
        $attrs["user"] = $user;
    }
    if ($password != "") {
        $attrs["password"] = $password;
    }
    def rows as list of map of string to string init apiTalk($c, BANDWIDTH_TEST_COMMAND, $attrs);
    return bandwidthResultFromRow(mergeRows($rows));
}

/**
 * Validate bandwidth-test duration and direction.
 *
 * @param seconds {int} duration, 1-300
 * @param direction {string} "receive", "transmit" or "both"
 * @throws {Error} kind "routeros" when either is out of range
 * @internal
 */
func ensureBandwidthParams(seconds as int, direction as string) {
    if ($seconds < 1 or $seconds > 300) {
        raiseError("the test duration must be between 1 and 300 seconds");
    }
    if (not lists.contains(BTEST_DIRECTIONS, $direction)) {
        raiseError("unknown direction \"" + $direction + "\" - use one of: " +
            strings.join(BTEST_DIRECTIONS, ", "));
    }
}

/**
 * Fold the merged bandwidth-test rows into a BandwidthResult.
 *
 * @param row {map of string to string} the merged progress rows
 * @return {BandwidthResult} the typed result
 * @internal
 */
func bandwidthResultFromRow(row as map of string to string) {
    return BandwidthResult{
        status: rowValue($row, "status"),
        direction: rowValue($row, "direction"),
        txCurrent: rowValue($row, "tx-current"),
        txAverage: rowValue($row, "tx-total-average"),
        rxCurrent: rowValue($row, "rx-current"),
        rxAverage: rowValue($row, "rx-total-average"),
        lostPackets: rowInt($row, "lost-packets")
    };
}

/**
 * One hop on a traceroute path.
 *
 * @field address {string} hop address, "" when it did not answer
 * @field loss {string} packet loss at this hop, as RouterOS prints it
 * @field avgRtt {string} average round trip to this hop, "" when no reply
 * @field status {string} hop status, as RouterOS prints it
 */
export def struct TracerouteHop {
    address as string,
    loss as string,
    avgRtt as string,
    status as string
};

/**
 * The outcome of a router-side fetch.
 *
 * @field status {string} "finished" on success, else the failure text
 * @field ok {bool} computed: whether status is "finished"
 * @field downloaded {string} amount downloaded, as RouterOS prints it
 * @field data {string} response body; only `fetchUrl` fills it
 */
export def struct FetchResult {
    status as string,
    ok as bool,
    downloaded as string,
    data as string
};

/**
 * Trace the path from the router to a host, one probe per hop.
 *
 * @param c {Client} an open client
 * @param host {string} IP address or DNS name
 * @return {list of TracerouteHop} the hops in order
 * @throws {Error} kind "routeros" on an empty host or one with spaces
 * @example
 *   def hops as list of mt.TracerouteHop init mt.traceroute($c, "1.1.1.1");
 *   for (def h in $hops) { io.printf("%s %s (loss %s)\n", $h.address, $h.avgRtt, $h.loss); }
 */
export func traceroute(c as Client, host as string) {
    def target as string init strings.trim($host);
    ensureHost($target);
    def rows as list of map of string to string init apiTalk(
        $c,
        TRACEROUTE_COMMAND,
        {"address": $target, "count": "1"});
    def out as list of TracerouteHop init [];
    for (def row in $rows) {
        $out[] = tracerouteHopFromRow($row);
    }
    return $out;
}

/**
 * Fetch a URL from the router and return the body in `data`.
 *
 * The router makes the request, from its own network position: a
 * webhook, a REST call, a "what is my IP" service. For a large download
 * to storage use `downloadFile`.
 *
 * @param c {Client} an open client
 * @param url {string} URL starting with "http"
 * @return {FetchResult} status and the response body
 * @throws {Error} kind "routeros" when the URL does not start with "http",
 *         kind "mikrotik" when the fetch fails
 * @example
 *   def r as mt.FetchResult init mt.fetchUrl($c, "https://ifconfig.co/ip");
 *   if ($r.ok) { io.printf("public IP: %s\n", $r.data); }
 */
export func fetchUrl(c as Client, url as string) {
    def target as string init strings.trim($url);
    if ($target == "" or not strings.startsWith($target, "http")) {
        raiseError("the fetch URL must be an http(s) URL");
    }
    def rows as list of map of string to string init apiTalk(
        $c,
        FETCH_COMMAND,
        {"url": $target, "output": "user", "mode": "https"});
    return fetchResultFromRow(mergeRows($rows));
}

/**
 * Download a URL to a file on the router's storage.
 *
 * @param c {Client} an open client
 * @param url {string} URL starting with "http"
 * @param fileName {string} destination file name on the router, no spaces
 * @return {FetchResult} status and amount downloaded
 * @throws {Error} kind "routeros" on a bad URL or file name, kind
 *         "mikrotik" when the download fails
 */
export func downloadFile(c as Client, url as string, fileName as string) {
    def target as string init strings.trim($url);
    if ($target == "" or not strings.startsWith($target, "http")) {
        raiseError("the download URL must be an http(s) URL");
    }
    ensureName($fileName, "file");
    def rows as list of map of string to string init apiTalk(
        $c,
        FETCH_COMMAND,
        {"url": $target, "dst-path": $fileName, "mode": "https"});
    return fetchResultFromRow(mergeRows($rows));
}

/**
 * Configure the router's outgoing e-mail (SMTP) settings, leaving the
 * TLS mode as it is.
 *
 * Afterwards `sendEmail` and RouterOS scripts can send mail. Same as
 * `configureEmailWith` with tls "".
 *
 * @param c {Client} an open client
 * @param server {string} SMTP server, DNS name or IP
 * @param port {int} SMTP port, e.g. 587
 * @param from {string} From: address
 * @param user {string} SMTP login, "" for an open relay
 * @param password {string} SMTP password, "" when no auth; write-only
 * @throws {Error} kind "routeros" on a bad server or port
 */
export func configureEmail(
    c as Client,
    server as string,
    port as int,
    from as string,
    user as string,
    password as string) {
    configureEmailWith($c, $server, $port, $from, $user, $password, "");
}

/**
 * Configure outgoing e-mail with a transport security mode.
 *
 * Most relays (Gmail, Office 365) want `EMAIL_TLS_STARTTLS` on port 587;
 * `EMAIL_TLS_IMPLICIT` is port 465, `EMAIL_TLS_NONE` plain SMTP for an
 * internal relay. The password is stored write-only; `emailSettings`
 * never returns it. An empty `user` or `password` is not sent, so the
 * router keeps its current value.
 *
 * RouterOS 7.12 renamed `address` to `server` and `start-tls` to `tls`.
 * This reads the settings row first and writes whichever spelling the
 * router uses; before 7.12, `EMAIL_TLS_STARTTLS` is written as
 * `start-tls=yes` and `EMAIL_TLS_IMPLICIT` as `start-tls=tls-only`.
 *
 * @param c {Client} an open client
 * @param server {string} SMTP server, DNS name or IP
 * @param port {int} SMTP port: 587 STARTTLS, 465 implicit, 25 plain
 * @param from {string} From: address
 * @param user {string} SMTP login, "" for an open relay
 * @param password {string} SMTP password, "" when no auth
 * @param tls {string} an EMAIL_TLS_* constant, or "" to leave it unchanged
 * @throws {Error} kind "routeros" on an empty or spaced server, a bad
 *         port, or an unknown tls mode
 * @example
 *   mt.configureEmailWith($c, "smtp.example.org", 587,
 *       "[MikroTik gw1] <router@example.org>", "router", "secret",
 *       mt.EMAIL_TLS_STARTTLS);
 */
export func configureEmailWith(
    c as Client,
    server as string,
    port as int,
    from as string,
    user as string,
    password as string,
    tls as string) {
    def host as string init strings.trim($server);
    ensureHost($host);
    ensurePort($port);
    def mode as string init strings.trim($tls);
    if ($mode != "") {
        ensureEmailTls($mode);
    }
    def names as map of string to string init emailPropertyNames($c);
    def attrs as map of string to string init {"port": convert.toString($port), "from": $from};
    $attrs[$names["server"]] = $host;
    if ($user != "") {
        $attrs["user"] = $user;
    }
    if ($password != "") {
        $attrs["password"] = $password;
    }
    if ($mode != "") {
        $attrs[$names["tls"]] = emailTlsWord($mode, $names["tls"]);
    }
    apiRun($c, EMAIL_PATH + "/set", $attrs);
}

/**
 * Read the router's outgoing e-mail settings, from either the 7.12+ or
 * the older property names. The password is never returned.
 *
 * @param c {Client} an open client
 * @return {EmailSettings} the current settings
 * @example
 *   def s as mt.EmailSettings init mt.emailSettings($c);
 *   if ($s.tls == mt.EMAIL_TLS_NONE) { io.printf("alerts go out in the clear\n"); }
 */
export func emailSettings(c as Client) {
    def row as map of string to string init singleRow($c, EMAIL_PATH);
    def server as string init rowValue($row, "server");
    if ($server == "") {
        $server = rowValue($row, "address");
    }
    def tls as string init rowValue($row, "tls");
    if ($tls == "") {
        $tls = modernTlsWord(rowValue($row, "start-tls"));
    }
    return EmailSettings{
        server: $server,
        port: rowInt($row, "port"),
        from: rowValue($row, "from"),
        user: rowValue($row, "user"),
        tls: $tls
    };
}

/**
 * Send an e-mail from the router.
 *
 * Needs `configureEmail` first.
 *
 * @param c {Client} an open client
 * @param recipient {string} recipient address
 * @param subject {string} subject line
 * @param body {string} message body
 * @throws {Error} kind "routeros" on an empty recipient, kind "mikrotik"
 *         when the SMTP send fails
 * @example
 *   mt.configureEmail($c, "10.0.9.25", 587, "router@example.org", "router", "secret");
 *   mt.sendEmail($c, "noc@example.org", "router booted", "the office router just started");
 */
export func sendEmail(c as Client, recipient as string, subject as string, body as string) {
    def target as string init strings.trim($recipient);
    if ($target == "") {
        raiseError("the recipient must not be empty");
    }
    apiRun($c, EMAIL_PATH + "/send", {"to": $target, "subject": $subject, "body": $body});
}

/**
 * Fold a reply row into a TracerouteHop.
 *
 * @param row {map of string to string} a traceroute reply row
 * @return {TracerouteHop} the typed hop
 * @internal
 */
func tracerouteHopFromRow(row as map of string to string) {
    return TracerouteHop{
        address: rowValue($row, "address"),
        loss: rowValue($row, "loss"),
        avgRtt: rowValue($row, "avg"),
        status: rowValue($row, "status")
    };
}

/**
 * Fold the merged fetch rows into a FetchResult; `ok` means the status
 * is "finished".
 *
 * @param row {map of string to string} the merged fetch progress rows
 * @return {FetchResult} the typed result
 * @internal
 */
func fetchResultFromRow(row as map of string to string) {
    def status as string init rowValue($row, "status");
    return FetchResult{
        status: $status,
        ok: $status == "finished",
        downloaded: rowValue($row, "downloaded"),
        data: rowValue($row, "data")
    };
}

/**
 * Decide which spelling of the e-mail properties this router uses.
 *
 * RouterOS 7.12 renamed `address` to `server` and `start-tls` to `tls`.
 * A settings row with `address` and no `server` is pre-7.12; an empty
 * row gets the modern names.
 *
 * @param c {Client} an open client
 * @return {map of string to string} keys "server" and "tls" mapped to the
 *         property names to write
 * @internal
 */
func emailPropertyNames(c as Client) {
    def modern as map of string to string init {"server": "server", "tls": "tls"};
    def legacy as map of string to string init {"server": "address", "tls": "start-tls"};
    def row as map of string to string init singleRow($c, EMAIL_PATH);
    if (maps.has($row, "address") and not maps.has($row, "server")) {
        return $legacy;
    }
    return $modern;
}

/**
 * Validate an e-mail TLS mode against the EMAIL_TLS_* constants.
 *
 * @param mode {string} the candidate mode
 * @throws {Error} kind "routeros" on an unknown mode
 * @internal
 */
func ensureEmailTls(mode as string) {
    if ($mode != EMAIL_TLS_NONE and $mode != EMAIL_TLS_STARTTLS and $mode != EMAIL_TLS_IMPLICIT) {
        raiseError("\"" + $mode +
            "\" is not a TLS mode - use EMAIL_TLS_NONE, EMAIL_TLS_STARTTLS, or EMAIL_TLS_IMPLICIT");
    }
}

/**
 * Render a TLS mode for the property name the router actually takes.
 *
 * Modern routers take the mode verbatim. Pre-7.12 `start-tls` spells the
 * same three states `no` / `yes` (STARTTLS) / `tls-only` (implicit).
 *
 * @param mode {string} an EMAIL_TLS_* value
 * @param property {string} property name chosen by `emailPropertyNames`
 * @return {string} the value to send
 * @internal
 */
func emailTlsWord(mode as string, property as string) {
    if ($property != "start-tls") {
        return $mode;
    }
    if ($mode == EMAIL_TLS_STARTTLS) {
        return "yes";
    }
    if ($mode == EMAIL_TLS_IMPLICIT) {
        return "tls-only";
    }
    return "no";
}

/**
 * Fold a legacy `start-tls` reading back into an EMAIL_TLS_* value.
 *
 * @param word {string} the `start-tls` property value ("" when absent)
 * @return {string} the matching EMAIL_TLS_* value
 * @internal
 */
func modernTlsWord(word as string) {
    if ($word == "yes") {
        return EMAIL_TLS_STARTTLS;
    }
    if ($word == "tls-only") {
        return EMAIL_TLS_IMPLICIT;
    }
    return EMAIL_TLS_NONE;
}
