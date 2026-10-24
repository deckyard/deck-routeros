# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - WireGuard VPN tunnels (RouterOS v7).
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the WireGuard interface list (needs RouterOS v7). */
export def const WIREGUARD_PATH as string init "/interface/wireguard";

/** RouterOS API path of the WireGuard peer list. */
export def const WIREGUARD_PEER_PATH as string init "/interface/wireguard/peers";

def const KEY_CHARS as string init "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

/**
 * One WireGuard interface: the local end of one or more tunnels.
 *
 * The private key is not read: the router generates and keeps it. Only
 * the public key, safe to share, is.
 *
 * @field id {string}         internal RouterOS id
 * @field name {string}       interface name (e.g. "wgvpn")
 * @field publicKey {string}  router's public key, to hand to peers
 * @field listenPort {int} UDP port the router listens on
 * @field mtu {string}        MTU as reported
 * @field running {bool}    true when the interface is up
 * @field disabled {bool}   true when the interface is switched off
 * @field comment {string}    free-text comment, "" when unset
 */
export def struct WireguardInterface {
    id as string,
    name as string,
    publicKey as string,
    listenPort as int,
    mtu as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * One WireGuard peer: a remote party allowed through a tunnel.
 *
 * @field id {string}              internal RouterOS id
 * @field interfaceName {string}   WireGuard interface the peer belongs to
 * @field publicKey {string}       the peer's public key
 * @field endpointAddress {string} address the router dials, "" when the
 *                                 peer dials in
 * @field endpointPort {string}    peer's UDP port, "" or "0" when it dials in
 * @field allowedAddress {string}  comma-separated CIDRs accepted from and
 *                                 routed to this peer
 * @field keepalive {string}       persistent keepalive as reported, "" when off
 * @field lastHandshake {string}   time since the last handshake
 * @field rx {string}              bytes received from the peer
 * @field tx {string}              bytes sent to the peer
 * @field disabled {bool}        true when the peer is switched off
 * @field comment {string}         free-text comment, the handle for removal
 */
export def struct WireguardPeer {
    id as string,
    interfaceName as string,
    publicKey as string,
    endpointAddress as string,
    endpointPort as string,
    allowedAddress as string,
    keepalive as string,
    lastHandshake as string,
    rx as string,
    tx as string,
    disabled as bool,
    comment as string
};

/**
 * List every WireGuard interface on the router.
 *
 * Any read error yields an empty list. That covers routers without
 * WireGuard (RouterOS v6), but also hides a dropped connection or a
 * permission error.
 *
 * @param c {Client} an open client
 * @return {list of WireguardInterface} all WireGuard interfaces
 */
export func wireguardInterfaces(c as Client) {
    def out as list of WireguardInterface init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, WIREGUARD_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = wireguardFromRow($row);
    }
    return $out;
}

/**
 * Create a WireGuard interface; the router generates the keypair.
 *
 * Idempotent by name: an existing interface of that name is returned
 * unchanged, even when its listen port differs. Read the public key for
 * the other side with `wireguardPublicKey`.
 *
 * @param c {Client}          an open client
 * @param name {string}       interface name (e.g. "wgvpn")
 * @param listenPort {int} UDP listen port, 1-65535 (e.g. 13231)
 * @return {string} the RouterOS id of the new or existing interface
 * @throws {Error} kind "routeros" on an empty or spaced name, or a port
 *                 outside 1-65535
 */
