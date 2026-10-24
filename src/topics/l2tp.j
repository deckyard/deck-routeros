# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - L2TP/IPsec remote-access VPN server and dial-out clients.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the L2TP server settings (single row). */
export def const L2TP_SERVER_PATH as string init "/interface/l2tp-server/server";

/** RouterOS API path of the L2TP client list (dial-out tunnels). */
export def const L2TP_CLIENT_PATH as string init "/interface/l2tp-client";

/**
 * The L2TP server settings.
 *
 * @field enabled {bool} true when the server accepts connections
 * @field useIpsec {bool} true when `use-ipsec` is anything but "no" (or unset)
 * @field defaultProfile {string} PPP profile applied to logins
 */
export def struct L2tpServer {
    enabled as bool,
    useIpsec as bool,
    defaultProfile as string
};

/**
 * One L2TP client: this router dialing out to an L2TP server.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} client interface name
 * @field connectTo {string} server address
 * @field user {string} login on the server
 * @field running {bool} true when the tunnel is up
 * @field disabled {bool} true when switched off
 * @field comment {string} comment, "" when unset
 */
export def struct L2tpClient {
    id as string,
    name as string,
    connectTo as string,
    user as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * Read the L2TP server settings.
 *
 * @param c {Client} an open client
 * @return {L2tpServer} the server state
 */
export func l2tpServerStatus(c as Client) {
    return l2tpServerFromRow(singleRow($c, L2TP_SERVER_PATH));
}

/**
 * Turn on an L2TP/IPsec remote-access server.
 *
 * Windows, macOS, iOS and Android dial L2TP/IPsec without extra
 * software. Sets `use-ipsec=required` with the given pre-shared key
 * (plain L2TP is cleartext) and accepts L2TP (udp 1701), IKE (udp 500),
 * NAT-T (udp 4500) and ESP in the input chain. Add logins with
 * `addVpnUser`. Idempotent.
 *
 * @param c {Client} an open client
 * @param ipsecSecret {string} pre-shared key every client also enters
 * @throws {Error} kind "routeros" on an empty secret
 * @example
 *   mt.enableL2tpServer($c, "a long random ipsec secret");
 *   mt.addVpnUser($c, "alice", "her password", "l2tp", "field laptop");
 *   # clients set: server = the router's public address/name, PSK = the
 *   # secret, username/password = the login
 */
export func enableL2tpServer(c as Client, ipsecSecret as string) {
    if (strings.trim($ipsecSecret) == "") {
        raiseError("the IPsec secret must not be empty - L2TP without it is cleartext");
    }
    apiRun(
        $c,
        L2TP_SERVER_PATH + "/set",
        {"enabled": "yes", "use-ipsec": "required", "ipsec-secret": $ipsecSecret});
    ensureInputAccept($c, "l2tp: server (l2tp)", {"protocol": "udp", "dst-port": "1701"});
    ensureInputAccept($c, "l2tp: server (ike)", {"protocol": "udp", "dst-port": "500"});
    ensureInputAccept($c, "l2tp: server (nat-t)", {"protocol": "udp", "dst-port": "4500"});
    ensureInputAccept($c, "l2tp: server (esp)", {"protocol": "ipsec-esp"});
}

/**
 * Turn the L2TP server off and remove its firewall openings.
 *
 * @param c {Client} an open client
 */
export func disableL2tpServer(c as Client) {
    apiRun($c, L2TP_SERVER_PATH + "/set", {"enabled": "no"});
    removeInputAcceptsByPrefix($c, "l2tp: server (");
}

/**
 * List the L2TP clients (dial-out tunnels).
 *
 * @param c {Client} an open client
 * @return {list of L2tpClient} all L2TP clients
 */
export func l2tpClients(c as Client) {
    def rows as list of map of string to string init getAll($c, L2TP_CLIENT_PATH);
    def out as list of L2tpClient init [];
    for (def row in $rows) {
        $out[] = l2tpClientFromRow($row);
    }
    return $out;
}

/**
 * Dial out to a remote L2TP server.
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
export func addL2tpClient(
    c as Client,
    name as string,
    serverAddress as string,
    user as string,
    password as string) {
    def none as map of string to string init {};
    return vpnClientAdd(
        $c,
        L2TP_CLIENT_PATH,
        "L2TP",
        $name,
        $serverAddress,
        $user,
        $password,
        $none);
}

/**
 * Remove an L2TP client.
 *
 * @param c {Client} an open client
 * @param name {string} client interface name
 * @throws {Error} kind "routeros" when no such client exists
 */
export func removeL2tpClient(c as Client, name as string) {
    remove($c, L2TP_CLIENT_PATH, requiredId($c, L2TP_CLIENT_PATH, $name, "L2TP client"));
}

/**
 * Fold a reply row into an L2tpServer.
 *
 * @param row {map of string to string} the "/interface/l2tp-server/server" row
 * @return {L2tpServer} the typed server state
 * @internal
 */
func l2tpServerFromRow(row as map of string to string) {
    return L2tpServer{
        enabled: rowBool($row, "enabled"),
        useIpsec: rowValue($row, "use-ipsec") != "no" and rowValue($row, "use-ipsec") != "",
        defaultProfile: rowValue($row, "default-profile")
    };
}

/**
 * Fold a reply row into an L2tpClient.
 *
 * @param row {map of string to string} an "/interface/l2tp-client/print" row
 * @return {L2tpClient} the typed client
 * @internal
 */
func l2tpClientFromRow(row as map of string to string) {
    return L2tpClient{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        connectTo: rowValue($row, "connect-to"),
        user: rowValue($row, "user"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
