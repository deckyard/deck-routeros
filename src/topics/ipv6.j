# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - IPv6: the stack switch, addresses, neighbor discovery.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the global IPv6 settings. */
export def const IPV6_SETTINGS_PATH as string init "/ipv6/settings";

/** RouterOS API path of the IPv6 address table. */
export def const IPV6_ADDRESS_PATH as string init "/ipv6/address";

/** RouterOS API path of the neighbor-discovery (router advertisement) list. */
export def const IPV6_ND_PATH as string init "/ipv6/nd";

/**
 * The router's global IPv6 settings.
 *
 * @field disabled {bool}       true when the IPv6 stack is switched off
 * @field forward {bool}        true when the router routes IPv6 between interfaces
 * @field acceptRouterAdvertisements {bool} true when the router configures
 *              itself from RAs it receives
 * @field acceptRedirects {bool} true when ICMPv6 redirects are honored
 * @field maxNeighborEntries {int} neighbor-cache size limit, 0 when absent
 */
export def struct Ipv6Settings {
    disabled as bool,
    forward as bool,
    acceptRouterAdvertisements as bool,
    acceptRedirects as bool,
    maxNeighborEntries as int
};

/**
 * One IPv6 address on an interface.
 *
 * @field id {string}            internal RouterOS id
 * @field address {string}       address in CIDR form
 * @field interfaceName {string} interface it sits on
 * @field advertise {bool}       true when the prefix is announced in RAs
 * @field eui64 {bool}           true when the host part is derived from the MAC
 * @field linkLocal {bool}       true for a fe80::/10 address
 * @field dynamic {bool}         true when RouterOS created it (SLAAC, DHCPv6-PD)
 * @field disabled {bool}        true when switched off
 * @field comment {string}       free-text comment, "" when unset
 */
export def struct Ipv6Address {
    id as string,
    address as string,
    interfaceName as string,
    advertise as bool,
    eui64 as bool,
    linkLocal as bool,
    dynamic as bool,
    disabled as bool,
    comment as string
};

/**
 * One neighbor-discovery entry: how the router advertises itself on an
 * interface.
 *
 * @field id {string}            internal RouterOS id
 * @field interfaceName {string} interface, "all" for the default entry
 * @field raInterval {string}    advertisement interval as RouterOS prints it
 * @field raLifetime {string}    how long clients keep this router as default gateway
 * @field managed {bool}         M flag: clients get addresses from DHCPv6
 * @field otherConfig {bool}     O flag: clients get DNS and other options from DHCPv6
 * @field advertiseDns {bool}    true when RAs carry the router's DNS servers
 * @field disabled {bool}        true when switched off
 */
export def struct Ipv6Nd {
    id as string,
    interfaceName as string,
    raInterval as string,
    raLifetime as string,
    managed as bool,
    otherConfig as bool,
    advertiseDns as bool,
    disabled as bool
};

/**
 * Read the global IPv6 settings.
 *
 * @param c {Client} an open client
 * @return {Ipv6Settings} the current settings
 * @example
 *   def s as mt.Ipv6Settings init mt.ipv6Settings($c);
 *   if ($s.disabled) { io.printf("IPv6 is off on this router\n"); }
 */
export func ipv6Settings(c as Client) {
    return ipv6SettingsFromRow(singleRow($c, IPV6_SETTINGS_PATH));
}

/**
 * Switch the IPv6 stack off.
 *
 * The right choice on a v4-only network: with IPv6 half-configured, hosts
 * still autoconfigure from any RA on the wire and bypass firewall rules
 * that only match v4.
 *
 * The setting is stored at once; RouterOS applies it fully at the next
 * reboot.
 *
 * @param c {Client} an open client
 * @example
 *   mt.disableIpv6($c);
 */
export func disableIpv6(c as Client) {
    apiRun($c, IPV6_SETTINGS_PATH + "/set", {"disable-ipv6": "yes"});
}

