# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - EoIP tunnels: a layer-2 wire between two MikroTiks.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the EoIP tunnel list. */
export def const EOIP_PATH as string init "/interface/eoip";

/**
 * One EoIP tunnel: an ethernet link carried over any IP path.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          tunnel interface name (e.g. "eoipbranch")
 * @field remoteAddress {string} other MikroTik's IP address
 * @field localAddress {string}  source address, "" for automatic
 * @field tunnelId {int}      tunnel id, the same on both ends
 * @field mac {string}           tunnel MAC address
 * @field mtu {string}           MTU as reported
 * @field keepalive {string}     keepalive setting as reported
 * @field running {bool}       true when the tunnel is up
 * @field disabled {bool}      true when the tunnel is switched off
 * @field comment {string}       free-text comment, "" when unset
 */
export def struct EoipTunnel {
    id as string,
    name as string,
    remoteAddress as string,
    localAddress as string,
    tunnelId as int,
    mac as string,
    mtu as string,
    keepalive as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * List every EoIP tunnel on the router.
 *
 * @param c {Client} an open client
 * @return {list of EoipTunnel} all EoIP tunnels
 */
export func eoipTunnels(c as Client) {
    def rows as list of map of string to string init getAll($c, EOIP_PATH);
    def out as list of EoipTunnel init [];
    for (def row in $rows) {
        $out[] = eoipFromRow($row);
    }
    return $out;
}

/**
 * Look up an EoIP tunnel by name.
 *
 * @param c {Client}    an open client
 * @param name {string} tunnel name
 * @return {EoipTunnel} the tunnel
 * @throws {Error} kind "routeros" when no EoIP tunnel has that name
 */
export func eoipTunnelByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, EOIP_PATH, $name);
    if (len($row) == 0) {
        raiseError("the EoIP tunnel \"" + $name + "\" was not found on the router");
    }
    return eoipFromRow($row);
}

/**
 * Create an EoIP tunnel to another MikroTik.
 *
 * EoIP carries ethernet frames over IP: bridge the tunnel on both ends
 * and the two sites share one broadcast domain. The other end needs the
 * mirror tunnel, with this router as its remote and the same tunnel id.
 *
 * EoIP is not encrypted; anyone on the path can read the frames. Across
 * the internet use `addSecureEoipTunnel`, or run the tunnel over
 * WireGuard with the peer's VPN address as remote.
 *
 * @param c {Client}             an open client
 * @param name {string}          tunnel interface name (e.g. "eoipbranch")
 * @param remoteAddress {string} other router's IP address
 * @param tunnelId {int}      shared id, 0-65535, equal on both ends
 * @return {string} the RouterOS id of the new tunnel
 * @throws {Error} kind "routeros" on an empty or spaced name, a remote that
 *                 is not an IP address, an id outside 0-65535, a taken
 *                 name, or an existing tunnel with the same remote and id
 * @example
 *   # site A (10.100.0.1 via WireGuard):
 *   mt.addEoipTunnel($c, "eoipbranch", "10.100.0.2", 7);
 *   mt.addBridgePort($c, "brlan", "eoipbranch");
 *   # site B mirrors it with remote 10.100.0.1 and the same id 7
 */
export func addEoipTunnel(c as Client, name as string, remoteAddress as string, tunnelId as int) {
    return eoipAdd($c, $name, $remoteAddress, $tunnelId, "");
}

/**
 * Create an EoIP tunnel encrypted with RouterOS's coupled IPsec.
 *
 * With a secret set, RouterOS wraps the tunnel in IPsec transport mode
 * itself; the other end needs the same secret. Use a long random secret:
 * it is the only protection of the traffic.
 *
 * @param c {Client}             an open client
 * @param name {string}          tunnel interface name
 * @param remoteAddress {string} other router's IP address
 * @param tunnelId {int}      shared id, 0-65535, equal on both ends
 * @param ipsecSecret {string}   shared IPsec secret; never read back
 * @return {string} the RouterOS id of the new tunnel
 * @throws {Error} kind "routeros" on an empty secret, or the
 *                 `addEoipTunnel` errors
 */
export func addSecureEoipTunnel(
    c as Client,
    name as string,
    remoteAddress as string,
    tunnelId as int,
    ipsecSecret as string) {
    if (strings.trim($ipsecSecret) == "") {
        raiseError("the IPsec secret must not be empty - it is the only thing protecting the tunnel");
    }
    return eoipAdd($c, $name, $remoteAddress, $tunnelId, $ipsecSecret);
}

