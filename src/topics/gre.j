# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - GRE tunnels: a routed point-to-point link over IP.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the GRE tunnel list. */
export def const GRE_PATH as string init "/interface/gre";

/**
 * One GRE tunnel: a routed (layer-3) point-to-point link over IP.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} tunnel interface name (e.g. "grebranch")
 * @field remoteAddress {string} the other router's IP address
 * @field localAddress {string} our source address, "" for automatic
 * @field mtu {string} MTU as reported
 * @field keepalive {string} keepalive setting as reported
 * @field running {bool} true when the tunnel is up
 * @field disabled {bool} true when the tunnel is switched off
 * @field comment {string} comment, "" when unset
 */
export def struct GreTunnel {
    id as string,
    name as string,
    remoteAddress as string,
    localAddress as string,
    mtu as string,
    keepalive as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * List the GRE tunnels.
 *
 * @param c {Client} an open client
 * @return {list of GreTunnel} all GRE tunnels
 */
export func greTunnels(c as Client) {
    def rows as list of map of string to string init getAll($c, GRE_PATH);
    def out as list of GreTunnel init [];
    for (def row in $rows) {
        $out[] = greFromRow($row);
    }
    return $out;
}

/**
 * Look up a GRE tunnel by name.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name
 * @return {GreTunnel} the tunnel
 * @throws {Error} kind "routeros" when no GRE tunnel has that name
 */
export func greTunnelByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, GRE_PATH, $name);
    if (len($row) == 0) {
        raiseError("the GRE tunnel \"" + $name + "\" was not found on the router");
    }
    return greFromRow($row);
}

/**
 * Create a GRE tunnel to another router.
 *
 * The far end needs the mirror tunnel, with our address as its remote.
 * Address each end in a small shared network (a /30 holds two) and
 * route through it, as in the example. GRE (RFC 2784) interoperates
 * with other vendors. It is not encrypted: across untrusted paths use
 * `addSecureGreTunnel` or WireGuard.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel interface name (e.g. "grebranch")
 * @param remoteAddress {string} the other router's IP address
 * @return {string} the RouterOS id of the new tunnel
 * @throws {Error} kind "routeros" on a bad name or address, a name
 *                 already taken, or an existing tunnel to that remote
 * @example
 *   mt.addGreTunnel($c, "grebranch", "203.0.113.99");
 *   mt.addIpAddress($c, "10.99.0.1/30", "grebranch");
 *   mt.addRoute($c, "192.168.20.0/24", "10.99.0.2", "branch LAN via GRE");
 *   # the far end mirrors it: remote = our address, 10.99.0.2/30, route back
 */
export func addGreTunnel(c as Client, name as string, remoteAddress as string) {
    return greAdd($c, $name, $remoteAddress, "");
}

/**
 * Create a GRE tunnel encrypted with RouterOS's coupled IPsec.
 *
 * With `ipsec-secret` set, RouterOS wraps the tunnel in IPsec transport
 * mode itself. The far end needs the same secret. Use a long random
 * secret: it is the only thing protecting the traffic.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel interface name
 * @param remoteAddress {string} the other router's IP address
 * @param ipsecSecret {string} shared IPsec secret (write-only)
 * @return {string} the RouterOS id of the new tunnel
 * @throws {Error} kind "routeros" on bad input or an empty secret
 */
export func addSecureGreTunnel(
    c as Client,
    name as string,
    remoteAddress as string,
    ipsecSecret as string) {
    if (strings.trim($ipsecSecret) == "") {
        raiseError("the IPsec secret must not be empty - it is the only thing protecting the tunnel");
    }
    return greAdd($c, $name, $remoteAddress, $ipsecSecret);
}

/**
 * Delete a GRE tunnel.
 *
 * Addresses on it go with it; routes through it become unreachable, so
 * remove those first.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name
 * @throws {Error} kind "routeros" when no GRE tunnel has that name
 */
export func removeGreTunnel(c as Client, name as string) {
    remove($c, GRE_PATH, requiredId($c, GRE_PATH, $name, "GRE tunnel"));
}

/**
 * Switch a GRE tunnel on.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name
 * @throws {Error} kind "routeros" when no GRE tunnel has that name
 */
export func enableGreTunnel(c as Client, name as string) {
    enable($c, GRE_PATH, requiredId($c, GRE_PATH, $name, "GRE tunnel"));
}

/**
 * Switch a GRE tunnel off; routes through it lose their link.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name
 * @throws {Error} kind "routeros" when no GRE tunnel has that name
 */
export func disableGreTunnel(c as Client, name as string) {
    disable($c, GRE_PATH, requiredId($c, GRE_PATH, $name, "GRE tunnel"));
}

/**
 * Validate and create a GRE tunnel; an empty secret omits the IPsec
 * coupling.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name
 * @param remoteAddress {string} the far end's IP address
 * @param secret {string} IPsec secret, "" for none
 * @return {string} the RouterOS id of the new tunnel
 * @throws {Error} kind "routeros" on bad input or a clashing tunnel
 * @internal
 */
func greAdd(c as Client, name as string, remoteAddress as string, secret as string) {
    ensureName($name, "GRE tunnel");
    def remote as string init strings.trim($remoteAddress);
    ensureIpAddress($remote);
    if (idByName($c, GRE_PATH, $name) != "") {
        raiseError("the GRE tunnel \"" + $name + "\" already exists");
    }
    def rows as list of map of string to string init getAll($c, GRE_PATH);
    def clash as map of string to string init findRowByField($rows, "remote-address", $remote);
    if (len($clash) > 0) {
        raiseError("a GRE tunnel to " + $remote + " already exists: \"" + rowValue($clash, "name") +
            "\"");
    }
    def attrs as map of string to string init {"name": $name, "remote-address": $remote};
    if ($secret != "") {
        $attrs["ipsec-secret"] = $secret;
    }
    return add($c, GRE_PATH, $attrs);
}

/**
 * Fold a reply row into a GreTunnel.
 *
 * @param row {map of string to string} an "/interface/gre/print" row
 * @return {GreTunnel} the typed tunnel
 * @internal
 */
func greFromRow(row as map of string to string) {
    return GreTunnel{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        remoteAddress: rowValue($row, "remote-address"),
        localAddress: rowValue($row, "local-address"),
        mtu: rowValue($row, "mtu"),
        keepalive: rowValue($row, "keepalive"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
