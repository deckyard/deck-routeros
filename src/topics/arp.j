# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - the ARP table: which IP belongs to which MAC.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the ARP table. */
export def const ARP_PATH as string init "/ip/arp";

/**
 * One ARP entry: an IP-to-MAC binding on an interface.
 *
 * @field id {string} internal RouterOS id
 * @field address {string} IP address
 * @field mac {string} MAC address it resolves to, "" while unresolved
 * @field interfaceName {string} interface the binding lives on
 * @field dynamic {bool} true when learned, false for a static (pinned) entry
 * @field complete {bool} true when the MAC is known; false means the router
 *        asked and got no answer, typically an offline device
 * @field published {bool} true when the router answers ARP for this address
 *        itself (proxy ARP)
 * @field disabled {bool} true when the entry is switched off
 * @field comment {string} comment, "" when unset
 */
export def struct ArpEntry {
    id as string,
    address as string,
    mac as string,
    interfaceName as string,
    dynamic as bool,
    complete as bool,
    published as bool,
    disabled as bool,
    comment as string
};

/**
 * Read the whole ARP table.
 *
 * Every device the router recently exchanged packets with on a connected
 * network appears here, so it doubles as a "who is on my LAN" list.
 * Dynamic entries age out after a few minutes of silence.
 *
 * @param c {Client} an open client
 * @return {list of ArpEntry} dynamic and static entries
 */
export func arpTable(c as Client) {
    def rows as list of map of string to string init getAll($c, ARP_PATH);
    def out as list of ArpEntry init [];
    for (def row in $rows) {
        $out[] = arpFromRow($row);
    }
    return $out;
}

/**
 * Read the ARP entries on one interface.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} interface or bridge to filter for
 * @return {list of ArpEntry} that interface's entries
 */
export func arpTableOn(c as Client, interfaceName as string) {
    def all as list of ArpEntry init arpTable($c);
    def out as list of ArpEntry init [];
    for (def entry in $all) {
        if ($entry.interfaceName == $interfaceName) {
            $out[] = $entry;
        }
    }
    return $out;
}

/**
 * Look up the MAC address an IP currently resolves to.
 *
 * A miss is normal (the device is offline or has not talked to the
 * router), so it returns "" instead of throwing.
 *
 * @param c {Client} an open client
 * @param address {string} IP address to look up
 * @return {string} the MAC address, or "" when the table has no entry
 * @throws {Error} kind "routeros" on a malformed address
 */
export func macForAddress(c as Client, address as string) {
    def target as string init strings.trim($address);
    ensureIpAddress($target);
    def rows as list of map of string to string init getAll($c, ARP_PATH);
    def row as map of string to string init findRowByField($rows, "address", $target);
    return rowValue($row, "mac-address");
}

/**
 * Look up the IP addresses a MAC currently holds.
 *
 * A device can hold several addresses. The MAC is matched
 * case-insensitively.
 *
 * @param c {Client} an open client
 * @param mac {string} device MAC address, six colon-separated hex pairs
 * @return {list of string} its IP addresses in table order, possibly empty
 * @throws {Error} kind "routeros" on a malformed MAC
 */
export func addressesForMac(c as Client, mac as string) {
    ensureMac($mac);
    def rows as list of map of string to string init getAll($c, ARP_PATH);
    return addressesForMacRows($rows, $mac);
}

/**
 * Pin an IP-to-MAC binding as a static ARP entry.
 *
 * The router then never re-learns that address from the network. With the
 * interface's `arp` property set to `reply-only` (generic `set` on
 * INTERFACE_PATH), only pinned devices can talk at all. The MAC is stored
 * upper-case. Refuses when a static entry for the same address already
 * exists on the same interface.
 *
 * @param c {Client} an open client
 * @param address {string} IP address to pin
 * @param mac {string} MAC it must resolve to
 * @param interfaceName {string} interface or bridge the binding lives on
 * @return {string} id of the new entry
 * @throws {Error} kind "routeros" on a malformed address or MAC, an
 *                unknown interface, or an existing static entry
 * @example
 *   mt.addStaticArp($c, "192.168.88.50", "AA:BB:CC:DD:EE:FF", "brlan");
 */
