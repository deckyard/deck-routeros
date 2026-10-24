# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - connection, generic verbs, shared validation and row helpers.
# Spliced into routeros.j via include - not a standalone module.

def const PORT_SPEC_CHARS as string init "0123456789,-";

def const HEX_CHARS as string init "0123456789abcdefABCDEF";

def const DIGIT_CHARS as string init "0123456789";

/**
 * An open, authenticated connection to one router.
 *
 * Made by `connect`, `connectTLS` or `connectWith`; passed first to every
 * other call; closed with `disconnect`.
 *
 * @field session {mikrotik.Session} the underlying API session
 * @field user {string} the logged-in account; the user helpers refuse to
 *        remove, disable or regroup it
 * @field verbose {bool} print every command to stdout before sending it
 *        (see `setVerbose`)
 */
export def struct Client {
    session as mikrotik.Session,
    user as string,
    verbose as bool
};

/**
 * Connect over the plaintext API port 8728.
 *
 * `MT_VERBOSE` in the environment seeds the verbose flag.
 *
 * @param host {string}     router IP address or DNS name
 * @param user {string}     RouterOS user name
 * @param password {string} RouterOS password
 * @return {Client} an authenticated client
 * @throws {Error} kind "mikrotik" when the connection or login fails
 */
export func connect(host as string, user as string, password as string) {
    return Client{
        session: mikrotik.connect(mikrotik.options($host, $user, $password)),
        user: $user,
        verbose: verboseFromEnv()
    };
}

/**
 * Connect over the TLS API port 8729 (api-ssl).
 *
 * The transport verifies the router's certificate.
 *
 * @param host {string}     router IP address or DNS name
 * @param user {string}     RouterOS user name
 * @param password {string} RouterOS password
 * @return {Client} an authenticated client
 * @throws {Error} kind "mikrotik" when the connection or login fails
 */
export func connectTLS(host as string, user as string, password as string) {
    return Client{
        session: mikrotik.connect(mikrotik.optionsTLS($host, $user, $password)),
        user: $user,
        verbose: verboseFromEnv()
    };
}

/**
 * Connect on an explicit port, with or without TLS.
 *
 * @param host {string}     router IP address or DNS name
 * @param port {int}        API TCP port, 1-65535
 * @param user {string}     RouterOS user name
 * @param password {string} RouterOS password
 * @param tls {bool}        wrap the connection in TLS
 * @return {Client} an authenticated client
 * @throws {Error} kind "routeros" on an invalid port,
 *                 kind "mikrotik" when the connection or login fails
 */
export func connectWith(
    host as string,
    port as int,
    user as string,
    password as string,
    tls as bool) {
    ensurePort($port);
    def o as mikrotik.Options init mikrotik.options($host, $user, $password);
    if ($tls) {
        $o = mikrotik.optionsTLS($host, $user, $password);
    }
    return Client{
        session: mikrotik.connect(mikrotik.withPort($o, $port)),
        user: $user,
        verbose: verboseFromEnv()
    };
}

/**
 * Close the connection behind a client.
 *
 * The client is unusable afterwards.
 *
 * @param c {Client} the client to close
 */
export func disconnect(c as Client) {
    mikrotik.close($c.session);
}

/**
 * Read every item under a path.
 *
 * Works for any list, including ones without a typed helper
 * (e.g. "/ip/dhcp-server/option").
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path; leading and trailing slashes optional
 * @return {list of map of string to string} one property map per item
 * @throws {Error} kind "routeros" on an empty path, kind "mikrotik" on a router error
 */
export func getAll(c as Client, path as string) {
    return apiPrint($c, apiPath($path));
}

/**
 * Create an item under a path.
 *
 * @param c {Client}     an open client
 * @param path {string}  RouterOS list path (e.g. "/interface/bridge")
 * @param attrs {map of string to string} properties of the new item, RouterOS names
 * @return {string} the new item's RouterOS id
 * @throws {Error} kind "routeros" on an empty path, kind "mikrotik" when the router refuses
 */
export func add(c as Client, path as string, attrs as map of string to string) {
    return apiRun($c, apiPath($path) + "/add", $attrs);
}

