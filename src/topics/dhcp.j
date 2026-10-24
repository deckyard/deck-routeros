# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - DHCP server, leases, and the WAN-side DHCP client.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the address-pool list. */
export def const IP_POOL_PATH as string init "/ip/pool";

/** RouterOS API path of the DHCP server list. */
export def const DHCP_SERVER_PATH as string init "/ip/dhcp-server";

/** RouterOS API path of the DHCP network list (gateway and DNS per subnet). */
export def const DHCP_NETWORK_PATH as string init "/ip/dhcp-server/network";

/** RouterOS API path of the DHCP lease list. */
export def const DHCP_LEASE_PATH as string init "/ip/dhcp-server/lease";

/** RouterOS API path of the DHCP client list. */
export def const DHCP_CLIENT_PATH as string init "/ip/dhcp-client";

/** RouterOS API path of the DHCP relay list. */
export def const DHCP_RELAY_PATH as string init "/ip/dhcp-relay";

/**
 * One DHCP server instance.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          server name
 * @field interfaceName {string} interface the server listens on
 * @field addressPool {string}   pool it hands addresses out of
 * @field leaseTime {string}     lease duration as RouterOS prints it (e.g. "30m")
 * @field disabled {bool}        true when switched off
 */
export def struct DhcpServer {
    id as string,
    name as string,
    interfaceName as string,
    addressPool as string,
    leaseTime as string,
    disabled as bool
};

/**
 * One DHCP lease: an address handed out to, or reserved for, a device.
 *
 * @field id {string}           internal RouterOS id
 * @field address {string}      leased address
 * @field mac {string}          device MAC address
 * @field hostName {string}     host name the device sent, "" when none
 * @field server {string}       DHCP server that owns the lease
 * @field status {string}       lease state ("bound", "waiting", ...)
 * @field dynamic {bool}        true for an automatic lease, false for a reservation
 * @field expiresAfter {string} time until the lease runs out, "" for static
 * @field comment {string}      free-text comment, "" when unset
 */
export def struct DhcpLease {
    id as string,
    address as string,
    mac as string,
    hostName as string,
    server as string,
    status as string,
    dynamic as bool,
    expiresAfter as string,
    comment as string
};

/**
 * One DHCP client: an interface that gets its address from another
 * network, usually the ISP.
 *
 * @field id {string}              internal RouterOS id
 * @field interfaceName {string}   interface the client runs on
 * @field status {string}          "bound" when an address was obtained;
 *                                 "searching..." while still asking
 * @field bound {bool}             true when the status is "bound"
 * @field address {string}         address obtained, with prefix
 * @field gateway {string}         gateway obtained
 * @field primaryDns {string}      first DNS server announced, "" when none
 * @field secondaryDns {string}    second DNS server, "" when none
 * @field expiresAfter {string}    time until the lease must be renewed
 * @field usePeerDns {bool}        true when the router adopts the announced DNS servers
 * @field addDefaultRoute {string} default-route mode: "yes", "no" or
 *                                 "special-classless"
 * @field disabled {bool}          true when switched off
 * @field comment {string}         free-text comment, "" when unset
 */
export def struct DhcpClient {
    id as string,
    interfaceName as string,
    status as string,
    bound as bool,
    address as string,
    gateway as string,
    primaryDns as string,
    secondaryDns as string,
    expiresAfter as string,
    usePeerDns as bool,
    addDefaultRoute as string,
    disabled as bool,
    comment as string
};

/**
 * List every DHCP server instance on the router.
 *
 * @param c {Client} an open client
 * @return {list of DhcpServer} all DHCP servers
 */
export func dhcpServers(c as Client) {
    def rows as list of map of string to string init getAll($c, DHCP_SERVER_PATH);
    def out as list of DhcpServer init [];
    for (def row in $rows) {
        $out[] = dhcpServerFromRow($row);
    }
    return $out;
}

