# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - SSTP remote-access VPN server and dial-out clients.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the SSTP server settings (single row). */
export def const SSTP_SERVER_PATH as string init "/interface/sstp-server/server";

/** RouterOS API path of the SSTP client list (dial-out tunnels). */
export def const SSTP_CLIENT_PATH as string init "/interface/sstp-client";

/**
 * The SSTP server settings.
 *
 * @field enabled {bool} true when the server accepts connections
 * @field port {int} TCP port it listens on (443 by default)
 * @field certificate {string} TLS certificate it serves
 * @field defaultProfile {string} PPP profile applied to logins
 */
export def struct SstpServer {
    enabled as bool,
    port as int,
    certificate as string,
    defaultProfile as string
};

/**
 * One SSTP client: this router dialing out to an SSTP server.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} client interface name
 * @field connectTo {string} server address
 * @field user {string} login on the server
 * @field running {bool} true when the tunnel is up
 * @field disabled {bool} true when switched off
 * @field comment {string} comment, "" when unset
 */
export def struct SstpClient {
    id as string,
    name as string,
    connectTo as string,
    user as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * Read the SSTP server settings.
 *
 * @param c {Client} an open client
 * @return {SstpServer} the server state
 */
export func sstpServerStatus(c as Client) {
    return sstpServerFromRow(singleRow($c, SSTP_SERVER_PATH));
}

/**
 * Turn on an SSTP remote-access server.
 *
 * SSTP is TLS over TCP; on port 443 it looks like HTTPS and passes
 * firewalls and captive networks that block L2TP or IKE. With a public
 * (Let's Encrypt) certificate built-in clients connect without
 * warnings; a self-signed one must be imported on each client. Accepts
 * the TCP port in the input chain. Add logins with `addVpnUser`.
 * Idempotent.
 *
 * @param c {Client} an open client
 * @param certificate {string} name of the TLS certificate in the store
 * @param port {int} TCP port (443 to look like HTTPS)
 * @throws {Error} kind "routeros" on a bad port or unknown certificate
 * @example
 *   mt.enableSstpServer($c, "router-le-cert", 443);
 *   mt.addVpnUser($c, "bob", "his password", "sstp", "remote worker");
 */
export func enableSstpServer(c as Client, certificate as string, port as int) {
    ensurePort($port);
    requiredId($c, CERTIFICATE_PATH, $certificate, "certificate");
    apiRun(
        $c,
        SSTP_SERVER_PATH + "/set",
        {"enabled": "yes", "certificate": $certificate, "port": convert.toString($port)});
    ensureInputAccept($c, "sstp: server", {"protocol": "tcp", "dst-port": convert.toString($port)});
}

/**
 * Turn the SSTP server off and remove its firewall opening.
 *
 * @param c {Client} an open client
 */
export func disableSstpServer(c as Client) {
    apiRun($c, SSTP_SERVER_PATH + "/set", {"enabled": "no"});
    removeInputAcceptsByPrefix($c, "sstp: server");
}

/**
 * List the SSTP clients (dial-out tunnels).
 *
 * @param c {Client} an open client
 * @return {list of SstpClient} all SSTP clients
 */
export func sstpClients(c as Client) {
    def rows as list of map of string to string init getAll($c, SSTP_CLIENT_PATH);
    def out as list of SstpClient init [];
    for (def row in $rows) {
        $out[] = sstpClientFromRow($row);
    }
    return $out;
}

/**
 * Dial out to a remote SSTP server.
 *
 * The client is created with `verify-server-certificate=no`: it does not
 * check the server's certificate. When a client of that name exists,
 * its id is returned and nothing is changed.
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
export func addSstpClient(
    c as Client,
    name as string,
    serverAddress as string,
    user as string,
    password as string) {
    def extra as map of string to string init {"verify-server-certificate": "no"};
    return vpnClientAdd(
        $c,
        SSTP_CLIENT_PATH,
        "SSTP",
        $name,
        $serverAddress,
        $user,
        $password,
        $extra);
}

/**
 * Remove an SSTP client.
 *
 * @param c {Client} an open client
 * @param name {string} client interface name
 * @throws {Error} kind "routeros" when no such client exists
 */
export func removeSstpClient(c as Client, name as string) {
    remove($c, SSTP_CLIENT_PATH, requiredId($c, SSTP_CLIENT_PATH, $name, "SSTP client"));
}

/**
 * Fold a reply row into an SstpServer.
 *
 * @param row {map of string to string} the "/interface/sstp-server/server" row
 * @return {SstpServer} the typed server state
 * @internal
 */
func sstpServerFromRow(row as map of string to string) {
    return SstpServer{
        enabled: rowBool($row, "enabled"),
        port: rowInt($row, "port"),
        certificate: rowValue($row, "certificate"),
        defaultProfile: rowValue($row, "default-profile")
    };
}

/**
 * Fold a reply row into an SstpClient.
 *
 * @param row {map of string to string} an "/interface/sstp-client/print" row
 * @return {SstpClient} the typed client
 * @internal
 */
func sstpClientFromRow(row as map of string to string) {
    return SstpClient{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        connectTo: rowValue($row, "connect-to"),
        user: rowValue($row, "user"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