/**
 * Delete an item by its RouterOS id.
 *
 * RouterOS has no separate delete verb.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path the item lives under
 * @param id {string}   the item id (e.g. "*3"), from `add` or a row's ".id"
 * @throws {Error} kind "routeros" on an empty path or id, kind "mikrotik" when the router refuses
 */
export func remove(c as Client, path as string, id as string) {
    ensureId($id);
    apiRun($c, apiPath($path) + "/remove", {".id": $id});
}

/**
 * Change properties of an item.
 *
 * @param c {Client}     an open client
 * @param path {string}  RouterOS list path the item lives under
 * @param id {string}    the item id (e.g. "*3")
 * @param attrs {map of string to string} the properties to change
 * @throws {Error} kind "routeros" on an empty path or id, kind "mikrotik" when the router refuses
 */
export func set(c as Client, path as string, id as string, attrs as map of string to string) {
    ensureId($id);
    def merged as map of string to string init $attrs;
    $merged[".id"] = $id;
    apiRun($c, apiPath($path) + "/set", $merged);
}

/**
 * Synonym of `set`.
 *
 * @param c {Client}     an open client
 * @param path {string}  RouterOS list path the item lives under
 * @param id {string}    the item id
 * @param attrs {map of string to string} the properties to change
 * @throws {Error} kind "routeros" on an empty path or id, kind "mikrotik" when the router refuses
 */
export func update(c as Client, path as string, id as string, attrs as map of string to string) {
    set($c, $path, $id, $attrs);
}

/**
 * Find the first item under a path whose "name" property matches.
 *
 * Filters on the router with a `?name=` query word, so only matching rows
 * travel.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path
 * @param name {string} the value of the "name" property to look for
 * @return {map of string to string} the item's properties, empty when absent
 */
export func findByName(c as Client, path as string, name as string) {
    def rows as list of map of string to string init apiPrintWhere(
        $c,
        apiPath($path),
        ["?name=" + $name]);
    if (len($rows) == 0) {
        def empty as map of string to string init {};
        return $empty;
    }
    return $rows[0];
}

/**
 * Resolve a name to a RouterOS id under a path.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path
 * @param name {string} the value of the "name" property to look for
 * @return {string} the item id, "" when no item has that name
 */
export func idByName(c as Client, path as string, name as string) {
    def row as map of string to string init findByName($c, $path, $name);
    return rowValue($row, ".id");
}

/**
 * Delete the item under a path whose "name" property matches.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path
 * @param name {string} the name of the item to delete
 * @throws {Error} kind "routeros" when no item has that name
 */
export func removeByName(c as Client, path as string, name as string) {
    remove($c, $path, requiredId($c, $path, $name, "item"));
}

/**
 * Clear an item's disabled flag.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path
 * @param id {string}   the item id
 */
export func enable(c as Client, path as string, id as string) {
    set($c, $path, $id, {"disabled": "no"});
}

/**
 * Set an item's disabled flag; the item stays but has no effect.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path
 * @param id {string}   the item id
 */
export func disable(c as Client, path as string, id as string) {
    set($c, $path, $id, {"disabled": "yes"});
}

/**
 * Move an item of an ordered list directly above another item.
 *
 * RouterOS evaluates its ordered lists (firewall filter, NAT, mangle,
 * raw, simple queues) top to bottom and stops at the first match, so
 * position decides behavior. `beforeId` "" moves the item to the bottom.
 *
 * @param c {Client}        an open client
 * @param path {string}     ordered list path (e.g. "/ip/firewall/filter")
 * @param id {string}       the item to move
 * @param beforeId {string} the item to land above, "" for the bottom
 * @throws {Error} kind "routeros" on an empty id or a self-move,
 *                 kind "mikrotik" when the router rejects the move
 * @example
 *   mt.moveRule($c, mt.FIREWALL_PATH, $acceptWgId, $dropNonLanId);
 */