/**
 * Set up a DHCP server: address pool, server and network entry.
 *
 * Every value is checked before anything is created: the gateway and the
 * range ends must lie inside the network, the DNS entries must be IP
 * addresses, the interface must exist. The pool takes the server's name,
 * so `teardownDhcp` can undo the setup. Not idempotent.
 *
 * The interface needs an address inside the network as well (see
 * `addIpAddress`), or clients get a gateway they cannot reach.
 *
 * @param c {Client}             an open client
 * @param name {string}          name of the server and its pool (e.g. "dhcplan")
 * @param interfaceName {string} interface (or bridge) to serve on
 * @param network {string}       client network in CIDR form (e.g. "192.168.88.0/24")
 * @param gateway {string}       gateway told to clients, inside `network`
 *                               (usually the router's own address there)
 * @param rangeFrom {string}     first address to hand out, inside `network`
 * @param rangeTo {string}       last address to hand out, inside `network`
 * @param dns {string}           DNS servers told to clients, comma-separated IP
 *                               addresses (the gateway itself when the router
 *                               resolves, see `allowRemoteDnsRequests`)
 * @return {string} the RouterOS id of the DHCP server
 * @throws {Error} kind "routeros" when a value is malformed, outside the
 *                 network, or the interface does not exist
 * @example
 *   mt.addIpAddress($c, "192.168.77.1/24", "brlan");
 *   mt.setupDhcp($c, "dhcplan", "brlan", "192.168.77.0/24",
 *       "192.168.77.1", "192.168.77.10", "192.168.77.199", "192.168.77.1");
 */
export func setupDhcp(
    c as Client,
    name as string,
    interfaceName as string,
    network as string,
    gateway as string,
    rangeFrom as string,
    rangeTo as string,
    dns as string) {
    ensureName($name, "DHCP server");
    ensureCidr($network);
    ensureIpAddress($gateway);
    ensureIpAddress($rangeFrom);
    ensureIpAddress($rangeTo);
    def servers as string init normalizedAddressList($dns);
    ensureInNetwork($network, $gateway, "gateway");
    ensureInNetwork($network, $rangeFrom, "range start");
    ensureInNetwork($network, $rangeTo, "range end");
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    add($c, IP_POOL_PATH, {"name": $name, "ranges": $rangeFrom + "-" + $rangeTo});
    def serverId as string init add(
        $c,
        DHCP_SERVER_PATH,
        {"name": $name, "interface": $interfaceName, "address-pool": $name});
    add($c, DHCP_NETWORK_PATH, {"address": $network, "gateway": $gateway, "dns-server": $servers});
    return $serverId;
}

/**
 * Undo a `setupDhcp`: remove the server, its pool and the network entry.
 *
 * Each piece is removed when present, so a half-finished setup tears down
 * too. The network entry is matched by its exact CIDR string.
 *
 * @param c {Client}       an open client
 * @param name {string}    the name given to `setupDhcp`
 * @param network {string} the CIDR string given to `setupDhcp`
 * @throws {Error} kind "routeros" when none of the three pieces exists
 */
export func teardownDhcp(c as Client, name as string, network as string) {
    def found as int init 0;
    def serverId as string init idByName($c, DHCP_SERVER_PATH, $name);
    if ($serverId != "") {
        remove($c, DHCP_SERVER_PATH, $serverId);
        $found = $found + 1;
    }
    def poolId as string init idByName($c, IP_POOL_PATH, $name);
    if ($poolId != "") {
        remove($c, IP_POOL_PATH, $poolId);
        $found = $found + 1;
    }
    def rows as list of map of string to string init getAll($c, DHCP_NETWORK_PATH);
    def row as map of string to string init findRowByField($rows, "address", $network);
    if (len($row) > 0) {
        remove($c, DHCP_NETWORK_PATH, rowValue($row, ".id"));
        $found = $found + 1;
    }
    if ($found == 0) {
        raiseError("no DHCP setup named \"" + $name + "\" for network \"" + $network +
            "\" was found");
    }
}