export func addWireguard(c as Client, name as string, listenPort as int) {
    ensureName($name, "WireGuard interface");
    ensurePort($listenPort);
    def existing as string init idByName($c, WIREGUARD_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    return add($c, WIREGUARD_PATH, {"name": $name, "listen-port": convert.toString($listenPort)});
}

/**
 * Read the router's public key for a WireGuard interface.
 *
 * The other side of the tunnel needs it; it is safe to share. The
 * private key never leaves the router through this deck.
 *
 * @param c {Client}    an open client
 * @param name {string} WireGuard interface name
 * @return {string} the base64 public key
 * @throws {Error} kind "routeros" when no such interface exists
 */
export func wireguardPublicKey(c as Client, name as string) {
    def row as map of string to string init findByName($c, WIREGUARD_PATH, $name);
    if (len($row) == 0) {
        raiseError("no WireGuard interface named \"" + $name +
            "\" was found - create one with addWireguard");
    }
    return rowValue($row, "public-key");
}

/**
 * Set up a WireGuard server: interface, VPN address and firewall opening.
 *
 * Creates the interface (`addWireguard`), puts `address` on it, and
 * accepts the listen port with an input-chain rule commented
 * "wireguard: <name>". Idempotent: each piece is created only if missing
 * (the address is matched by value, the rule by comment). Add peers with
 * `addWireguardPeer`.
 *
 * @param c {Client}          an open client
 * @param name {string}       interface name (e.g. "wgvpn")
 * @param listenPort {int} UDP listen port, 1-65535 (e.g. 13231)
 * @param address {string}    router's address inside the VPN, in CIDR
 *                            (e.g. "10.100.0.1/24")
 * @return {string} the RouterOS id of the WireGuard interface
 * @throws {Error} kind "routeros" on an address without prefix, or the
 *                 `addWireguard` errors
 * @example
 *   mt.setupWireguardServer($c, "wgvpn", 13231, "10.100.0.1/24");
 *   io.printf("server key: %s\n", mt.wireguardPublicKey($c, "wgvpn"));
 *   mt.addWireguardPeer($c, "wgvpn", $laptopKey, "10.100.0.2/32", "laptop");
 */
export func setupWireguardServer(
    c as Client,
    name as string,
    listenPort as int,
    address as string) {
    ensureCidr($address);
    def id as string init addWireguard($c, $name, $listenPort);
    def rows as list of map of string to string init getAll($c, IP_ADDRESS_PATH);
    def existing as map of string to string init findRowByField($rows, "address", $address);
    if (len($existing) == 0) {
        add($c, IP_ADDRESS_PATH, {"address": $address, "interface": $name});
    }
    def fwComment as string init "wireguard: " + $name;
    def fwRows as list of map of string to string init getAll($c, FIREWALL_PATH);
    def fwExisting as map of string to string init findRowByField($fwRows, "comment", $fwComment);
    if (len($fwExisting) == 0) {
        allowService($c, "udp", $listenPort, $fwComment);
    }
    return $id;
}

/**
 * List WireGuard peers with traffic counters and handshake age.
 *
 * A peer whose `lastHandshake` is within about 2 minutes is alive. Any
 * read error yields an empty list, as for `wireguardInterfaces` (meant
 * for RouterOS v6; it also hides a dropped connection).
 *
 * @param c {Client} an open client
 * @return {list of WireguardPeer} peers of all WireGuard interfaces
 */
export func wireguardPeers(c as Client) {
    def out as list of WireguardPeer init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, WIREGUARD_PEER_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = wireguardPeerFromRow($row);
    }
    return $out;
}

/**
 * Add a peer that dials in (server side): a laptop, phone or router.
 *
 * Traffic from and to the peer is accepted only for `allowedAddress`,
 * its address inside the VPN; a single device is "10.100.0.2/32". Not
 * idempotent: each call adds a peer.
 *
 * @param c {Client}              an open client
 * @param interfaceName {string}  existing WireGuard interface
 * @param publicKey {string}      peer's public key, 44 base64 characters
 *                                ending in "="
 * @param allowedAddress {string} peer's VPN address(es) in CIDR,
 *                                comma-separated
 * @param comment {string}        handle for the peer (e.g. "laptop"), "" for none
 * @return {string} the RouterOS id of the new peer
 * @throws {Error} kind "routeros" on an unknown interface, a malformed
 *                 key, or an allowed-address entry that is empty, has no
 *                 prefix or does not parse
 */
