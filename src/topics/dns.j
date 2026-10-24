# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - DNS resolver settings, static entries, and the cache.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the DNS resolver menu. */
export def const DNS_PATH as string init "/ip/dns";

/** RouterOS API path of the static DNS entry list. */
export def const DNS_STATIC_PATH as string init "/ip/dns/static";

/** RouterOS API path of the DNS adlist (blocklists, RouterOS 7.15+). */
export def const DNS_ADLIST_PATH as string init "/ip/dns/adlist";

/** RouterOS API path of the DNS cache. */
export def const DNS_CACHE_PATH as string init "/ip/dns/cache";

/**
 * One DNS cache record.
 *
 * @field id {string}       internal RouterOS id
 * @field name {string}     DNS name the record answers for
 * @field kind {string}     record type ("A", "AAAA", "CNAME", ...)
 * @field data {string}     answer: an address for A/AAAA, a name for CNAME
 * @field ttl {string}      time until the record expires from the cache
 * @field isStatic {bool}   true for a static entry, which never expires
 */
export def struct DnsCacheEntry {
    id as string,
    name as string,
    kind as string,
    data as string,
    ttl as string,
    isStatic as bool
};

/**
 * The router's DNS resolver configuration.
 *
 * @field servers {string}             upstream servers, comma-separated
 * @field allowRemoteRequests {bool} true when the router answers its clients' queries
 * @field cacheSize {string}           cache size as RouterOS prints it (e.g. "2048KiB")
 * @field cacheUsed {string}           cache usage as RouterOS prints it
 */
export def struct DnsSettings {
    servers as string,
    allowRemoteRequests as bool,
    cacheSize as string,
    cacheUsed as string
};

/**
 * One static DNS entry: a local name with a fixed address.
 *
 * @field id {string}       internal RouterOS id
 * @field name {string}     DNS name (e.g. "nas.lan")
 * @field address {string}  address it resolves to
 * @field ttl {string}      time-to-live as RouterOS prints it (e.g. "1d")
 * @field disabled {bool}   true when switched off
 * @field comment {string}  free-text comment, "" when unset
 */
export def struct DnsEntry {
    id as string,
    name as string,
    address as string,
    ttl as string,
    disabled as bool,
    comment as string
};

/**
 * Read the router's DNS resolver configuration.
 *
 * @param c {Client} an open client
 * @return {DnsSettings} the resolver state
 */
export func dnsSettings(c as Client) {
    return dnsSettingsFromRow(singleRow($c, DNS_PATH));
}

/**
 * Point the router's resolver at upstream DNS servers.
 *
 * @param c {Client}       an open client
 * @param servers {string} comma-separated IP addresses (e.g.
 *                         "1.1.1.1, 9.9.9.9"); spaces are dropped
 * @throws {Error} kind "routeros" on an empty list, an empty entry, or an
 *                 entry that is not an IP address (DNS names are rejected)
 */
export func setDnsServers(c as Client, servers as string) {
    apiRun($c, DNS_PATH + "/set", {"servers": normalizedAddressList($servers)});
}

/**
 * Answer, or stop answering, DNS queries from clients.
 *
 * Needed when DHCP clients use the router as their DNS server. The router
 * then answers on every interface: on an internet-facing router, drop
 * UDP and TCP port 53 from the WAN (see `firewallRule`), or it is an open
 * resolver.
 *
 * @param c {Client}   an open client
 * @param allow {bool} true to answer client queries
 */
export func allowRemoteDnsRequests(c as Client, allow as bool) {
    apiRun($c, DNS_PATH + "/set", {"allow-remote-requests": boolWord($allow)});
}

/**
 * List the static DNS entries.
 *
 * @param c {Client} an open client
 * @return {list of DnsEntry} all static entries
 */
export func dnsStaticEntries(c as Client) {
    def rows as list of map of string to string init getAll($c, DNS_STATIC_PATH);
    def out as list of DnsEntry init [];
    for (def row in $rows) {
        $out[] = dnsEntryFromRow($row);
    }
    return $out;
}

/**
 * Add a static DNS entry: a local name with a fixed address.
 *
 * Clients see it only when they use the router as their DNS server
 * (see `allowRemoteDnsRequests`). Not idempotent: a second call adds a
 * second entry.
 *
 * @param c {Client}       an open client
 * @param name {string}    DNS name (e.g. "nas.lan")
 * @param address {string} IP address (v4 or v6) it resolves to
 * @return {string} the RouterOS id of the new entry
 * @throws {Error} kind "routeros" on an empty or spaced name or a malformed address
 */