export func addStaticArp(c as Client, address as string, mac as string, interfaceName as string) {
    def target as string init strings.trim($address);
    ensureIpAddress($target);
    ensureMac($mac);
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def rows as list of map of string to string init getAll($c, ARP_PATH);
    def existing as map of string to string init findStaticArpRow($rows, $target, $interfaceName);
    if (len($existing) > 0) {
        raiseError("a static ARP entry for " + $target + " on \"" + $interfaceName +
            "\" already exists - remove it first (removeArpEntry)");
    }
    return add(
        $c,
        ARP_PATH,
        {"address": $target, "mac-address": strings.upper($mac), "interface": $interfaceName});
}

/**
 * Remove the ARP entry for an address.
 *
 * Works on static entries (unpin) and dynamic ones: removing a dynamic
 * entry makes the router re-resolve, which clears a stale binding after a
 * device changed hardware. Only the first entry for the address is
 * removed.
 *
 * @param c {Client} an open client
 * @param address {string} IP address whose entry goes
 * @throws {Error} kind "routeros" when the table has no entry for it
 */
export func removeArpEntry(c as Client, address as string) {
    def target as string init strings.trim($address);
    def rows as list of map of string to string init getAll($c, ARP_PATH);
    def row as map of string to string init findRowByField($rows, "address", $target);
    if (len($row) == 0) {
        raiseError("the ARP table has no entry for \"" + $target + "\"");
    }
    remove($c, ARP_PATH, rowValue($row, ".id"));
}

/**
 * Remove every dynamic ARP entry on an interface.
 *
 * The router re-learns its neighbours from scratch. Static entries stay.
 * An interface with no dynamic entries is not an error.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} interface to flush
 * @return {int} number of entries removed
 */
export func flushArp(c as Client, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, ARP_PATH);
    def flushed as int init 0;
    for (def row in $rows) {
        if (rowValue($row, "interface") == $interfaceName and rowBool($row, "dynamic")) {
            remove($c, ARP_PATH, rowValue($row, ".id"));
            $flushed = $flushed + 1;
        }
    }
    return $flushed;
}

/**
 * Collect the addresses rows bound to a MAC, case-insensitively.
 *
 * @param rows {list of map of string to string} "/ip/arp/print" rows
 * @param mac {string} the MAC to match
 * @return {list of string} the bound addresses, in table order
 * @internal
 */
func addressesForMacRows(rows as list of map of string to string, mac as string) {
    def wanted as string init strings.upper(strings.trim($mac));
    def out as list of string init [];
    for (def row in $rows) {
        if (strings.upper(rowValue($row, "mac-address")) == $wanted) {
            $out[] = rowValue($row, "address");
        }
    }
    return $out;
}

/**
 * Find a static (non-dynamic) ARP row for an address on an interface.
 *
 * @param rows {list of map of string to string} "/ip/arp/print" rows
 * @param address {string}       the IP address
 * @param interfaceName {string} the interface
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findStaticArpRow(
    rows as list of map of string to string,
    address as string,
    interfaceName as string) {
    for (def row in $rows) {
        if (rowValue($row, "address") == $address and
            rowValue($row, "interface") == $interfaceName and not rowBool($row, "dynamic")) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a reply row into an ArpEntry.
 *
 * @param row {map of string to string} an "/ip/arp/print" row
 * @return {ArpEntry} the typed entry
 * @internal
 */
func arpFromRow(row as map of string to string) {
    return ArpEntry{
        id: rowValue($row, ".id"),
        address: rowValue($row, "address"),
        mac: rowValue($row, "mac-address"),
        interfaceName: rowValue($row, "interface"),
        dynamic: rowBool($row, "dynamic"),
        complete: rowBool($row, "complete"),
        published: rowBool($row, "published"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
