# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - firewall address lists: named sets of addresses.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the firewall address lists. */
export def const ADDRESS_LIST_PATH as string init "/ip/firewall/address-list";

/**
 * One entry of a firewall address list.
 *
 * @field id {string} internal RouterOS id
 * @field listName {string} list the entry belongs to, e.g. "blocklist"
 * @field address {string} IP, CIDR network or DNS name; RouterOS resolves
 *        names and follows their changes
 * @field timeout {string} remaining lifetime, "" for a permanent entry
 * @field dynamic {bool} true when something else created it, e.g. a
 *        firewall rule with add-src-to-address-list
 * @field disabled {bool} true when the entry is switched off
 * @field comment {string} comment, "" when unset
 */
export def struct AddressListEntry {
    id as string,
    listName as string,
    address as string,
    timeout as string,
    dynamic as bool,
    disabled as bool,
    comment as string
};

/**
 * List the names of all address lists on the router.
 *
 * Reads only the `list` property of every entry, so it still works on
 * tables far larger than a full read allows.
 *
 * @param c {Client} an open client
 * @return {list of string} distinct list names in first-seen order
 */
export func addressLists(c as Client) {
    def rows as list of map of string to string init apiPrintSelect(
        $c,
        ADDRESS_LIST_PATH,
        ["list"],
        []);
    return distinctLists($rows);
}

/**
 * Read the entries of one address list.
 *
 * @param c {Client} an open client
 * @param listName {string} list to read, e.g. "blocklist"
 * @return {list of AddressListEntry} its entries, empty for an unknown list
 */
export func addressListEntries(c as Client, listName as string) {
    def rows as list of map of string to string init [];
    if ($listName != "") {
        $rows = apiPrintWhere($c, ADDRESS_LIST_PATH, ["?list=" + $listName]);
    }
    def out as list of AddressListEntry init [];
    for (def row in $rows) {
        if (rowValue($row, "list") == $listName) {
            $out[] = addressListEntryFromRow($row);
        }
    }
    return $out;
}

/**
 * Add an address to a list permanently.
 *
 * The list is created with its first entry. The address may be an IP
 * ("203.0.113.7"), a network ("203.0.113.0/24") or a DNS name
 * ("bad.example.org", resolved and tracked by RouterOS). Addresses are
 * normalized the way RouterOS stores them ("203.0.113.7/32" becomes
 * "203.0.113.7", "10.0.0.5/24" becomes "10.0.0.0/24"). Idempotent: when
 * the list already holds the address, the existing entry's id is
 * returned. IPv6 entries belong in "/ipv6/firewall/address-list" (generic
 * `add`) and are refused here.
 *
 * @param c {Client} an open client
 * @param listName {string} list name, e.g. "blocklist"
 * @param address {string} IP, CIDR or DNS name
 * @param comment {string} comment, "" for none
 * @return {string} id of the new or existing entry
 * @throws {Error} kind "routeros" on a bad list name, a malformed or IPv6
 *                 address
 * @example
 *   mt.addToAddressList($c, "blocklist", "203.0.113.7", "ssh scanner");
 *   mt.dropAddressList($c, "blocklist", mt.CHAIN_INPUT, "drop blocklisted");
 */
export func addToAddressList(
    c as Client,
    listName as string,
    address as string,
    comment as string) {
    ensureName($listName, "address list");
    def entry as string init normalizedListAddress($address);
    def existing as map of string to string init addressListRow($c, $listName, $entry);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {"list": $listName, "address": $entry};
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, ADDRESS_LIST_PATH, $attrs);
}

/**
 * Add an address to a list with a lifetime; RouterOS removes it when the
 * timeout runs out.
 *
 * Not idempotent: each call adds an entry.
 *
 * @param c {Client} an open client
 * @param listName {string} list name
 * @param address {string} IP, CIDR or DNS name
 * @param timeout {string} lifetime as s/m/h/d/w tokens ("30m", "1d",
 *        "1d12h") or "HH:MM:SS"
 * @param comment {string} comment, "" for none
 * @return {string} id of the new entry
 * @throws {Error} kind "routeros" on a bad list name, address or timeout
 */
export func addToAddressListTimed(
    c as Client,
    listName as string,
    address as string,
    timeout as string,
    comment as string) {
    ensureName($listName, "address list");
    def entry as string init normalizedListAddress($address);
    def ttl as string init strings.trim($timeout);
    ensureSchedulerInterval($ttl);
    def attrs as map of string to string init {
        "list": $listName,
        "address": $entry,
        "timeout": $ttl
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, ADDRESS_LIST_PATH, $attrs);
}

/**
 * Remove one address from a list.
 *
 * @param c {Client} an open client
 * @param listName {string} list name
 * @param address {string} address as added (normalized like
 *        `addToAddressList`)
 * @throws {Error} kind "routeros" on a bad list name or address, or when
 *                 the list has no such entry
 */
export func removeFromAddressList(c as Client, listName as string, address as string) {
    ensureName($listName, "address list");
    def row as map of string to string init addressListRow(
        $c,
        $listName,
        normalizedListAddress($address));
    if (len($row) == 0) {
        raiseError("the list \"" + $listName + "\" has no entry \"" + $address + "\"");
    }
    remove($c, ADDRESS_LIST_PATH, rowValue($row, ".id"));
}