/**
 * List every DHCP lease: addresses handed out and static reservations.
 *
 * @param c {Client} an open client
 * @return {list of DhcpLease} all leases
 */
export func dhcpLeases(c as Client) {
    def rows as list of map of string to string init getAll($c, DHCP_LEASE_PATH);
    def out as list of DhcpLease init [];
    for (def row in $rows) {
        $out[] = dhcpLeaseFromRow($row);
    }
    return $out;
}

/**
 * Reserve a fixed IP address for one device (a static lease).
 *
 * The device, identified by its MAC, gets `address` every time it asks.
 * Not idempotent.
 *
 * @param c {Client}       an open client
 * @param address {string} address to reserve (e.g. "192.168.88.50")
 * @param mac {string}     device MAC, six colon-separated hex pairs, any
 *                         case; sent uppercased
 * @param comment {string} free-text note (e.g. "printer"), "" for none
 * @return {string} the RouterOS id of the reservation
 * @throws {Error} kind "routeros" on a malformed address or MAC
 */
export func addStaticLease(c as Client, address as string, mac as string, comment as string) {
    ensureIpAddress($address);
    ensureMac($mac);
    def attrs as map of string to string init {
        "address": $address,
        "mac-address": strings.upper($mac)
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, DHCP_LEASE_PATH, $attrs);
}

/**
 * Remove the lease or reservation held by a MAC address.
 *
 * @param c {Client}   an open client
 * @param mac {string} device MAC, any case
 * @throws {Error} kind "routeros" on a malformed MAC or when no lease exists
 */
export func removeLeaseByMac(c as Client, mac as string) {
    ensureMac($mac);
    def rows as list of map of string to string init getAll($c, DHCP_LEASE_PATH);
    def row as map of string to string init findRowByField(
        $rows,
        "mac-address",
        strings.upper($mac));
    if (len($row) == 0) {
        raiseError("no DHCP lease for MAC \"" + $mac + "\" was found");
    }
    remove($c, DHCP_LEASE_PATH, rowValue($row, ".id"));
}

/**
 * List every DHCP client on the router.
 *
 * @param c {Client} an open client
 * @return {list of DhcpClient} all DHCP clients with their lease state
 */
export func dhcpClients(c as Client) {
    def rows as list of map of string to string init getAll($c, DHCP_CLIENT_PATH);
    def out as list of DhcpClient init [];
    for (def row in $rows) {
        $out[] = dhcpClientFromRow($row);
    }
    return $out;
}

/**
 * Run a DHCP client on the WAN interface.
 *
 * The client installs the ISP's default route and adopts its DNS
 * servers. Idempotent: when a DHCP client already runs on the interface,
 * its id is returned and its settings are left alone. With
 * `addMasquerade` on the same interface the LAN reaches the internet.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} internet-facing interface (e.g. "ether1")
 * @return {string} the RouterOS id of the (new or existing) DHCP client
 * @throws {Error} kind "routeros" when the interface does not exist
 * @example
 *   mt.setupWan($c, "ether1");
 *   mt.addMasquerade($c, "ether1", "lan to internet");
 */
export func setupWan(c as Client, interfaceName as string) {
    return setupWanWith($c, $interfaceName, true, true);
}

/**
 * Like `setupWan`, choosing what the router adopts from the ISP.
 *
 * Decline `addDefaultRoute` for a backup line whose route you manage
 * (`addRouteWithDistance`); decline `usePeerDns` to keep the servers set
 * with `setDnsServers`. Idempotent like `setupWan`: an existing client
 * keeps its settings.
 *
 * @param c {Client}               an open client
 * @param interfaceName {string}   internet-facing interface
 * @param usePeerDns {bool}        true to adopt the ISP's DNS servers
 * @param addDefaultRoute {bool}   true to install the ISP's default route
 * @return {string} the RouterOS id of the (new or existing) DHCP client
 * @throws {Error} kind "routeros" when the interface does not exist
 */