/**
 * Switch the IPv6 stack on.
 *
 * Takes full effect after a reboot. The v4 firewall does not filter IPv6:
 * without `/ipv6/firewall` rules, LAN hosts with global addresses are
 * reachable from the internet.
 *
 * @param c {Client} an open client
 */
export func enableIpv6(c as Client) {
    apiRun($c, IPV6_SETTINGS_PATH + "/set", {"disable-ipv6": "no"});
}

/**
 * Turn IPv6 routing between interfaces on or off.
 *
 * @param c {Client}       an open client
 * @param enabled {bool}   true to route IPv6, false to keep it host-only
 */
export func setIpv6Forwarding(c as Client, enabled as bool) {
    apiRun($c, IPV6_SETTINGS_PATH + "/set", {"forward": boolWord($enabled)});
}

/**
 * Choose whether the router configures itself from router advertisements.
 *
 * Leave on when the uplink hands out IPv6 by SLAAC; turn off on a router
 * that should use only addresses you gave it.
 *
 * @param c {Client}       an open client
 * @param enabled {bool}   true to accept RAs
 */
export func setIpv6AcceptRouterAdvertisements(c as Client, enabled as bool) {
    apiRun($c, IPV6_SETTINGS_PATH + "/set", {"accept-router-advertisements": boolWord($enabled)});
}

/**
 * List the IPv6 addresses on the router.
 *
 * Includes dynamic ones (link-local, SLAAC, DHCPv6-PD); `dynamic` tells
 * them apart.
 *
 * @param c {Client} an open client
 * @return {list of Ipv6Address} every IPv6 address
 */
export func ipv6Addresses(c as Client) {
    def rows as list of map of string to string init getAll($c, IPV6_ADDRESS_PATH);
    def out as list of Ipv6Address init [];
    for (def row in $rows) {
        $out[] = ipv6AddressFromRow($row);
    }
    return $out;
}

/**
 * List the IPv6 addresses on one interface.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} interface to filter on, exact name
 * @return {list of Ipv6Address} its addresses, empty when it has none
 * @throws {Error} kind "routeros" on an empty or spaced interface name
 */
export func ipv6AddressesOn(c as Client, interfaceName as string) {
    ensureName($interfaceName, "interface");
    def target as string init strings.trim($interfaceName);
    def out as list of Ipv6Address init [];
    for (def a in ipv6Addresses($c)) {
        if ($a.interfaceName == $target) {
            $out[] = $a;
        }
    }
    return $out;
}

/**
 * Give an interface a static IPv6 address, advertised in RAs.
 *
 * Same as `addIpv6AddressWith` with `advertise` true and `eui64` false.
 * SLAAC works only on a /64, so a LAN wants /64; a router-to-router link
 * can use a longer prefix.
 *
 * @param c {Client}             an open client
 * @param cidr {string}          address in CIDR form (e.g. "2001:db8:1::1/64")
 * @param interfaceName {string} interface to put it on
 * @return {string} the RouterOS id of the new address
 * @throws {Error} kind "routeros" when the address is not IPv6 in CIDR
 *                 form, or the interface name is empty or spaced
 * @example
 *   mt.addIpv6Address($c, "2001:db8:1::1/64", "brlan");
 */
export func addIpv6Address(c as Client, cidr as string, interfaceName as string) {
    return addIpv6AddressWith($c, $cidr, $interfaceName, true, false);
}

/**
 * Give an interface a static IPv6 address, choosing how it is announced.
 *
 * `advertise` puts the prefix in router advertisements, so clients on
 * that LAN configure themselves by SLAAC: true for a client network,
 * false for a router-to-router link. `eui64` derives the host part from
 * the interface MAC, so the same call gives every router a stable,
 * distinct address inside the prefix.
 *
 * @param c {Client}             an open client
 * @param cidr {string}          address in CIDR form
 * @param interfaceName {string} interface to put it on
 * @param advertise {bool}       true to announce the prefix in RAs
 * @param eui64 {bool}           true to derive the host part from the MAC
 * @return {string} the RouterOS id of the new address
 * @throws {Error} kind "routeros" on a bad address or interface name
 * @example
 *   mt.addIpv6AddressWith($c, "2001:db8:1::/64", "brlan", true, true);
 */
