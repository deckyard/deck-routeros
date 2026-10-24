# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

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

/**
 * Read the live connection table.
 *
 * Thousands of rows on a busy router; `connectionsFor` filters to one
 * host. NAT'd connections appear in translated form.
 *
 * @param c {Client} an open client
 * @return {list of Connection} every tracked connection
 */
export func connections(c as Client) {
    def rows as list of map of string to string init getAll($c, CONNECTION_PATH);
    def out as list of Connection init [];
    for (def row in $rows) {
        $out[] = connectionFromRow($row);
    }
    return $out;
}

/**
 * List the connections whose source or destination contains an address.
 *
 * Warning: the match is a substring test on the "address:port" strings,
 * not an exact host match, so "10.0.0.1" also matches 10.0.0.10-19,
 * 10.0.0.100-199 and 110.0.0.1. Filter the result on `srcAddress` /
 * `dstAddress` when that matters.
 *
 * @param c {Client} an open client
 * @param address {string} host IP to look for
 * @return {list of Connection} the matching connections
 * @throws {Error} kind "routeros" on a malformed address
 */
export func connectionsFor(c as Client, address as string) {
    ensureIpAddress($address);
    def rows as list of map of string to string init getAll($c, CONNECTION_PATH);
    def out as list of Connection init [];
    for (def row in $rows) {
        if (strings.contains(rowValue($row, "src-address"), $address) or
            strings.contains(rowValue($row, "dst-address"), $address)) {
            $out[] = connectionFromRow($row);
        }
    }
    return $out;
}

/**
 * Remove the tracked connections whose source or destination contains an
 * address, forcing them to re-establish.
 *
 * Cuts a device's flows without a firewall rule, or resets flows stuck
 * after a routing change. The host can open new connections at once.
 *
 * Warning: the match is the same substring test as `connectionsFor`, so
 * "10.0.0.1" also drops the connections of 10.0.0.10-19, 10.0.0.100-199
 * and 110.0.0.1. For an exact match, filter `connections` yourself and
 * remove by id with the generic `remove`.
 *
 * @param c {Client} an open client
 * @param address {string} host IP whose connections to drop
 * @return {int} number of connections removed
 * @throws {Error} kind "routeros" on a malformed address
 */
export func dropConnectionsFor(c as Client, address as string) {
    ensureIpAddress($address);
    def rows as list of map of string to string init getAll($c, CONNECTION_PATH);
    def dropped as int init 0;
    for (def row in $rows) {
        if (strings.contains(rowValue($row, "src-address"), $address) or
            strings.contains(rowValue($row, "dst-address"), $address)) {
            remove($c, CONNECTION_PATH, rowValue($row, ".id"));
            $dropped = $dropped + 1;
        }
    }
    return $dropped;
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
