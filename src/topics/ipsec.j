# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - IPsec: standards-based site-to-site tunnels.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the IPsec peer list. */
export def const IPSEC_PEER_PATH as string init "/ip/ipsec/peer";

/** RouterOS API path of the IPsec identity list (authentication). */
export def const IPSEC_IDENTITY_PATH as string init "/ip/ipsec/identity";

/** RouterOS API path of the IPsec policy list (what gets encrypted). */
export def const IPSEC_POLICY_PATH as string init "/ip/ipsec/policy";

/** RouterOS API path of the active IPsec peers (read-only status). */
export def const IPSEC_ACTIVE_PATH as string init "/ip/ipsec/active-peers";

/** RouterOS API path of the IPsec mode-config (road-warrior client settings). */
export def const IPSEC_MODE_CONFIG_PATH as string init "/ip/ipsec/mode-config";

/**
 * One configured IPsec peer (the remote router).
 *
 * @field id {string} internal RouterOS id
 * @field name {string} peer name, the handle identity and policy refer to
 * @field address {string} remote router's address or DNS name
 * @field exchangeMode {string} "ike2" for peers this deck creates
 * @field disabled {bool} true when switched off
 */
export def struct IpsecPeer {
    id as string,
    name as string,
    address as string,
    exchangeMode as string,
    disabled as bool
};

/**
 * One IPsec policy: which traffic is encrypted to which peer.
 *
 * @field id {string} internal RouterOS id
 * @field peer {string} peer name
 * @field srcAddress {string} local subnet
 * @field dstAddress {string} remote subnet
 * @field tunnel {bool} true for tunnel mode (site-to-site)
 * @field active {bool} true when the policy has a live SA
 * @field disabled {bool} true when switched off
 */
export def struct IpsecPolicy {
    id as string,
    peer as string,
    srcAddress as string,
    dstAddress as string,
    tunnel as bool,
    active as bool,
    disabled as bool
};

/**
 * One live IPsec negotiation with a remote router.
 *
 * @field remoteAddress {string} the other end
 * @field state {string} negotiation state as reported
 * @field established {bool} computed: state equals "established"
 * @field uptime {string} time since the tunnel came up
 * @field side {string} "initiator" or "responder"
 */
export def struct IpsecActivePeer {
    remoteAddress as string,
    state as string,
    established as bool,
    uptime as string,
    side as string
};

/**
 * List the configured IPsec peers.
 *
 * @param c {Client} an open client
 * @return {list of IpsecPeer} all peers
 */
export func ipsecPeers(c as Client) {
    def rows as list of map of string to string init getAll($c, IPSEC_PEER_PATH);
    def out as list of IpsecPeer init [];
    for (def row in $rows) {
        $out[] = ipsecPeerFromRow($row);
    }
    return $out;
}

/**
 * List the IPsec policies with their live state.
 *
 * @param c {Client} an open client
 * @return {list of IpsecPolicy} all policies; `active` is the health flag
 */
export func ipsecPolicies(c as Client) {
    def rows as list of map of string to string init getAll($c, IPSEC_POLICY_PATH);
    def out as list of IpsecPolicy init [];
    for (def row in $rows) {
        $out[] = ipsecPolicyFromRow($row);
    }
    return $out;
}

/**
 * List the live IPsec negotiations (active peers).
 *
 * @param c {Client} an open client
 * @return {list of IpsecActivePeer} live peers; `established` is the health flag
 */
export func ipsecActive(c as Client) {
    def rows as list of map of string to string init getAll($c, IPSEC_ACTIVE_PATH);
    def out as list of IpsecActivePeer init [];
    for (def row in $rows) {
        $out[] = ipsecActiveFromRow($row);
    }
    return $out;
}