/**
 * Remove every static entry from an address list.
 *
 * Dynamic entries (from firewall rules or timeouts) stay; whatever
 * created them manages them. The entries are removed in batches, not
 * one command each.
 *
 * @param c {Client} an open client
 * @param listName {string} list to empty
 * @throws {Error} kind "routeros" on a bad list name or when the list has
 *                 no static entries
 */
export func clearAddressList(c as Client, listName as string) {
    ensureName($listName, "address list");
    def rows as list of map of string to string init apiPrintSelect(
        $c,
        ADDRESS_LIST_PATH,
        [".id", "list", "dynamic"],
        ["?list=" + $listName]);
    def ids as list of string init [];
    for (def row in $rows) {
        if (rowValue($row, "list") == $listName and not rowBool($row, "dynamic")) {
            $ids[] = rowValue($row, ".id");
        }
    }
    if (len($ids) == 0) {
        raiseError("the address list \"" + $listName + "\" has no static entries");
    }
    removeMany($c, ADDRESS_LIST_PATH, $ids);
}

/**
 * Add one firewall filter rule that drops all traffic from the members of
 * an address list.
 *
 * The rule stays while the list changes: maintain members with
 * `addToAddressList` / `removeFromAddressList`. The rule is appended to
 * the end of the chain and carries `comment` as its handle for the
 * *ByComment verbs. Not idempotent: each call adds a rule.
 *
 * @param c {Client} an open client
 * @param listName {string} list whose members are dropped
 * @param chain {string} CHAIN_INPUT to protect the router, CHAIN_FORWARD
 *        to protect the networks behind it
 * @param comment {string} rule handle, e.g. "drop blocklisted"
 * @return {string} id of the new rule
 * @throws {Error} kind "routeros" on a bad list name or chain
 */
export func dropAddressList(c as Client, listName as string, chain as string, comment as string) {
    ensureName($listName, "address list");
    def r as FirewallRule init firewallRule($chain, ACTION_DROP);
    $r = withSrcAddressList($r, $listName);
    $r = withComment($r, $comment);
    return addFirewallRule($c, $r);
}

/**
 * Read the entry of a list holding an address, filtered on the router.
 *
 * @param c {Client}         an open client
 * @param listName {string}  the list to search
 * @param address {string}   the normalized address to look for
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func addressListRow(c as Client, listName as string, address as string) {
    def rows as list of map of string to string init apiPrintWhere(
        $c,
        ADDRESS_LIST_PATH,
        ["?list=" + $listName, "?address=" + $address]);
    for (def row in $rows) {
        if (rowValue($row, "list") == $listName and rowValue($row, "address") == $address) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Distinct list names, in first-seen order.
 *
 * @param rows {list of map of string to string} address-list rows
 * @return {list of string} the list names, deduplicated
 * @internal
 */
func distinctLists(rows as list of map of string to string) {
    def out as list of string init [];
    for (def row in $rows) {
        def name as string init rowValue($row, "list");
        if ($name != "" and not lists.contains($out, $name)) {
            $out[] = $name;
        }
    }
    return $out;
}

/**
 * Validate an address-list address and normalize it the way RouterOS
 * stores it: an IPv4 address, a network with its host bits cleared ("/32"
 * dropped), or a DNS name as given.
 *
 * @param address {string} the candidate
 * @return {string} the normalized address
 * @throws {Error} kind "routeros" on an empty or malformed value, or an
 *                 IPv6 address or network (they go in the IPv6 list)
 * @internal
 */
func normalizedListAddress(address as string) {
    def entry as string init strings.trim($address);
    if (strings.contains($entry, "/")) {
        ensureCidr($entry);
        def net as ipnet.Network init ipnet.parse($entry);
        refuseV6ListAddress($entry, ipnet.version($net.addr));
        if ($net.prefix == 32) {
            return ipnet.toString($net.addr);
        }
        return ipnet.networkString($net);
    }
    if (isIpAddress($entry)) {
        def addr as ipnet.Address init ipnet.parseAddress($entry);
        refuseV6ListAddress($entry, ipnet.version($addr));
        return ipnet.toString($addr);
    }
    ensureName($entry, "address-list");
    return $entry;
}

/**
 * Refuse an IPv6 address-list entry.
 *
 * @param entry {string} the address, for the message
 * @param version {int}  its IP version
 * @throws {Error} kind "routeros" for version 6
 * @internal
 */
func refuseV6ListAddress(entry as string, version as int) {
    if ($version == 6) {
        raiseError("\"" + $entry + "\" is IPv6 - IPv6 address lists live under " +
            "/ipv6/firewall/address-list (generic add)");
    }
}

/**
 * Fold a reply row into an AddressListEntry.
 *
 * @param row {map of string to string} an "/ip/firewall/address-list/print" row
 * @return {AddressListEntry} the typed entry
 * @internal
 */
func addressListEntryFromRow(row as map of string to string) {
    return AddressListEntry{
        id: rowValue($row, ".id"),
        listName: rowValue($row, "list"),
        address: rowValue($row, "address"),
        timeout: rowValue($row, "timeout"),
        dynamic: rowBool($row, "dynamic"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