export func addDnsEntry(c as Client, name as string, address as string) {
    ensureName($name, "DNS entry");
    ensureIpAddress($address);
    return add($c, DNS_STATIC_PATH, {"name": $name, "address": $address});
}

/**
 * Remove a static DNS entry by its name.
 *
 * @param c {Client}    an open client
 * @param name {string} DNS name of the entry
 * @throws {Error} kind "routeros" when no entry has that name
 */
export func removeDnsEntry(c as Client, name as string) {
    remove($c, DNS_STATIC_PATH, requiredId($c, DNS_STATIC_PATH, $name, "DNS entry"));
}

/**
 * Read the whole DNS cache.
 *
 * Large on a busy router; for one name use `dnsCacheFor` or
 * `resolvedAddresses`. The fill level is in `dnsSettings`
 * (`cacheUsed` / `cacheSize`).
 *
 * @param c {Client} an open client
 * @return {list of DnsCacheEntry} all cached records
 */
export func dnsCache(c as Client) {
    def rows as list of map of string to string init getAll($c, DNS_CACHE_PATH);
    def out as list of DnsCacheEntry init [];
    for (def row in $rows) {
        $out[] = dnsCacheEntryFromRow($row);
    }
    return $out;
}

/**
 * List the cached records for one name, matched case-insensitively.
 *
 * Several records are normal (A and AAAA, or a CNAME chain). An empty
 * list means the router has not resolved the name recently. The whole
 * cache is read and filtered locally.
 *
 * @param c {Client}    an open client
 * @param name {string} DNS name to look up
 * @return {list of DnsCacheEntry} the matching records, possibly empty
 * @throws {Error} kind "routeros" on an empty or spaced name
 */
export func dnsCacheFor(c as Client, name as string) {
    ensureName($name, "DNS");
    def rows as list of map of string to string init getAll($c, DNS_CACHE_PATH);
    def hits as list of map of string to string init cacheRowsForName($rows, $name);
    def out as list of DnsCacheEntry init [];
    for (def row in $hits) {
        $out[] = dnsCacheEntryFromRow($row);
    }
    return $out;
}

/**
 * List the addresses the cache holds for a name: the data of its A and
 * AAAA records, in cache order. CNAMEs are not followed.
 *
 * @param c {Client}    an open client
 * @param name {string} DNS name, matched case-insensitively
 * @return {list of string} the cached addresses, possibly empty
 * @throws {Error} kind "routeros" on an empty or spaced name
 * @example
 *   def addrs as list of string init mt.resolvedAddresses($c, "example.org");
 *   for (def a in $addrs) { io.printf("cached: %s\n", $a); }
 */
export func resolvedAddresses(c as Client, name as string) {
    ensureName($name, "DNS");
    def rows as list of map of string to string init getAll($c, DNS_CACHE_PATH);
    return addressesFromCacheRows($rows, $name);
}

/**
 * Empty the DNS cache, so the resolver asks upstream again.
 *
 * Use it after a DNS change or `setDnsServers`. Static entries are
 * configuration and survive.
 *
 * @param c {Client} an open client
 */
export func flushDnsCache(c as Client) {
    def none as map of string to string init {};
    apiRun($c, DNS_CACHE_PATH + "/flush", $none);
}

/**
 * Fold a reply row into the DnsSettings.
 *
 * @param row {map of string to string} the "/ip/dns/print" row
 * @return {DnsSettings} the typed resolver state
 * @internal
 */
func dnsSettingsFromRow(row as map of string to string) {
    return DnsSettings{
        servers: rowValue($row, "servers"),
        allowRemoteRequests: rowBool($row, "allow-remote-requests"),
        cacheSize: rowValue($row, "cache-size"),
        cacheUsed: rowValue($row, "cache-used")
    };
}

/**
 * Fold a reply row into a DnsEntry.
 *
 * @param row {map of string to string} an "/ip/dns/static/print" row
 * @return {DnsEntry} the typed entry
 * @internal
 */