export func addIpv6AddressWith(
    c as Client,
    cidr as string,
    interfaceName as string,
    advertise as bool,
    eui64 as bool) {
    ensureIpv6Cidr($cidr);
    ensureName($interfaceName, "interface");
    return add(
        $c,
        IPV6_ADDRESS_PATH,
        {
            "address": strings.trim($cidr),
            "interface": strings.trim($interfaceName),
            "advertise": boolWord($advertise),
            "eui-64": boolWord($eui64)
        });
}

/**
 * Remove a static IPv6 address.
 *
 * Dynamic addresses (link-local, SLAAC, DHCPv6-PD) are refused; remove
 * what creates them instead. The address is matched as text, so pass it
 * exactly as `ipv6Addresses` reports it.
 *
 * @param c {Client}    an open client
 * @param cidr {string} address in CIDR form, as RouterOS stores it
 * @throws {Error} kind "routeros" when it is not IPv6 CIDR, not configured,
 *                 or dynamic
 * @example
 *   mt.removeIpv6Address($c, "2001:db8:1::1/64");
 */
export func removeIpv6Address(c as Client, cidr as string) {
    ensureIpv6Cidr($cidr);
    def target as string init strings.trim($cidr);
    def rows as list of map of string to string init getAll($c, IPV6_ADDRESS_PATH);
    def row as map of string to string init findRowByField($rows, "address", $target);
    if (len($row) == 0) {
        raiseError("the IPv6 address " + $target + " is not configured on this router");
    }
    if (rowBool($row, "dynamic")) {
        raiseError("the IPv6 address " + $target +
            " is dynamic - remove what creates it, not the address");
    }
    remove($c, IPV6_ADDRESS_PATH, rowValue($row, ".id"));
}

/**
 * List the neighbor-discovery entries.
 *
 * @param c {Client} an open client
 * @return {list of Ipv6Nd} one entry per configured interface
 */
export func ipv6Nd(c as Client) {
    def rows as list of map of string to string init getAll($c, IPV6_ND_PATH);
    def out as list of Ipv6Nd init [];
    for (def row in $rows) {
        $out[] = ipv6NdFromRow($row);
    }
    return $out;
}

/**
 * Advertise this router on an interface, so clients there configure
 * themselves by SLAAC.
 *
 * Idempotent: enables the interface's existing entry, or creates one.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} interface to advertise on
 * @return {string} the RouterOS id of the entry
 * @throws {Error} kind "routeros" on an empty or spaced interface name
 * @example
 *   mt.advertiseIpv6On($c, "brlan");
 */
export func advertiseIpv6On(c as Client, interfaceName as string) {
    return setIpv6NdEntry($c, $interfaceName, {"disabled": "no"});
}

/**
 * Stop advertising this router on an interface.
 *
 * Disables the interface's entry (creating it disabled when absent).
 * Clients keep the addresses they built until the advertised lifetime
 * runs out.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} interface to stop advertising on
 * @return {string} the RouterOS id of the entry
 * @throws {Error} kind "routeros" on an empty or spaced interface name
 */
export func stopAdvertisingIpv6On(c as Client, interfaceName as string) {
    return setIpv6NdEntry($c, $interfaceName, {"disabled": "yes"});
}

/**
 * Set the M and O flags an interface advertises.
 *
 * `managed` (M) tells clients to get an address from DHCPv6;
 * `otherConfig` (O) tells them to build their own address but get DNS
 * from DHCPv6. Both false is pure SLAAC, the usual choice for a small
 * network. Creates the interface's entry when absent.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} interface the entry is for
 * @param managed {bool}         M flag
 * @param otherConfig {bool}     O flag
 * @return {string} the RouterOS id of the entry
 * @throws {Error} kind "routeros" on an empty or spaced interface name
 * @example
 *   mt.setIpv6NdFlags($c, "brlan", false, true);   # SLAAC + DHCPv6 for DNS
 */