export func moveRule(c as Client, path as string, id as string, beforeId as string) {
    def p as string init apiPath($path);
    ensureId($id);
    def item as string init strings.trim($id);
    def attrs as map of string to string init {"numbers": $item};
    def dest as string init strings.trim($beforeId);
    if ($dest != "") {
        if ($dest == $item) {
            raiseError("a rule cannot be moved before itself");
        }
        $attrs["destination"] = $dest;
    }
    apiRun($c, $p + "/move", $attrs);
}

/**
 * Move an item to the top of its ordered list.
 *
 * A no-op when the item is already first. Reads the list to find the
 * current first item.
 *
 * @param c {Client}    an open client
 * @param path {string} ordered list path
 * @param id {string}   the item to move
 * @throws {Error} kind "routeros" on an empty id or an empty list
 * @example
 *   mt.moveRuleToTop($c, mt.RAW_PATH, $dropBogonsId);
 */
export func moveRuleToTop(c as Client, path as string, id as string) {
    ensureId($id);
    def rows as list of map of string to string init getAll($c, $path);
    if (len($rows) == 0) {
        raiseError("the list " + apiPath($path) + " has no items to reorder");
    }
    def firstId as string init rowValue($rows[0], ".id");
    if ($firstId == strings.trim($id)) {
        return;
    }
    moveRule($c, $path, $id, $firstId);
}

/**
 * Move an item to the bottom of its ordered list.
 *
 * @param c {Client}    an open client
 * @param path {string} ordered list path
 * @param id {string}   the item to move
 * @throws {Error} kind "routeros" on an empty id
 */
export func moveRuleToBottom(c as Client, path as string, id as string) {
    moveRule($c, $path, $id, "");
}

/**
 * Throw the module's error.
 *
 * @param message {string} human-readable failure description
 * @throws {Error} always, kind "routeros"
 * @internal
 */
func raiseError(message as string) {
    throw Error{kind: "routeros", message: $message, file: "", line: 0, col: 0};
}

/**
 * Normalize a RouterOS API path: trim, force a leading slash, strip
 * trailing slashes.
 *
 * @param path {string} raw path (e.g. "interface/bridge/")
 * @return {string} the normalized path (e.g. "/interface/bridge")
 * @throws {Error} kind "routeros" on an empty or root-only path
 * @internal
 */
func apiPath(path as string) {
    def p as string init strings.trim($path);
    if ($p == "") {
        raiseError("the API path must not be empty");
    }
    if (not strings.startsWith($p, "/")) {
        $p = "/" + $p;
    }
    while (strings.endsWith($p, "/") and len($p) > 1) {
        $p = $p[..len($p) - 1];
    }
    if ($p == "/") {
        raiseError("the API path must name a list, not the root");
    }
    return $p;
}

/**
 * Render a bool the way RouterOS expects it in attributes.
 *
 * @param value {bool} the flag
 * @return {string} "yes" or "no"
 * @internal
 */
func boolWord(value as bool) {
    if ($value) {
        return "yes";
    }
    return "no";
}

/**
 * Read a property from a reply row, "" when absent.
 *
 * @param row {map of string to string} a reply row
 * @param key {string} property name
 * @return {string} the value or ""
 * @internal
 */
func rowValue(row as map of string to string, key as string) {
    if (maps.has($row, $key)) {
        return $row[$key];
    }
    return "";
}

/**
 * Read a boolean property from a reply row; absent counts as false.
 *
 * RouterOS renders flags as "true"/"false" (v7) or "yes"/"no" (older);
 * both are accepted.
 *
 * @param row {map of string to string} a reply row
 * @param key {string} property name
 * @return {bool} the flag
 * @internal
 */
func rowBool(row as map of string to string, key as string) {
    def v as string init rowValue($row, $key);
    return $v == "true" or $v == "yes";
}

/**
 * Find the first row whose property `key` equals `value`.
 *
 * @param rows {list of map of string to string} reply rows
 * @param key {string}   property name to compare
 * @param value {string} value to look for
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findRowByField(rows as list of map of string to string, key as string, value as string) {
    for (def row in $rows) {
        if (rowValue($row, $key) == $value) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Resolve a name to an id under a path, throwing a friendly error when absent.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS list path
 * @param name {string} the "name" property value to look for
 * @param what {string} noun for the error message (e.g. "bridge")
 * @return {string} the item id
 * @throws {Error} kind "routeros" when no item has that name
 * @internal
 */