func dnsEntryFromRow(row as map of string to string) {
    return DnsEntry{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        address: rowValue($row, "address"),
        ttl: rowValue($row, "ttl"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * The cache rows answering for a name, compared case-insensitively
 * (DNS names are).
 *
 * @param rows {list of map of string to string} "/ip/dns/cache/print" rows
 * @param name {string} the name to match
 * @return {list of map of string to string} the matching rows, in order
 * @internal
 */
func cacheRowsForName(rows as list of map of string to string, name as string) {
    def wanted as string init strings.lower(strings.trim($name));
    def out as list of map of string to string init [];
    for (def row in $rows) {
        if (strings.lower(rowValue($row, "name")) == $wanted) {
            $out[] = $row;
        }
    }
    return $out;
}

/**
 * The cached A/AAAA addresses for a name.
 *
 * @param rows {list of map of string to string} "/ip/dns/cache/print" rows
 * @param name {string} the name to match (case-insensitive)
 * @return {list of string} the address record data, in cache order
 * @internal
 */
func addressesFromCacheRows(rows as list of map of string to string, name as string) {
    def hits as list of map of string to string init cacheRowsForName($rows, $name);
    def out as list of string init [];
    for (def row in $hits) {
        def kind as string init rowValue($row, "type");
        if ($kind == "A" or $kind == "AAAA") {
            $out[] = rowValue($row, "data");
        }
    }
    return $out;
}

/**
 * Fold a reply row into a DnsCacheEntry.
 *
 * @param row {map of string to string} an "/ip/dns/cache/print" row
 * @return {DnsCacheEntry} the typed record
 * @internal
 */
func dnsCacheEntryFromRow(row as map of string to string) {
    return DnsCacheEntry{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        kind: rowValue($row, "type"),
        data: rowValue($row, "data"),
        ttl: rowValue($row, "ttl"),
        isStatic: rowBool($row, "static")
    };
}

/**
 * One DNS adlist: a hosts-format blocklist the resolver applies (v7.15+).
 *
 * @field id {string}        internal RouterOS id
 * @field url {string}        blocklist URL, "" for a local-file list
 * @field matchCount {string} number of names it blocks, as RouterOS prints it
 * @field disabled {bool}    true when switched off
 */
export def struct DnsAdlist {
    id as string,
    url as string,
    matchCount as string,
    disabled as bool
};

/**
 * List the DNS adlists (blocklists).
 *
 * @param c {Client} an open client
 * @return {list of DnsAdlist} all adlists
 */
export func dnsAdlists(c as Client) {
    def rows as list of map of string to string init getAll($c, DNS_ADLIST_PATH);
    def out as list of DnsAdlist init [];
    for (def row in $rows) {
        $out[] = dnsAdlistFromRow($row);
    }
    return $out;
}

/**
 * Add a DNS blocklist by URL, for router-wide ad and malware blocking.
 *
 * RouterOS 7.15+ downloads the hosts-format list and answers 0.0.0.0 for
 * every name on it, to every client that uses the router as resolver
 * (see `allowRemoteDnsRequests`). Large lists take noticeable RAM.
 * Idempotent by URL. RouterOS loads the list on its next refresh.
 *
 * @param c {Client}   an open client
 * @param url {string} blocklist URL, hosts format
 * @return {string} the RouterOS id of the (new or existing) adlist
 * @throws {Error} kind "routeros" on a URL that does not start with "http"
 * @example
 *   mt.allowRemoteDnsRequests($c, true);
 *   mt.addAdlist($c, "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts");
 */
export func addAdlist(c as Client, url as string) {
    def target as string init strings.trim($url);
    if ($target == "" or not strings.startsWith($target, "http")) {
        raiseError("the adlist URL must be an http(s) URL");
    }
    def rows as list of map of string to string init getAll($c, DNS_ADLIST_PATH);
    def existing as map of string to string init findRowByField($rows, "url", $target);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    return add($c, DNS_ADLIST_PATH, {"url": $target});
}

/**
 * Remove a DNS blocklist.
 *
 * @param c {Client}   an open client
 * @param url {string} blocklist URL, as added
 * @throws {Error} kind "routeros" when no adlist has that URL
 */
export func removeAdlist(c as Client, url as string) {
    def rows as list of map of string to string init getAll($c, DNS_ADLIST_PATH);
    def row as map of string to string init findRowByField($rows, "url", strings.trim($url));
    if (len($row) == 0) {
        raiseError("no adlist with the URL \"" + $url + "\" was found");
    }
    remove($c, DNS_ADLIST_PATH, rowValue($row, ".id"));
}

/**
 * Fold a reply row into a DnsAdlist.
 *
 * @param row {map of string to string} an "/ip/dns/adlist/print" row
 * @return {DnsAdlist} the typed adlist
 * @internal
 */
func dnsAdlistFromRow(row as map of string to string) {
    return DnsAdlist{
        id: rowValue($row, ".id"),
        url: rowValue($row, "url"),
        matchCount: rowValue($row, "match-count"),
        disabled: rowBool($row, "disabled")
    };
}