export func setupWanWith(
    c as Client,
    interfaceName as string,
    usePeerDns as bool,
    addDefaultRoute as bool) {
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def rows as list of map of string to string init getAll($c, DHCP_CLIENT_PATH);
    def existing as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    return add(
        $c,
        DHCP_CLIENT_PATH,
        {
            "interface": $interfaceName,
            "use-peer-dns": boolWord($usePeerDns),
            "add-default-route": boolWord($addDefaultRoute)
        });
}

/**
 * Read the DHCP client state of a WAN interface.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface the DHCP client runs on
 * @return {DhcpClient} the client state; check `bound` and `address`
 * @throws {Error} kind "routeros" when no DHCP client runs on that interface
 * @example
 *   def wan as mt.DhcpClient init mt.wanStatus($c, "ether1");
 *   if ($wan.bound) { io.printf("online as %s\n", $wan.address); }
 */
export func wanStatus(c as Client, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, DHCP_CLIENT_PATH);
    def row as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($row) == 0) {
        raiseError("no DHCP client runs on \"" + $interfaceName + "\" - set one up with setupWan");
    }
    return dhcpClientFromRow($row);
}

/**
 * Ask the ISP for a fresh lease now (DHCP renew).
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface the DHCP client runs on
 * @throws {Error} kind "routeros" when no DHCP client runs on that interface
 */
export func renewWan(c as Client, interfaceName as string) {
    apiRun($c, DHCP_CLIENT_PATH + "/renew", {".id": requiredDhcpClientId($c, $interfaceName)});
}

/**
 * Remove the DHCP client from an interface.
 *
 * The interface loses its ISP-assigned address, default route and DNS
 * servers: the uplink is down until reconfigured.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface the DHCP client runs on
 * @throws {Error} kind "routeros" when no DHCP client runs on that interface
 */
export func removeDhcpClient(c as Client, interfaceName as string) {
    remove($c, DHCP_CLIENT_PATH, requiredDhcpClientId($c, $interfaceName));
}

/**
 * Enable the DHCP client on an interface.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface the DHCP client runs on
 * @throws {Error} kind "routeros" when no DHCP client runs on that interface
 */
export func enableDhcpClient(c as Client, interfaceName as string) {
    enable($c, DHCP_CLIENT_PATH, requiredDhcpClientId($c, $interfaceName));
}

/**
 * Disable the DHCP client on an interface.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface the DHCP client runs on
 * @throws {Error} kind "routeros" when no DHCP client runs on that interface
 */
export func disableDhcpClient(c as Client, interfaceName as string) {
    disable($c, DHCP_CLIENT_PATH, requiredDhcpClientId($c, $interfaceName));
}

/**
 * Fold a reply row into a DhcpServer.
 *
 * @param row {map of string to string} an "/ip/dhcp-server/print" row
 * @return {DhcpServer} the typed server
 * @internal
 */