func requiredId(c as Client, path as string, name as string, what as string) {
    def id as string init idByName($c, $path, $name);
    if ($id == "") {
        raiseError("the " + $what + " \"" + $name + "\" was not found on the router");
    }
    return $id;
}

/**
 * Validate a non-empty, space-free name.
 *
 * @param name {string} the candidate name
 * @param what {string} noun for the error message
 * @throws {Error} kind "routeros" on an empty or space-containing name
 * @internal
 */
func ensureName(name as string, what as string) {
    if (strings.trim($name) == "") {
        raiseError("the " + $what + " name must not be empty");
    }
    if (strings.contains($name, " ")) {
        raiseError("the " + $what + " name must not contain spaces");
    }
}

/**
 * Validate a RouterOS item id.
 *
 * @param id {string} the candidate id
 * @throws {Error} kind "routeros" on an empty id
 * @internal
 */
func ensureId(id as string) {
    if (strings.trim($id) == "") {
        raiseError("the item id must not be empty");
    }
}

/**
 * Validate a single TCP/UDP port number.
 *
 * @param port {int} the candidate port
 * @throws {Error} kind "routeros" when outside 1-65535
 * @internal
 */
func ensurePort(port as int) {
    if ($port < 1 or $port > 65535) {
        raiseError("the port must be between 1 and 65535");
    }
}

/**
 * Validate a port spec: digits plus "," (list) and "-" (range).
 *
 * @param spec {string} the candidate spec
 * @throws {Error} kind "routeros" on an empty spec or a foreign character
 * @internal
 */
func ensurePortSpec(spec as string) {
    if ($spec == "") {
        raiseError("the port spec must not be empty");
    }
    def parts as list of string init strings.chars($spec);
    for (def ch in $parts) {
        if (not strings.contains(PORT_SPEC_CHARS, $ch)) {
            raiseError("the port spec \"" + $spec + "\" may only contain digits, \",\" and \"-\"");
        }
    }
}

/**
 * Read a single-entry menu (e.g. "/system/resource") as one row.
 *
 * @param c {Client}    an open client
 * @param path {string} RouterOS menu path
 * @return {map of string to string} the first row, or an empty map when
 *         the router sent nothing
 * @internal
 */