/**
 * Build an IKEv2 site-to-site tunnel with a pre-shared key.
 *
 * Use it when the far end is another vendor (Cisco, pfSense, a cloud VPN
 * gateway) or IPsec is required; between two MikroTiks WireGuard is
 * simpler. Creates:
 *
 * - the IKEv2 peer and its pre-shared-key identity;
 * - a tunnel-mode policy for localSubnet <-> remoteSubnet;
 * - a srcnat accept placed before the first srcnat rule, so masquerade
 *   does not rewrite tunnel traffic before IPsec matches it;
 * - input accepts for IKE (udp 500), NAT-T (udp 4500) and ESP, limited to
 *   the peer's address when it is an IP.
 *
 * The far end makes the mirror call: our address as its peer, the same
 * key, subnets swapped. When a peer of that name exists, its id is
 * returned and nothing is changed.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name, used for the peer and rule comments
 * @param peerAddress {string} remote router's public address or DNS name
 * @param psk {string} pre-shared key; the tunnel's only authentication, so
 *        long and random
 * @param localSubnet {string} this site's LAN in CIDR form (e.g. "192.168.10.0/24")
 * @param remoteSubnet {string} far site's LAN in CIDR form (e.g. "192.168.20.0/24")
 * @return {string} the RouterOS id of the peer
 * @throws {Error} kind "routeros" on a bad name, host or subnet, or an empty key
 * @example
 *   mt.setupIpsecTunnel($c, "tobranch", "203.0.113.99",
 *       "a long random shared secret", "192.168.10.0/24", "192.168.20.0/24");
 */
