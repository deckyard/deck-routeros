# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - connection tracking: the live connection table.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the connection-tracking settings. */
export def const CONNTRACK_SETTINGS_PATH as string init "/ip/firewall/connection/tracking";

/** RouterOS API path of the live connection table. */
export def const CONNECTION_PATH as string init "/ip/firewall/connection";

/**
 * The connection-tracking settings and table fill.
 *
 * @field enabled {string} "auto", "yes" or "no", as reported
 * @field totalEntries {int} connections tracked now
 * @field maxEntries {int} table capacity; new connections are dropped
 *        when it is full
 */
export def struct ConntrackSettings {
    enabled as string,
    totalEntries as int,
    maxEntries as int
};

/**
 * One tracked connection.
 *
 * @field id {string} internal RouterOS id
 * @field protocol {string} protocol, e.g. "tcp" or "udp"
 * @field srcAddress {string} source address:port
 * @field dstAddress {string} destination address:port
 * @field tcpState {string} TCP state such as "established", "" for non-TCP
 * @field timeout {string} time until the entry expires
 * @field connectionMark {string} connection mark, "" when none
 */
export def struct Connection {
    id as string,
    protocol as string,
    srcAddress as string,
    dstAddress as string,
    tcpState as string,
    timeout as string,
    connectionMark as string
};

/**
 * Read the connection-tracking settings and how full the table is.
 *
 * @param c {Client} an open client
 * @return {ConntrackSettings} settings and current fill
 */
export func conntrackSettings(c as Client) {
    return conntrackFromRow(singleRow($c, CONNTRACK_SETTINGS_PATH));
}

# The connection properties `Connection` folds; reads ask for these only.
def const CONNECTION_PROPS as list of string init [
    ".id",
    "protocol",
    "src-address",
    "dst-address",
    "tcp-state",
    "timeout",
    "connection-mark"
];

/**
 * Read the live connection table.
 *
 * Thousands of rows on a busy router; only the properties `Connection`
 * holds travel. A table too large for one reply throws kind "limit";
 * `connectionsFor` filters to one host.
 *
 * @param c {Client} an open client
 * @return {list of Connection} every tracked connection
 */
export func connections(c as Client) {
    def rows as list of map of string to string init apiPrintSelect(
        $c,
        CONNECTION_PATH,
        CONNECTION_PROPS,
        []);
    def out as list of Connection init [];
    for (def row in $rows) {
        $out[] = connectionFromRow($row);
    }
    return $out;
}

/**
 * List the connections from or to one host.
 *
 * The host part of "address:port" must equal the address exactly, so
 * "10.0.0.1" does not match 10.0.0.10. IPv4 only: IPv6 connections are
 * tracked under "/ipv6/firewall/connection".
 *
 * @param c {Client} an open client
 * @param address {string} host IPv4 address to look for
 * @return {list of Connection} the matching connections
 * @throws {Error} kind "routeros" on a malformed or IPv6 address
 */
export func connectionsFor(c as Client, address as string) {
    def host as string init strings.trim($address);
    ensureIpv4Address($host, "connection host");
    def rows as list of map of string to string init apiPrintSelect(
        $c,
        CONNECTION_PATH,
        CONNECTION_PROPS,
        []);
    def out as list of Connection init [];
    for (def row in $rows) {
        if (connectionTouches($row, $host)) {
            $out[] = connectionFromRow($row);
        }
    }
    return $out;
}

/**
 * Remove the tracked connections from or to one host, forcing them to
 * re-establish.
 *
 * Cuts a device's flows without a firewall rule, or resets flows stuck
 * after a routing change. The host can open new connections at once.
 * Matches like `connectionsFor` (exact host); the connections go in
 * batches of up to 100 per command. A connection that expires between
 * the read and the remove fails its batch with kind "mikrotik".
 *
 * @param c {Client} an open client
 * @param address {string} host IPv4 address whose connections to drop
 * @return {int} number of connections removed
 * @throws {Error} kind "routeros" on a malformed or IPv6 address
 */
export func dropConnectionsFor(c as Client, address as string) {
    def host as string init strings.trim($address);
    ensureIpv4Address($host, "connection host");
    def rows as list of map of string to string init apiPrintSelect(
        $c,
        CONNECTION_PATH,
        [".id", "src-address", "dst-address"],
        []);
    def ids as list of string init [];
    for (def row in $rows) {
        if (connectionTouches($row, $host)) {
            $ids[] = rowValue($row, ".id");
        }
    }
    if (len($ids) == 0) {
        return 0;
    }
    return removeMany($c, CONNECTION_PATH, $ids);
}

/**
 * Whether a connection's source or destination host is `host`.
 *
 * @param row {map of string to string} a connection row
 * @param host {string} the IPv4 address
 * @return {bool} true when either end's host part equals it
 * @internal
 */
func connectionTouches(row as map of string to string, host as string) {
    return endpointHost(rowValue($row, "src-address")) == $host or
        endpointHost(rowValue($row, "dst-address")) == $host;
}

/**
 * The host part of an IPv4 connection endpoint ("10.0.0.1:443" or a
 * port-less "10.0.0.1").
 *
 * @param endpoint {string} the endpoint as reported
 * @return {string} the address without its port
 * @internal
 */
func endpointHost(endpoint as string) {
    def at as int init strings.lastIndexOf($endpoint, ":");
    if ($at < 0) {
        return $endpoint;
    }
    return $endpoint[..$at];
}

/**
 * Fold a reply row into the ConntrackSettings.
 *
 * @param row {map of string to string} the tracking-settings row
 * @return {ConntrackSettings} the typed settings
 * @internal
 */
func conntrackFromRow(row as map of string to string) {
    return ConntrackSettings{
        enabled: rowValue($row, "enabled"),
        totalEntries: rowInt($row, "total-entries"),
        maxEntries: rowInt($row, "max-entries")
    };
}

/**
 * Fold a reply row into a Connection.
 *
 * @param row {map of string to string} an "/ip/firewall/connection/print" row
 * @return {Connection} the typed connection
 * @internal
 */
func connectionFromRow(row as map of string to string) {
    return Connection{
        id: rowValue($row, ".id"),
        protocol: rowValue($row, "protocol"),
        srcAddress: rowValue($row, "src-address"),
        dstAddress: rowValue($row, "dst-address"),
        tcpState: rowValue($row, "tcp-state"),
        timeout: rowValue($row, "timeout"),
        connectionMark: rowValue($row, "connection-mark")
    };
}