func singleRow(c as Client, path as string) {
    def rows as list of map of string to string init getAll($c, $path);
    if (len($rows) > 0) {
        return $rows[0];
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Merge progress rows into one; later rows win on a shared key.
 *
 * Streaming commands like "check-for-updates" report progress as a
 * sequence of partial rows; the final state is their overlay.
 *
 * @param rows {list of map of string to string} the reply rows, in order
 * @return {map of string to string} the merged row
 * @internal
 */
func mergeRows(rows as list of map of string to string) {
    def merged as map of string to string init {};
    for (def row in $rows) {
        def names as list of string init maps.keys($row);
        for (def key in $names) {
            $merged[$key] = $row[$key];
        }
    }
    return $merged;
}

/**
 * Validate one plain IP address (v4 or v6), no prefix.
 *
 * @param address {string} the candidate address
 * @throws {Error} kind "routeros" when it does not parse
 * @internal
 */
func ensureIpAddress(address as string) {
    try {
        ipnet.parseAddress(strings.trim($address));
    } catch (e) {
        raiseError("\"" + $address + "\" is not a valid IP address");
    }
}

/**
 * Validate an address in CIDR form ("address/prefix").
 *
 * @param cidr {string} the candidate (e.g. "192.168.88.0/24")
 * @throws {Error} kind "routeros" on a missing prefix or a parse failure
 * @internal
 */
func ensureCidr(cidr as string) {
    if (not strings.contains($cidr, "/")) {
        raiseError("\"" + $cidr +
            "\" is missing the prefix length - write it like \"192.168.88.0/24\"");
    }
    try {
        ipnet.parse(strings.trim($cidr));
    } catch (e) {
        raiseError("\"" + $cidr + "\" is not a valid network in CIDR form");
    }
}

/**
 * Require an address to lie inside a network.
 *
 * Call after `ensureCidr` / `ensureIpAddress`, so parse errors have
 * already been reported with better messages.
 *
 * @param cidr {string}    the network (e.g. "192.168.88.0/24")
 * @param address {string} the address that must be inside it
 * @param what {string}    noun for the error message (e.g. "gateway")
 * @throws {Error} kind "routeros" when the address is outside
 * @internal
 */
func ensureInNetwork(cidr as string, address as string, what as string) {
    def net as ipnet.Network init ipnet.parse(strings.trim($cidr));
    def addr as ipnet.Address init ipnet.parseAddress(strings.trim($address));
    if (not ipnet.contains($net, $addr)) {
        raiseError("the " + $what + " " + $address + " is not inside the network " + $cidr);
    }
}

/**
 * Reject a malformed MAC address.
 *
 * @param mac {string} the offending value
 * @throws {Error} always, kind "routeros"
 * @internal
 */
func badMac(mac as string) {
    raiseError("\"" + $mac +
        "\" is not a MAC address - expected six hex pairs like \"AA:BB:CC:DD:EE:FF\"");
}

/**
 * Validate a MAC address: six colon-separated hex pairs, any case.
 *
 * @param mac {string} the candidate MAC
 * @throws {Error} kind "routeros" on any other shape
 * @internal
 */
func ensureMac(mac as string) {
    def parts as list of string init strings.split($mac, ":");
    if (len($parts) != 6) {
        badMac($mac);
    }
    for (def part in $parts) {
        if (len($part) != 2) {
            badMac($mac);
        }
        def chars as list of string init strings.chars($part);
        for (def ch in $chars) {
            if (not strings.contains(HEX_CHARS, $ch)) {
                badMac($mac);
            }
        }
    }
}

/**
 * Validate and normalize a comma-separated list of IP addresses.
 *
 * @param csv {string} e.g. "1.1.1.1, 9.9.9.9" (spaces tolerated)
 * @return {string} the normalized list, e.g. "1.1.1.1,9.9.9.9"
 * @throws {Error} kind "routeros" on an empty list, an empty entry, or
 *                 an entry that is not an IP address
 * @internal
 */
func normalizedAddressList(csv as string) {
    def parts as list of string init strings.split($csv, ",");
    def out as list of string init [];
    for (def part in $parts) {
        def p as string init strings.trim($part);
        if ($p == "") {
            raiseError("the server list \"" + $csv + "\" must not contain empty entries");
        }
        ensureIpAddress($p);
        $out[] = $p;
    }
    if (len($out) == 0) {
        raiseError("the server list must contain at least one address");
    }
    return strings.join($out, ",");
}

/**
 * Test whether a string is a plain IP address (v4 or v6).
 *
 * @param value {string} the candidate
 * @return {bool} true when it parses as an address
 * @internal
 */
func isIpAddress(value as string) {
    try {
        ipnet.parseAddress(strings.trim($value));
    } catch (e) {
        return false;
    }
    return true;
}

/**
 * Read an integer property from a reply row; absent or unparseable
 * counts as 0.
 *
 * @param row {map of string to string} a reply row
 * @param key {string} property name
 * @return {int} the value or 0
 * @internal
 */
func rowInt(row as map of string to string, key as string) {
    def v as string init rowValue($row, $key);
    if ($v == "") {
        return 0;
    }
    try {
        return convert.toInt($v);
    } catch (e) {
        return 0;
    }
}

/**
 * Validate a ping / bandwidth-test target host.
 *
 * IP addresses and DNS names are both fine (the router resolves), so
 * only the obviously broken is rejected.
 *
 * @param host {string} the candidate (already trimmed)
 * @throws {Error} kind "routeros" on an empty or space-containing host
 * @internal
 */
func ensureHost(host as string) {
    if ($host == "") {
        raiseError("the target host must not be empty");
    }
    if (strings.contains($host, " ")) {
        raiseError("the target host must not contain spaces");
    }
}

/**
 * Resolve a comment to the id of the item carrying it, under any path.
 *
 * Comments are the deck's stable handle on the ordered tables (a rule's
 * id changes when it is re-added, its comment does not), so the
 * *ByComment verbs all funnel through here.
 *
 * @param c {Client}       an open client
 * @param path {string}    the list path to search
 * @param comment {string} the comment to look for
 * @param what {string}    noun for the error message (e.g. "firewall rule")
 * @return {string} the item id
 * @throws {Error} kind "routeros" when nothing carries that comment
 * @internal
 */
func requiredIdByComment(c as Client, path as string, comment as string, what as string) {
    def rows as list of map of string to string init getAll($c, $path);
    def row as map of string to string init findRowByField($rows, "comment", $comment);
    if (len($row) == 0) {
        raiseError("no " + $what + " with the comment \"" + $comment + "\" was found");
    }
    return rowValue($row, ".id");
}

/**
 * Turn command logging on or off.
 *
 * When on, every command is printed to stdout before it is sent, with
 * credentials shown as `<redacted>`. Returns a copy: keep it
 * (`$c = mt.setVerbose($c, true);`), the argument is unchanged.
 * `MT_VERBOSE` (`1`, `yes`, `true`, `on`) seeds the flag at connect time.
 *
 * @param c {Client}     an open client
 * @param enabled {bool} print commands
 * @return {Client} a copy of the client with the flag set
 * @example
 *   def c as mt.Client init mt.connect($host, $user, $password);
 *   $c = mt.setVerbose($c, true);
 *   mt.addBridge($c, "brlan");     # prints: mt> /interface/bridge/add name=brlan
 */
export func setVerbose(c as Client, enabled as bool) {
    return Client{session: $c.session, user: $c.user, verbose: $enabled};
}

/**
 * Whether the client logs the commands it sends.
 *
 * @param c {Client} an open client
 * @return {bool} true when command logging is on
 */
export func isVerbose(c as Client) {
    return $c.verbose;
}

/**
 * Send a command that returns the `!done` `=ret=` value (add / set /
 * remove / any action), logging it first when the client is verbose.
 *
 * Every write in the module funnels through here, so turning logging on
 * covers all of them - the topic files never reach for `mikrotik.run`
 * themselves.
 *
 * @param c {Client}       an open client
 * @param command {string} the full RouterOS command path
 * @param attrs {map of string to string} the `=key=value` attributes
 * @return {string} the `=ret=` value the router replied with
 * @internal
 */
func apiRun(c as Client, command as string, attrs as map of string to string) {
    logCommand($c, $command, $attrs);
    return mikrotik.run($c.session, $command, $attrs);
}

/**
 * Send a command that returns reply rows, logging it first when the
 * client is verbose.
 *
 * @param c {Client}       an open client
 * @param command {string} the full RouterOS command path
 * @param attrs {map of string to string} the `=key=value` attributes
 * @return {list of map of string to string} the `!re` rows
 * @internal
 */
func apiTalk(c as Client, command as string, attrs as map of string to string) {
    logCommand($c, $command, $attrs);
    def rows as list of map of string to string init mikrotik.talk($c.session, $command, $attrs);
    logRows($c, $rows);
    return $rows;
}

/**
 * Read a whole list path, logging it first when the client is verbose.
 *
 * @param c {Client}    an open client
 * @param path {string} the normalized list path
 * @return {list of map of string to string} the rows
 * @internal
 */
func apiPrint(c as Client, path as string) {
    def none as map of string to string init {};
    logCommand($c, $path + "/print", $none);
    def rows as list of map of string to string init mikrotik.print($c.session, $path);
    logRows($c, $rows);
    return $rows;
}

/**
 * Read a list path filtered by RouterOS query words, logging it first
 * when the client is verbose.
 *
 * @param c {Client}       an open client
 * @param path {string}    the normalized list path
 * @param queries {list of string} the raw `?...` query words
 * @return {list of map of string to string} the matching rows
 * @internal
 */
func apiPrintWhere(c as Client, path as string, queries as list of string) {
    if ($c.verbose) {
        io.printf("mt> %s/print%s\n", $path, formatQueries($queries));
    }
    def rows as list of map of string to string init mikrotik.printWhere(
        $c.session,
        $path,
        $queries);
    logRows($c, $rows);
    return $rows;
}

/**
 * Print one outgoing command, when the client is verbose.
 *
 * @param c {Client}       an open client
 * @param command {string} the command path
 * @param attrs {map of string to string} its attributes
 * @internal
 */
func logCommand(c as Client, command as string, attrs as map of string to string) {
    if ($c.verbose) {
        io.printf("mt> %s%s\n", $command, formatAttrs($attrs));
    }
}

/**
 * Print how many rows a read returned, when the client is verbose.
 *
 * @param c {Client}    an open client
 * @param rows {list of map of string to string} the reply rows
 * @internal
 */
func logRows(c as Client, rows as list of map of string to string) {
    if ($c.verbose) {
        if (len($rows) == 1) {
            io.printf("mt< 1 row\n");
        } else {
            io.printf("mt< %d rows\n", len($rows));
        }
    }
}

/**
 * Render attributes as ` key=value` pairs, secrets replaced.
 *
 * Insertion order is preserved, so the log shows the attributes in the
 * order they go on the wire.
 *
 * @param attrs {map of string to string} the attributes
 * @return {string} the rendered suffix, "" when there are none
 * @internal
 */
func formatAttrs(attrs as map of string to string) {
    def out as string init "";
    def names as list of string init maps.keys($attrs);
    for (def key in $names) {
        $out = $out + " " + $key + "=" + loggedValue($key, $attrs[$key]);
    }
    return $out;
}

/**
 * Render RouterOS query words for the log.
 *
 * @param queries {list of string} the raw `?...` words
 * @return {string} the rendered suffix, "" when there are none
 * @internal
 */
func formatQueries(queries as list of string) {
    def out as string init "";
    for (def q in $queries) {
        $out = $out + " " + $q;
    }
    return $out;
}

/**
 * The value to print for an attribute: the value itself, or a
 * placeholder when the key carries a secret.
 *
 * @param key {string}   the attribute name
 * @param value {string} the attribute value
 * @return {string} what the log should show
 * @internal
 */
func loggedValue(key as string, value as string) {
    if (isSecretKey($key)) {
        return "<redacted>";
    }
    return $value;
}

/**
 * Whether an attribute name carries a credential.
 *
 * Verbose mode prints what goes on the wire, and what goes on the wire
 * includes SMTP passwords, WPA keys, IPsec and PPP secrets, and
 * WireGuard private keys - so those values are never printed. Matched
 * narrowly on purpose: `public-key` is public, `key-usage` is a
 * certificate flag, and `passive` / `passthrough` merely start with the
 * same letters, so none of them are redacted.
 *
 * @param key {string} the attribute name
 * @return {bool} true when the value must not be printed
 * @internal
 */
func isSecretKey(key as string) {
    if ($key == "password" or $key == "secret" or $key == "passphrase") {
        return true;
    }
    if ($key == "private-key" or strings.endsWith($key, "-private-key")) {
        return true;
    }
    if (strings.endsWith($key, "-password") or strings.endsWith($key, "-secret")) {
        return true;
    }
    if (strings.endsWith($key, ".passphrase") or strings.endsWith($key, "-passphrase")) {
        return true;
    }
    return strings.contains($key, "pre-shared-key");
}

/**
 * Read the initial verbose flag from the environment.
 *
 * @return {bool} true when MT_VERBOSE is set to an affirmative value
 * @internal
 */
func verboseFromEnv() {
    return truthyWord(os.getEnv("MT_VERBOSE"));
}

/**
 * Read an environment-style flag: is this string an affirmative?
 *
 * Case- and space-insensitive; anything unrecognised (including "" for
 * an unset variable) is false, so a stray value never silently turns
 * logging on.
 *
 * @param raw {string} the raw value
 * @return {bool} true for "1" / "yes" / "true" / "on"
 * @internal
 */
func truthyWord(raw as string) {
    def v as string init strings.lower(strings.trim($raw));
    return $v == "1" or $v == "yes" or $v == "true" or $v == "on";
}