export func setupIpsecTunnel(
    c as Client,
    name as string,
    peerAddress as string,
    psk as string,
    localSubnet as string,
    remoteSubnet as string) {
    ensureName($name, "IPsec tunnel");
    def remote as string init strings.trim($peerAddress);
    ensureHost($remote);
    if (strings.trim($psk) == "") {
        raiseError("the pre-shared key must not be empty - it is the tunnel's entire authentication");
    }
    ensureCidr($localSubnet);
    ensureCidr($remoteSubnet);
    def existing as string init idByName($c, IPSEC_PEER_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    def peerId as string init add(
        $c,
        IPSEC_PEER_PATH,
        {"name": $name, "address": $remote, "exchange-mode": "ike2"});
    add($c, IPSEC_IDENTITY_PATH, {"peer": $name, "auth-method": "pre-shared-key", "secret": $psk});
    add(
        $c,
        IPSEC_POLICY_PATH,
        {"peer": $name, "tunnel": "yes", "src-address": $localSubnet, "dst-address": $remoteSubnet});
    ipsecNatBypass($c, $name, $localSubnet, $remoteSubnet);
    ipsecFirewallAccepts($c, $name, $remote);
    return $peerId;
}

/**
 * Remove what `setupIpsecTunnel` created: policy, identity, peer, NAT
 * bypass and firewall accepts.
 *
 * @param c {Client} an open client
 * @param name {string} name given to `setupIpsecTunnel`
 * @throws {Error} kind "routeros" when nothing of the tunnel exists
 */
export func teardownIpsecTunnel(c as Client, name as string) {
    def found as int init 0;
    def policyRows as list of map of string to string init getAll($c, IPSEC_POLICY_PATH);
    for (def row in $policyRows) {
        if (rowValue($row, "peer") == $name) {
            remove($c, IPSEC_POLICY_PATH, rowValue($row, ".id"));
            $found = $found + 1;
        }
    }
    def identityRows as list of map of string to string init getAll($c, IPSEC_IDENTITY_PATH);
    for (def row in $identityRows) {
        if (rowValue($row, "peer") == $name) {
            remove($c, IPSEC_IDENTITY_PATH, rowValue($row, ".id"));
            $found = $found + 1;
        }
    }
    def peerId as string init idByName($c, IPSEC_PEER_PATH, $name);
    if ($peerId != "") {
        remove($c, IPSEC_PEER_PATH, $peerId);
        $found = $found + 1;
    }
    def natRows as list of map of string to string init getAll($c, NAT_PATH);
    for (def row in $natRows) {
        if (rowValue($row, "comment") == "ipsec: " + $name + " (nat bypass)") {
            remove($c, NAT_PATH, rowValue($row, ".id"));
            $found = $found + 1;
        }
    }
    def fwRows as list of map of string to string init getAll($c, FIREWALL_PATH);
    for (def row in $fwRows) {
        if (strings.startsWith(rowValue($row, "comment"), "ipsec: " + $name + " (")) {
            remove($c, FIREWALL_PATH, rowValue($row, ".id"));
            $found = $found + 1;
        }
    }
    if ($found == 0) {
        raiseError("no IPsec tunnel named \"" + $name + "\" was found");
    }
}

/**
 * Insert the srcnat accept that keeps masquerade off tunnel traffic.
 *
 * Placed before the first srcnat rule; idempotent by comment.
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name, for the comment
 * @param localSubnet {string} this site's LAN
 * @param remoteSubnet {string} far site's LAN
 * @internal
 */
func ipsecNatBypass(c as Client, name as string, localSubnet as string, remoteSubnet as string) {
    def rows as list of map of string to string init getAll($c, NAT_PATH);
    def comment as string init "ipsec: " + $name + " (nat bypass)";
    def existing as map of string to string init findRowByField($rows, "comment", $comment);
    if (len($existing) > 0) {
        return;
    }
    def attrs as map of string to string init {
        "chain": CHAIN_SRCNAT,
        "action": "accept",
        "src-address": $localSubnet,
        "dst-address": $remoteSubnet,
        "comment": $comment
    };
    def anchor as string init firstChainRowId($rows, CHAIN_SRCNAT);
    if ($anchor != "") {
        $attrs["place-before"] = $anchor;
    }
    add($c, NAT_PATH, $attrs);
}

/**
 * Accept IKE, NAT-T and ESP from the peer in the input chain.
 *
 * Idempotent per rule by the comments "ipsec: <name> (ike|nat-t|esp)".
 *
 * @param c {Client} an open client
 * @param name {string} tunnel name
 * @param remote {string} peer address, the src match when it is an IP
 * @internal
 */
func ipsecFirewallAccepts(c as Client, name as string, remote as string) {
    def fwRows as list of map of string to string init getAll($c, FIREWALL_PATH);
    def kinds as list of string init ["ike", "nat-t", "esp"];
    for (def kind in $kinds) {
        def comment as string init "ipsec: " + $name + " (" + $kind + ")";
        def existing as map of string to string init findRowByField($fwRows, "comment", $comment);
        if (len($existing) == 0) {
            def attrs as map of string to string init {
                "chain": CHAIN_INPUT,
                "action": ACTION_ACCEPT,
                "comment": $comment
            };
            if ($kind == "ike") {
                $attrs["protocol"] = "udp";
                $attrs["dst-port"] = "500";
            } elseif ($kind == "nat-t") {
                $attrs["protocol"] = "udp";
                $attrs["dst-port"] = "4500";
            } else {
                $attrs["protocol"] = "ipsec-esp";
            }
            if (isIpAddress($remote)) {
                $attrs["src-address"] = $remote;
            }
            add($c, FIREWALL_PATH, $attrs);
        }
    }
}

/**
 * Find the first rule in a chain: the place-before anchor for rules that
 * must precede masquerade.
 *
 * @param rows {list of map of string to string} NAT (or filter) rows, in order
 * @param chain {string} the chain to look in
 * @return {string} the first rule's id, or ""
 * @internal
 */
func firstChainRowId(rows as list of map of string to string, chain as string) {
    for (def row in $rows) {
        if (rowValue($row, "chain") == $chain) {
            return rowValue($row, ".id");
        }
    }
    return "";
}

/**
 * Fold a reply row into an IpsecPeer.
 *
 * @param row {map of string to string} an "/ip/ipsec/peer/print" row
 * @return {IpsecPeer} the typed peer
 * @internal
 */
func ipsecPeerFromRow(row as map of string to string) {
    return IpsecPeer{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        address: rowValue($row, "address"),
        exchangeMode: rowValue($row, "exchange-mode"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Fold a reply row into an IpsecPolicy.
 *
 * @param row {map of string to string} an "/ip/ipsec/policy/print" row
 * @return {IpsecPolicy} the typed policy
 * @internal
 */
func ipsecPolicyFromRow(row as map of string to string) {
    return IpsecPolicy{
        id: rowValue($row, ".id"),
        peer: rowValue($row, "peer"),
        srcAddress: rowValue($row, "src-address"),
        dstAddress: rowValue($row, "dst-address"),
        tunnel: rowBool($row, "tunnel"),
        active: rowBool($row, "active"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Set up an IKEv2 remote-access (road-warrior) server for native clients.
 *
 * iOS/macOS, Windows and strongSwan dial in without an L2TP layer.
 * Creates an address pool and a mode-config named `name` (reused when
 * they exist), a passive IKEv2 peer, and an identity with
 * `auth-method=eap-radius`, so users are authenticated by RADIUS (see
 * the radius topic). The router proves itself with `certificate`.
 * Opens the input chain for IKE, NAT-T and ESP from any address.
 *
 * Treat the result as a starting point and test it with a real client:
 * the certificate trust chain and the EAP user source are easy to get
 * wrong. Between networks you control, WireGuard or `setupIpsecTunnel`
 * is simpler.
 *
 * @param c {Client} an open client
 * @param name {string} setup name, used for the pool, mode-config, peer and comments
 * @param certificate {string} name of the router's certificate in the store
 * @param poolRange {string} client address range (e.g. "10.200.0.10-10.200.0.200"),
 *        passed through unvalidated
 * @param dns {string} DNS server handed to clients (e.g. "10.200.0.1")
 * @return {string} the RouterOS id of the peer
 * @throws {Error} kind "routeros" on a bad name or DNS address, a missing
 *         certificate, or an existing peer of that name
 * @example
 *   mt.setupIkev2Server($c, "roadwarriors", "router-le-cert",
 *       "10.200.0.10-10.200.0.200", "1.1.1.1");
 *   # add EAP users via RADIUS, or /ip/ipsec identity with the generic verbs
 */
export func setupIkev2Server(
    c as Client,
    name as string,
    certificate as string,
    poolRange as string,
    dns as string) {
    ensureName($name, "IKEv2 server");
    requiredId($c, CERTIFICATE_PATH, $certificate, "certificate");
    ensureIpAddress($dns);
    if (idByName($c, IPSEC_PEER_PATH, $name) != "") {
        raiseError("the IKEv2 server \"" + $name + "\" already exists");
    }
    if (idByName($c, IP_POOL_PATH, $name) == "") {
        add($c, IP_POOL_PATH, {"name": $name, "ranges": strings.trim($poolRange)});
    }
    if (idByName($c, IPSEC_MODE_CONFIG_PATH, $name) == "") {
        add(
            $c,
            IPSEC_MODE_CONFIG_PATH,
            {
                "name": $name,
                "address-pool": $name,
                "address-prefix-length": "32",
                "static-dns": strings.trim($dns)
            });
    }
    def peerId as string init add(
        $c,
        IPSEC_PEER_PATH,
        {"name": $name, "exchange-mode": "ike2", "passive": "yes", "send-initial-contact": "no"});
    add(
        $c,
        IPSEC_IDENTITY_PATH,
        {
            "peer": $name,
            "auth-method": "eap-radius",
            "certificate": $certificate,
            "generate-policy": "port-strict",
            "mode-config": $name
        });
    ipsecFirewallAccepts($c, $name, "");
    return $peerId;
}

/**
 * Fold a reply row into an IpsecActivePeer; `established` is computed.
 *
 * @param row {map of string to string} an "/ip/ipsec/active-peers/print" row
 * @return {IpsecActivePeer} the typed live peer
 * @internal
 */
func ipsecActiveFromRow(row as map of string to string) {
    def state as string init rowValue($row, "state");
    return IpsecActivePeer{
        remoteAddress: rowValue($row, "remote-address"),
        state: $state,
        established: $state == "established",
        uptime: rowValue($row, "uptime"),
        side: rowValue($row, "side")
    };
}