export func addWireguardPeer(
    c as Client,
    interfaceName as string,
    publicKey as string,
    allowedAddress as string,
    comment as string) {
    requiredId($c, WIREGUARD_PATH, $interfaceName, "WireGuard interface");
    ensureWireguardKey($publicKey);
    def allowed as string init normalizedAllowedAddress($allowedAddress);
    def attrs as map of string to string init {
        "interface": $interfaceName,
        "public-key": strings.trim($publicKey),
        "allowed-address": $allowed
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, WIREGUARD_PEER_PATH, $attrs);
}

/**
 * Add a peer the router dials (client side).
 *
 * Sets a 25-second persistent keepalive so the tunnel stays open through
 * NAT. allowedAddress "0.0.0.0/0" sends everything through the tunnel;
 * the remote networks' CIDRs send only those.
 *
 * @param c {Client}               an open client
 * @param interfaceName {string}   existing WireGuard interface
 * @param publicKey {string}       server's public key
 * @param endpointHost {string}    server's address or DNS name
 * @param endpointPort {int}    server's UDP port, 1-65535 (e.g. 13231)
 * @param allowedAddress {string}  networks to send through the tunnel in
 *                                 CIDR, comma-separated
 * @param comment {string}         handle for the peer, "" for none
 * @return {string} the RouterOS id of the new peer
 * @throws {Error} kind "routeros" on an unknown interface, a malformed
 *                 key, an empty or spaced host, a port outside 1-65535,
 *                 or a bad allowed-address entry
 * @example
 *   mt.addWireguard($c, "wghome", 13231);
 *   mt.connectWireguard($c, "wghome", $serverKey, "vpn.example.org", 13231,
 *       "10.100.0.0/24", "to home network");
 *   mt.addIpAddress($c, "10.100.0.3/24", "wghome");
 */
export func connectWireguard(
    c as Client,
    interfaceName as string,
    publicKey as string,
    endpointHost as string,
    endpointPort as int,
    allowedAddress as string,
    comment as string) {
    requiredId($c, WIREGUARD_PATH, $interfaceName, "WireGuard interface");
    ensureWireguardKey($publicKey);
    def host as string init strings.trim($endpointHost);
    ensureHost($host);
    ensurePort($endpointPort);
    def allowed as string init normalizedAllowedAddress($allowedAddress);
    def attrs as map of string to string init {
        "interface": $interfaceName,
        "public-key": strings.trim($publicKey),
        "endpoint-address": $host,
        "endpoint-port": convert.toString($endpointPort),
        "allowed-address": $allowed,
        "persistent-keepalive": "25"
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, WIREGUARD_PEER_PATH, $attrs);
}

/**
 * Remove the WireGuard peer that carries a comment.
 *
 * @param c {Client}       an open client
 * @param comment {string} comment the peer was added with
 * @throws {Error} kind "routeros" when no peer carries that comment
 */
export func removeWireguardPeerByComment(c as Client, comment as string) {
    def rows as list of map of string to string init getAll($c, WIREGUARD_PEER_PATH);
    def row as map of string to string init findRowByField($rows, "comment", $comment);
    if (len($row) == 0) {
        raiseError("no WireGuard peer with the comment \"" + $comment + "\" was found");
    }
    remove($c, WIREGUARD_PEER_PATH, rowValue($row, ".id"));
}

/**
 * Delete a WireGuard interface with its peers and what
 * `setupWireguardServer` created for it.
 *
 * Removes the first IP address on the interface, the "wireguard: <name>"
 * firewall rule if present, and the interface (its peers go with it).
 *
 * @param c {Client}    an open client
 * @param name {string} WireGuard interface name
 * @throws {Error} kind "routeros" when no such interface exists
 */
export func removeWireguard(c as Client, name as string) {
    def id as string init requiredId($c, WIREGUARD_PATH, $name, "WireGuard interface");
    def addrRows as list of map of string to string init getAll($c, IP_ADDRESS_PATH);
    def addrRow as map of string to string init findRowByField($addrRows, "interface", $name);
    if (len($addrRow) > 0) {
        remove($c, IP_ADDRESS_PATH, rowValue($addrRow, ".id"));
    }
    def fwRows as list of map of string to string init getAll($c, FIREWALL_PATH);
    def fwRow as map of string to string init findRowByField(
        $fwRows,
        "comment",
        "wireguard: " + $name);
    if (len($fwRow) > 0) {
        remove($c, FIREWALL_PATH, rowValue($fwRow, ".id"));
    }
    remove($c, WIREGUARD_PATH, $id);
}