/**
 * Delete an EoIP tunnel.
 *
 * A bridge port on the tunnel loses its interface; detach it first for a
 * clean teardown.
 *
 * @param c {Client}    an open client
 * @param name {string} tunnel name
 * @throws {Error} kind "routeros" when no EoIP tunnel has that name
 */
export func removeEoipTunnel(c as Client, name as string) {
    remove($c, EOIP_PATH, requiredId($c, EOIP_PATH, $name, "EoIP tunnel"));
}

/**
 * Switch an EoIP tunnel on.
 *
 * @param c {Client}    an open client
 * @param name {string} tunnel name
 * @throws {Error} kind "routeros" when no EoIP tunnel has that name
 */
export func enableEoipTunnel(c as Client, name as string) {
    enable($c, EOIP_PATH, requiredId($c, EOIP_PATH, $name, "EoIP tunnel"));
}

/**
 * Switch an EoIP tunnel off; the layer-2 link between the sites drops.
 *
 * @param c {Client}    an open client
 * @param name {string} tunnel name
 * @throws {Error} kind "routeros" when no EoIP tunnel has that name
 */
export func disableEoipTunnel(c as Client, name as string) {
    disable($c, EOIP_PATH, requiredId($c, EOIP_PATH, $name, "EoIP tunnel"));
}

/**
 * Validate and create an EoIP tunnel; an empty secret omits IPsec.
 *
 * @param c {Client}             an open client
 * @param name {string}          tunnel name
 * @param remoteAddress {string} the far end
 * @param tunnelId {int}      shared id
 * @param secret {string}        IPsec secret, "" for none
 * @return {string} the RouterOS id of the new tunnel
 * @throws {Error} kind "routeros" on bad input or a clashing tunnel
 * @internal
 */
func eoipAdd(
    c as Client,
    name as string,
    remoteAddress as string,
    tunnelId as int,
    secret as string) {
    ensureName($name, "EoIP tunnel");
    def remote as string init strings.trim($remoteAddress);
    ensureIpAddress($remote);
    ensureTunnelId($tunnelId);
    if (idByName($c, EOIP_PATH, $name) != "") {
        raiseError("the EoIP tunnel \"" + $name + "\" already exists");
    }
    def rows as list of map of string to string init getAll($c, EOIP_PATH);
    def clash as map of string to string init findEoipRow($rows, $remote, $tunnelId);
    if (len($clash) > 0) {
        raiseError("tunnel id " + convert.toString($tunnelId) + " to " + $remote +
            " is already used by \"" + rowValue($clash, "name") + "\"");
    }
    def attrs as map of string to string init {
        "name": $name,
        "remote-address": $remote,
        "tunnel-id": convert.toString($tunnelId)
    };
    if ($secret != "") {
        $attrs["ipsec-secret"] = $secret;
    }
    return add($c, EOIP_PATH, $attrs);
}

/**
 * Validate an EoIP tunnel id.
 *
 * @param tunnelId {int} the candidate id
 * @throws {Error} kind "routeros" when outside 0-65535
 * @internal
 */
func ensureTunnelId(tunnelId as int) {
    if ($tunnelId < 0 or $tunnelId > 65535) {
        raiseError("the tunnel id must be between 0 and 65535 (and match the other end)");
    }
}

/**
 * Find an existing tunnel to a remote with a tunnel id.
 *
 * @param rows {list of map of string to string} "/interface/eoip/print" rows
 * @param remote {string}   the remote address
 * @param tunnelId {int} the tunnel id
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findEoipRow(rows as list of map of string to string, remote as string, tunnelId as int) {
    for (def row in $rows) {
        if (rowValue($row, "remote-address") == $remote and rowInt($row, "tunnel-id") == $tunnelId) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a reply row into an EoipTunnel.
 *
 * @param row {map of string to string} an "/interface/eoip/print" row
 * @return {EoipTunnel} the typed tunnel
 * @internal
 */
func eoipFromRow(row as map of string to string) {
    return EoipTunnel{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        remoteAddress: rowValue($row, "remote-address"),
        localAddress: rowValue($row, "local-address"),
        tunnelId: rowInt($row, "tunnel-id"),
        mac: rowValue($row, "mac-address"),
        mtu: rowValue($row, "mtu"),
        keepalive: rowValue($row, "keepalive"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