func dhcpServerFromRow(row as map of string to string) {
    return DhcpServer{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        interfaceName: rowValue($row, "interface"),
        addressPool: rowValue($row, "address-pool"),
        leaseTime: rowValue($row, "lease-time"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Fold a reply row into a DhcpLease.
 *
 * @param row {map of string to string} an "/ip/dhcp-server/lease/print" row
 * @return {DhcpLease} the typed lease
 * @internal
 */
func dhcpLeaseFromRow(row as map of string to string) {
    return DhcpLease{
        id: rowValue($row, ".id"),
        address: rowValue($row, "address"),
        mac: rowValue($row, "mac-address"),
        hostName: rowValue($row, "host-name"),
        server: rowValue($row, "server"),
        status: rowValue($row, "status"),
        dynamic: rowBool($row, "dynamic"),
        expiresAfter: rowValue($row, "expires-after"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Resolve an interface name to the id of its DHCP client, with a
 * friendly error when there is none.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface to look for
 * @return {string} the DHCP client id
 * @throws {Error} kind "routeros" when no DHCP client runs there
 * @internal
 */
func requiredDhcpClientId(c as Client, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, DHCP_CLIENT_PATH);
    def row as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($row) == 0) {
        raiseError("no DHCP client runs on \"" + $interfaceName + "\" - set one up with setupWan");
    }
    return rowValue($row, ".id");
}

/**
 * Fold a reply row into a DhcpClient.
 *
 * `bound` is computed here: the status equals "bound".
 *
 * @param row {map of string to string} an "/ip/dhcp-client/print" row
 * @return {DhcpClient} the typed client state
 * @internal
 */
func dhcpClientFromRow(row as map of string to string) {
    def status as string init rowValue($row, "status");
    return DhcpClient{
        id: rowValue($row, ".id"),
        interfaceName: rowValue($row, "interface"),
        status: $status,
        bound: $status == "bound",
        address: rowValue($row, "address"),
        gateway: rowValue($row, "gateway"),
        primaryDns: rowValue($row, "primary-dns"),
        secondaryDns: rowValue($row, "secondary-dns"),
        expiresAfter: rowValue($row, "expires-after"),
        usePeerDns: rowBool($row, "use-peer-dns"),
        addDefaultRoute: rowValue($row, "add-default-route"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * One DHCP relay: forwards a local network's DHCP requests to a remote
 * server.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          relay name
 * @field interfaceName {string} interface whose clients are relayed
 * @field dhcpServer {string}    remote DHCP server address
 * @field disabled {bool}        true when switched off
 */
export def struct DhcpRelay {
    id as string,
    name as string,
    interfaceName as string,
    dhcpServer as string,
    disabled as bool
};

/**
 * List the DHCP relays.
 *
 * @param c {Client} an open client
 * @return {list of DhcpRelay} all relays
 */
export func dhcpRelays(c as Client) {
    def rows as list of map of string to string init getAll($c, DHCP_RELAY_PATH);
    def out as list of DhcpRelay init [];
    for (def row in $rows) {
        $out[] = dhcpRelayFromRow($row);
    }
    return $out;
}

/**
 * Relay a network's DHCP requests to a central DHCP server.
 *
 * The clients' broadcasts on the interface are unicast to
 * `serverAddress` and the replies handed back. The interface needs an
 * address in the client network, which tells the server which subnet to
 * serve. Idempotent by name: an existing relay is returned unchanged.
 *
 * @param c {Client}             an open client
 * @param name {string}          relay name
 * @param interfaceName {string} interface whose clients are relayed
 * @param serverAddress {string} central DHCP server IP address
 * @return {string} the RouterOS id of the (new or existing) relay
 * @throws {Error} kind "routeros" on a bad name, an address that is not an
 *                 IP, or an unknown interface
 * @example
 *   mt.addDhcpRelay($c, "vlan20-relay", "vlanoffice", "10.0.0.5");
 */
export func addDhcpRelay(
    c as Client,
    name as string,
    interfaceName as string,
    serverAddress as string) {
    ensureName($name, "DHCP relay");
    def server as string init strings.trim($serverAddress);
    ensureIpAddress($server);
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def existing as string init idByName($c, DHCP_RELAY_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    return add(
        $c,
        DHCP_RELAY_PATH,
        {"name": $name, "interface": $interfaceName, "dhcp-server": $server});
}

/**
 * Remove a DHCP relay.
 *
 * @param c {Client}    an open client
 * @param name {string} relay name
 * @throws {Error} kind "routeros" when no relay has that name
 */
export func removeDhcpRelay(c as Client, name as string) {
    remove($c, DHCP_RELAY_PATH, requiredId($c, DHCP_RELAY_PATH, $name, "DHCP relay"));
}

/**
 * Fold a reply row into a DhcpRelay.
 *
 * @param row {map of string to string} an "/ip/dhcp-relay/print" row
 * @return {DhcpRelay} the typed relay
 * @internal
 */
func dhcpRelayFromRow(row as map of string to string) {
    return DhcpRelay{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        interfaceName: rowValue($row, "interface"),
        dhcpServer: rowValue($row, "dhcp-server"),
        disabled: rowBool($row, "disabled")
    };
}