/**
 * Switch a WireGuard interface on.
 *
 * @param c {Client}    an open client
 * @param name {string} WireGuard interface name
 * @throws {Error} kind "routeros" when no such interface exists
 */
export func enableWireguard(c as Client, name as string) {
    enable($c, WIREGUARD_PATH, requiredId($c, WIREGUARD_PATH, $name, "WireGuard interface"));
}

/**
 * Switch a WireGuard interface off; all its tunnels go down.
 *
 * @param c {Client}    an open client
 * @param name {string} WireGuard interface name
 * @throws {Error} kind "routeros" when no such interface exists
 */
export func disableWireguard(c as Client, name as string) {
    disable($c, WIREGUARD_PATH, requiredId($c, WIREGUARD_PATH, $name, "WireGuard interface"));
}

/**
 * Validate a WireGuard key: 44 base64 characters ending in "=".
 *
 * @param key {string} the candidate key
 * @throws {Error} kind "routeros" on any other shape
 * @internal
 */
func ensureWireguardKey(key as string) {
    def k as string init strings.trim($key);
    if (len($k) != 44 or not strings.endsWith($k, "=")) {
        raiseError("\"" + $key +
            "\" is not a WireGuard key - expected 44 base64 characters ending in \"=\"");
    }
    def chars as list of string init strings.chars($k);
    for (def ch in $chars) {
        if (not strings.contains(KEY_CHARS, $ch)) {
            raiseError("\"" + $key +
                "\" is not a WireGuard key - it contains characters outside base64");
        }
    }
}

/**
 * Validate and normalize a comma-separated allowed-address list.
 *
 * Every entry needs a prefix. A bare address is the most common
 * WireGuard mistake, so the error suggests the "/32" form.
 *
 * @param csv {string} the candidate list
 * @return {string} the normalized list
 * @throws {Error} kind "routeros" on an empty list or a bad entry
 * @internal
 */
func normalizedAllowedAddress(csv as string) {
    def parts as list of string init strings.split($csv, ",");
    def out as list of string init [];
    for (def part in $parts) {
        def p as string init strings.trim($part);
        if ($p == "") {
            raiseError("the allowed-address list \"" + $csv + "\" must not contain empty entries");
        }
        if (not strings.contains($p, "/")) {
            raiseError("\"" + $p + "\" is missing the prefix length - a single device is \"" + $p +
                "/32\"");
        }
        ensureCidr($p);
        $out[] = $p;
    }
    if (len($out) == 0) {
        raiseError("the allowed-address list must contain at least one network");
    }
    return strings.join($out, ",");
}

/**
 * Fold a reply row into a WireguardInterface.
 *
 * @param row {map of string to string} an "/interface/wireguard/print" row
 * @return {WireguardInterface} the typed interface
 * @internal
 */
func wireguardFromRow(row as map of string to string) {
    return WireguardInterface{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        publicKey: rowValue($row, "public-key"),
        listenPort: rowInt($row, "listen-port"),
        mtu: rowValue($row, "mtu"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold a reply row into a WireguardPeer.
 *
 * @param row {map of string to string} an "/interface/wireguard/peers/print" row
 * @return {WireguardPeer} the typed peer
 * @internal
 */
func wireguardPeerFromRow(row as map of string to string) {
    return WireguardPeer{
        id: rowValue($row, ".id"),
        interfaceName: rowValue($row, "interface"),
        publicKey: rowValue($row, "public-key"),
        endpointAddress: rowValue($row, "endpoint-address"),
        endpointPort: rowValue($row, "endpoint-port"),
        allowedAddress: rowValue($row, "allowed-address"),
        keepalive: rowValue($row, "persistent-keepalive"),
        lastHandshake: rowValue($row, "last-handshake"),
        rx: rowValue($row, "rx"),
        tx: rowValue($row, "tx"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