export func setIpv6NdFlags(
    c as Client,
    interfaceName as string,
    managed as bool,
    otherConfig as bool) {
    return setIpv6NdEntry(
        $c,
        $interfaceName,
        {
            "managed-address-configuration": boolWord($managed),
            "other-configuration": boolWord($otherConfig)
        });
}

/**
 * Create or update the neighbor-discovery entry for an interface.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface the entry is for
 * @param attrs {map of string to string} the properties to write
 * @return {string} the RouterOS id of the entry
 * @throws {Error} kind "routeros" on an empty or spaced interface name
 * @internal
 */
func setIpv6NdEntry(c as Client, interfaceName as string, attrs as map of string to string) {
    ensureName($interfaceName, "interface");
    def target as string init strings.trim($interfaceName);
    def rows as list of map of string to string init getAll($c, IPV6_ND_PATH);
    def row as map of string to string init findRowByField($rows, "interface", $target);
    if (len($row) == 0) {
        def created as map of string to string init $attrs;
        $created["interface"] = $target;
        return add($c, IPV6_ND_PATH, $created);
    }
    def id as string init rowValue($row, ".id");
    set($c, IPV6_ND_PATH, $id, $attrs);
    return $id;
}

/**
 * Fold a reply row into Ipv6Settings.
 *
 * @param row {map of string to string} an "/ipv6/settings/print" row
 * @return {Ipv6Settings} the typed settings
 * @internal
 */
func ipv6SettingsFromRow(row as map of string to string) {
    return Ipv6Settings{
        disabled: rowBool($row, "disable-ipv6"),
        forward: rowBool($row, "forward"),
        acceptRouterAdvertisements: rowBool($row, "accept-router-advertisements"),
        acceptRedirects: rowBool($row, "accept-redirects"),
        maxNeighborEntries: rowInt($row, "max-neighbor-entries")
    };
}

/**
 * Fold a reply row into an Ipv6Address.
 *
 * @param row {map of string to string} an "/ipv6/address/print" row
 * @return {Ipv6Address} the typed address
 * @internal
 */
func ipv6AddressFromRow(row as map of string to string) {
    return Ipv6Address{
        id: rowValue($row, ".id"),
        address: rowValue($row, "address"),
        interfaceName: rowValue($row, "interface"),
        advertise: rowBool($row, "advertise"),
        eui64: rowBool($row, "eui-64"),
        linkLocal: rowBool($row, "link-local"),
        dynamic: rowBool($row, "dynamic"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold a reply row into an Ipv6Nd.
 *
 * @param row {map of string to string} an "/ipv6/nd/print" row
 * @return {Ipv6Nd} the typed entry
 * @internal
 */
func ipv6NdFromRow(row as map of string to string) {
    return Ipv6Nd{
        id: rowValue($row, ".id"),
        interfaceName: rowValue($row, "interface"),
        raInterval: rowValue($row, "ra-interval"),
        raLifetime: rowValue($row, "ra-lifetime"),
        managed: rowBool($row, "managed-address-configuration"),
        otherConfig: rowBool($row, "other-configuration"),
        advertiseDns: rowBool($row, "advertise-dns"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Validate an IPv6 address in CIDR form.
 *
 * A valid IPv4 CIDR gets its own message, since passing the v4 address
 * is the likely slip.
 *
 * @param cidr {string} the candidate (e.g. "2001:db8:1::1/64")
 * @throws {Error} kind "routeros" when it does not parse, or parses as IPv4
 * @internal
 */
func ensureIpv6Cidr(cidr as string) {
    ensureCidr($cidr);
    def net as ipnet.Network init ipnet.parse(strings.trim($cidr));
    if (ipnet.version($net.addr) != 6) {
        raiseError("\"" + $cidr + "\" is an IPv4 network - this call configures IPv6");
    }
}
