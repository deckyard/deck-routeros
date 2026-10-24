# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - OpenVPN remote-access server and dial-out clients.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the OpenVPN server settings (single row). */
export def const OVPN_SERVER_PATH as string init "/interface/ovpn-server/server";

/** RouterOS API path of the OpenVPN client list (dial-out tunnels). */
export def const OVPN_CLIENT_PATH as string init "/interface/ovpn-client";

/**
 * The OpenVPN server settings.
 *
 * @field enabled {bool} true when the server accepts connections
 * @field port {int} TCP port it listens on (1194 by default)
 * @field mode {string} "ip" (routed, tun) or "ethernet" (bridged, tap)
 * @field certificate {string} TLS certificate it serves
 * @field defaultProfile {string} PPP profile applied to logins
 */
export def struct OvpnServer {
    enabled as bool,
    port as int,
    mode as string,
    certificate as string,
    defaultProfile as string
};

/**
 * One OpenVPN client: this router dialing out to an OpenVPN server.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} client interface name
 * @field connectTo {string} server address
 * @field user {string} login on the server
 * @field running {bool} true when the tunnel is up
 * @field disabled {bool} true when switched off
 * @field comment {string} comment, "" when unset
 */
export def struct OvpnClient {
    id as string,
    name as string,
    connectTo as string,
    user as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * Read the OpenVPN server settings.
 *
 * @param c {Client} an open client
 * @return {OvpnServer} the server state
 */
export func ovpnServerStatus(c as Client) {
    return ovpnServerFromRow(singleRow($c, OVPN_SERVER_PATH));
}

/**
 * Turn on a routed (`mode=ip`, tun) OpenVPN remote-access server.
 *
 * Clients exist for every OS, but each needs a config profile, so it is
 * less plug-and-play than L2TP. Needs a TLS certificate. Accepts the
 * port over TCP in the input chain. Add logins with `addVpnUser`.
 * Idempotent.
 *
 * @param c {Client} an open client
 * @param certificate {string} name of the TLS certificate in the store
 * @param port {int} TCP port (1194 is the OpenVPN default)
 * @throws {Error} kind "routeros" on a bad port or unknown certificate
 * @example
 *   mt.enableOvpnServer($c, "router-le-cert", 1194);
 *   mt.addVpnUser($c, "carol", "her password", "ovpn", "laptop");
 */
export func enableOvpnServer(c as Client, certificate as string, port as int) {
    ensurePort($port);
    requiredId($c, CERTIFICATE_PATH, $certificate, "certificate");
    apiRun(
        $c,
        OVPN_SERVER_PATH + "/set",
        {
            "enabled": "yes",
            "certificate": $certificate,
            "port": convert.toString($port),
            "mode": "ip"
        });
    ensureInputAccept($c, "ovpn: server", {"protocol": "tcp", "dst-port": convert.toString($port)});
}

/**
 * Turn the OpenVPN server off and remove its firewall opening.
 *
 * @param c {Client} an open client
 */
export func disableOvpnServer(c as Client) {
    apiRun($c, OVPN_SERVER_PATH + "/set", {"enabled": "no"});
    removeInputAcceptsByPrefix($c, "ovpn: server");
}

/**
 * List the OpenVPN clients (dial-out tunnels).
 *
 * @param c {Client} an open client
 * @return {list of OvpnClient} all OpenVPN clients
 */
export func ovpnClients(c as Client) {
    def rows as list of map of string to string init getAll($c, OVPN_CLIENT_PATH);
    def out as list of OvpnClient init [];
    for (def row in $rows) {
        $out[] = ovpnClientFromRow($row);
    }
    return $out;
}

/**
 * Dial out to a remote OpenVPN server.
 *
 * When a client of that name exists, its id is returned and nothing is
 * changed.
 *
 * @param c {Client} an open client
 * @param name {string} client interface name
 * @param serverAddress {string} server address or DNS name
 * @param user {string} login on the server
 * @param password {string} password for that login
 * @return {string} the RouterOS id of the new or existing client
 * @throws {Error} kind "routeros" on an empty or spaced name or user, an
 *         empty password, or an empty or spaced server address
 */
export func addOvpnClient(
    c as Client,
    name as string,
    serverAddress as string,
    user as string,
    password as string) {
    def none as map of string to string init {};
    return vpnClientAdd(
        $c,
        OVPN_CLIENT_PATH,
        "OpenVPN",
        $name,
        $serverAddress,
        $user,
        $password,
        $none);
}

/**
 * Remove an OpenVPN client.
 *
 * @param c {Client} an open client
 * @param name {string} client interface name
 * @throws {Error} kind "routeros" when no such client exists
 */
export func removeOvpnClient(c as Client, name as string) {
    remove($c, OVPN_CLIENT_PATH, requiredId($c, OVPN_CLIENT_PATH, $name, "OpenVPN client"));
}

/**
 * Fold a reply row into an OvpnServer.
 *
 * @param row {map of string to string} the "/interface/ovpn-server/server" row
 * @return {OvpnServer} the typed server state
 * @internal
 */
func ovpnServerFromRow(row as map of string to string) {
    return OvpnServer{
        enabled: rowBool($row, "enabled"),
        port: rowInt($row, "port"),
        mode: rowValue($row, "mode"),
        certificate: rowValue($row, "certificate"),
        defaultProfile: rowValue($row, "default-profile")
    };
}

/**
 * Fold a reply row into an OvpnClient.
 *
 * @param row {map of string to string} an "/interface/ovpn-client/print" row
 * @return {OvpnClient} the typed client
 * @internal
 */
func ovpnClientFromRow(row as map of string to string) {
    return OvpnClient{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        connectTo: rowValue($row, "connect-to"),
        user: rowValue($row, "user"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
