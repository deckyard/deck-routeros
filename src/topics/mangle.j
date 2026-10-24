# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - mangle: marking traffic for queues and policy routing.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the firewall mangle-rule list. */
export def const MANGLE_PATH as string init "/ip/firewall/mangle";

/** Chain for traffic as it enters, before the routing decision (mangle and raw). */
export def const CHAIN_PREROUTING as string init "prerouting";

/** Mangle chain for traffic as it leaves, after the routing decision. */
export def const CHAIN_POSTROUTING as string init "postrouting";

/**
 * One mangle rule as read back from the router.
 *
 * `setupPacketMark`, `markRoutingFor` and `clampTcpMss` create the
 * everyday shapes; other rules go through the generic `add` on
 * MANGLE_PATH.
 *
 * @field id {string} internal RouterOS id
 * @field chain {string} "prerouting", "forward", "postrouting", ...
 * @field action {string} "mark-connection", "mark-packet", "mark-routing",
 *        "change-mss", ...
 * @field newConnectionMark {string} connection mark set, "" when none
 * @field newPacketMark {string} packet mark set, "" when none
 * @field newRoutingMark {string} routing mark (table name) set, "" when none
 * @field newMss {string} MSS set by change-mss, "" when none
 * @field connectionMark {string} matched connection mark, "" for any
 * @field packetMark {string} matched packet mark, "" for any
 * @field protocol {string} matched protocol, "" for any
 * @field srcAddress {string} matched source, "" for any
 * @field dstAddress {string} matched destination, "" for any
 * @field dstPort {string} matched destination port(s), "" for any
 * @field inInterface {string} matched incoming interface, "" for any
 * @field outInterface {string} matched outgoing interface, "" for any
 * @field passthrough {bool} true when later rules still see the packet
 * @field disabled {bool} true when the rule is switched off
 * @field comment {string} comment; the handle the setup verbs use
 */
export def struct MangleRule {
    id as string,
    chain as string,
    action as string,
    newConnectionMark as string,
    newPacketMark as string,
    newRoutingMark as string,
    newMss as string,
    connectionMark as string,
    packetMark as string,
    protocol as string,
    srcAddress as string,
    dstAddress as string,
    dstPort as string,
    inInterface as string,
    outInterface as string,
    passthrough as bool,
    disabled as bool,
    comment as string
};

/**
 * List the mangle rules in table order.
 *
 * @param c {Client} an open client
 * @return {list of MangleRule} all mangle rules
 */
export func mangleRules(c as Client) {
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def out as list of MangleRule init [];
    for (def row in $rows) {
        $out[] = mangleFromRow($row);
    }
    return $out;
}

/**
 * Mark a class of traffic with a packet mark, for queues to match.
 *
 * Adds RouterOS's two-rule pattern: new connections matching `matcher`
 * get connection mark `<markName>-conn` (passthrough), and every packet of
 * such a connection gets packet mark `markName`. A queue then matches the
 * mark (a simple queue's `packet-marks`, set with the generic `set`). The
 * matcher's chain is kept (CHAIN_PREROUTING suits queue marks); its
 * action and comment are replaced. The rules are commented
 * "mark: <markName> (connections)" and "mark: <markName> (packets)".
 * Idempotent by mark name: when the packet rule exists, its id is
 * returned and nothing is added.
 *
 * @param c {Client} an open client
 * @param markName {string} packet mark to create, e.g. "voip"
 * @param matcher {FirewallRule} what to mark, built with `firewallRule` and
 *        the `with*` refiners
 * @return {string} id of the packet-marking rule
 * @throws {Error} kind "routeros" on a bad mark name or matcher
 * @example
 *   def m as mt.FirewallRule init mt.firewallRule(mt.CHAIN_PREROUTING, mt.ACTION_ACCEPT);
 *   $m = mt.withProtocol($m, "udp");
 *   $m = mt.withDstPort($m, "5060-5200");
 *   mt.setupPacketMark($c, "voip", $m);
 */
export func setupPacketMark(c as Client, markName as string, matcher as FirewallRule) {
    ensureName($markName, "packet mark");
    def pair as list of map of string to string init packetMarkRuleAttrs($matcher, $markName);
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def existing as map of string to string init findRowByField(
        $rows,
        "comment",
        "mark: " + $markName + " (packets)");
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    add($c, MANGLE_PATH, $pair[0]);
    return add($c, MANGLE_PATH, $pair[1]);
}

/**
 * Remove the two rules `setupPacketMark` created for a mark.
 *
 * Queues that match the mark stop seeing marked packets; they are not
 * changed.
 *
 * @param c {Client} an open client
 * @param markName {string} mark given to `setupPacketMark`
 * @throws {Error} kind "routeros" when no rule of that mark exists
 */
export func removePacketMark(c as Client, markName as string) {
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def found as int init 0;
    for (def row in $rows) {
        def comment as string init rowValue($row, "comment");
        if ($comment == "mark: " + $markName + " (connections)" or $comment == "mark: " +
            $markName + " (packets)") {
            remove($c, MANGLE_PATH, rowValue($row, ".id"));
            $found = $found + 1;
        }
    }
    if ($found == 0) {
        raiseError("no packet mark \"" + $markName +
            "\" was found - was it created with setupPacketMark?");
    }
}

/**
 * Send a source's traffic to another routing table (policy routing).
 *
 * Traffic from `srcAddress` gets routing mark `markName` in prerouting and
 * is looked up in the table of that name instead of `main`, e.g. to send
 * one subnet over a backup uplink. On RouterOS v7 the table must exist
 * (generic `add` on ROUTING_TABLE_PATH with `fib`) and needs its own
 * default route (generic `add` on ROUTE_PATH with "routing-table"). The rule is commented
 * "route mark: <markName> for <srcAddress>"; idempotent by mark and source.
 *
 * @param c {Client} an open client
 * @param markName {string} routing mark, which is the table name
 * @param srcAddress {string} source IP or CIDR network
 * @return {string} id of the new or existing marking rule
 * @throws {Error} kind "routeros" on a bad mark name or address
 */
export func markRoutingFor(c as Client, markName as string, srcAddress as string) {
    ensureName($markName, "routing mark");
    def src as string init strings.trim($srcAddress);
    if (strings.contains($src, "/")) {
        ensureCidr($src);
    } else {
        ensureIpAddress($src);
    }
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def comment as string init "route mark: " + $markName + " for " + $src;
    def existing as map of string to string init findRowByField($rows, "comment", $comment);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    return add($c, MANGLE_PATH, routingMarkAttrs($markName, $src));
}

/**
 * Remove the routing-mark rule `markRoutingFor` created for a source.
 *
 * @param c {Client} an open client
 * @param markName {string} routing mark
 * @param srcAddress {string} source as given to `markRoutingFor`
 * @throws {Error} kind "routeros" when no such rule exists
 */
export func removeRoutingMark(c as Client, markName as string, srcAddress as string) {
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def comment as string init "route mark: " + $markName + " for " + strings.trim($srcAddress);
    def row as map of string to string init findRowByField($rows, "comment", $comment);
    if (len($row) == 0) {
        raiseError("no routing mark \"" + $markName + "\" for \"" + $srcAddress + "\" was found");
    }
    remove($c, MANGLE_PATH, rowValue($row, ".id"));
}

/**
 * Clamp the TCP MSS of connections crossing an interface, both directions.
 *
 * Fixes "ping works, pages half-load" over PPPoE and tunnels: SYN packets
 * in the forward chain get their MSS set to `clamp-to-pmtu`. Adds one rule
 * per direction, commented "mss clamp: <interfaceName> (out)" and
 * "(in)"; a direction that already has its rule is skipped, so the call
 * is idempotent.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} small-MTU interface, e.g. "pppoewan" or a
 *        GRE or EoIP tunnel
 * @throws {Error} kind "routeros" when the interface does not exist
 * @example
 *   mt.clampTcpMss($c, "pppoewan");
 */
export func clampTcpMss(c as Client, interfaceName as string) {
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def directions as list of string init ["out", "in"];
    for (def direction in $directions) {
        def attrs as map of string to string init mssClampAttrs($interfaceName, $direction);
        def existing as map of string to string init findRowByField(
            $rows,
            "comment",
            $attrs["comment"]);
        if (len($existing) == 0) {
            add($c, MANGLE_PATH, $attrs);
        }
    }
}

/**
 * Remove both MSS clamp rules from an interface.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} interface the clamp was set on
 * @throws {Error} kind "routeros" when no clamp rule exists there
 */
export func removeTcpMssClamp(c as Client, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, MANGLE_PATH);
    def found as int init 0;
    for (def row in $rows) {
        def comment as string init rowValue($row, "comment");
        if ($comment == "mss clamp: " + $interfaceName + " (out)" or $comment == "mss clamp: " +
            $interfaceName + " (in)") {
            remove($c, MANGLE_PATH, rowValue($row, ".id"));
            $found = $found + 1;
        }
    }
    if ($found == 0) {
        raiseError("no MSS clamp on \"" + $interfaceName + "\" was found");
    }
}

/**
 * Build the canonical mark-connection / mark-packet attribute pair
 * from a matcher rule.
 *
 * The matcher's chain is kept; its action is replaced. The connection
 * rule marks only new connections (efficient) and passes through; the
 * packet rule matches the connection mark and stops.
 *
 * @param matcher {FirewallRule}  the match, built with the firewall builder
 * @param markName {string} the packet mark
 * @return {list of map of string to string} two attribute maps:
 *         the connection rule, then the packet rule
 * @internal
 */
func packetMarkRuleAttrs(matcher as FirewallRule, markName as string) {
    def connName as string init $markName + "-conn";
    def connAttrs as map of string to string init ruleAttrs($matcher);
    $connAttrs["action"] = "mark-connection";
    $connAttrs["new-connection-mark"] = $connName;
    $connAttrs["connection-state"] = "new";
    $connAttrs["passthrough"] = "yes";
    $connAttrs["comment"] = "mark: " + $markName + " (connections)";
    def pktAttrs as map of string to string init {
        "chain": $connAttrs["chain"],
        "action": "mark-packet",
        "connection-mark": $connName,
        "new-packet-mark": $markName,
        "passthrough": "no",
        "comment": "mark: " + $markName + " (packets)"
    };
    def out as list of map of string to string init [];
    $out[] = $connAttrs;
    $out[] = $pktAttrs;
    return $out;
}

/**
 * Build the mark-routing attributes for a source.
 *
 * @param markName {string} the routing mark / table
 * @param src {string}      the validated source (IP or CIDR)
 * @return {map of string to string} the rule attributes
 * @internal
 */
func routingMarkAttrs(markName as string, src as string) {
    return {
        "chain": CHAIN_PREROUTING,
        "action": "mark-routing",
        "src-address": $src,
        "new-routing-mark": $markName,
        "passthrough": "yes",
        "comment": "route mark: " + $markName + " for " + $src
    };
}

/**
 * Build the change-mss attributes for one direction of an interface.
 *
 * @param interfaceName {string} the small-MTU interface
 * @param direction {string}     "out" or "in"
 * @return {map of string to string} the rule attributes
 * @internal
 */
func mssClampAttrs(interfaceName as string, direction as string) {
    def attrs as map of string to string init {
        "chain": "forward",
        "action": "change-mss",
        "protocol": "tcp",
        "tcp-flags": "syn",
        "new-mss": "clamp-to-pmtu",
        "passthrough": "yes",
        "comment": "mss clamp: " + $interfaceName + " (" + $direction + ")"
    };
    if ($direction == "out") {
        $attrs["out-interface"] = $interfaceName;
    } else {
        $attrs["in-interface"] = $interfaceName;
    }
    return $attrs;
}

/**
 * Fold a reply row into a MangleRule.
 *
 * @param row {map of string to string} an "/ip/firewall/mangle/print" row
 * @return {MangleRule} the typed rule
 * @internal
 */
func mangleFromRow(row as map of string to string) {
    return MangleRule{
        id: rowValue($row, ".id"),
        chain: rowValue($row, "chain"),
        action: rowValue($row, "action"),
        newConnectionMark: rowValue($row, "new-connection-mark"),
        newPacketMark: rowValue($row, "new-packet-mark"),
        newRoutingMark: rowValue($row, "new-routing-mark"),
        newMss: rowValue($row, "new-mss"),
        connectionMark: rowValue($row, "connection-mark"),
        packetMark: rowValue($row, "packet-mark"),
        protocol: rowValue($row, "protocol"),
        srcAddress: rowValue($row, "src-address"),
        dstAddress: rowValue($row, "dst-address"),
        dstPort: rowValue($row, "dst-port"),
        inInterface: rowValue($row, "in-interface"),
        outInterface: rowValue($row, "out-interface"),
        passthrough: rowBool($row, "passthrough"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Move a mangle rule directly above another one.
 *
 * Order decides which mark sticks: once a rule without passthrough marks
 * a packet, later rules never see it.
 *
 * @param c {Client} an open client
 * @param id {string} rule to move
 * @param beforeId {string} rule to land above, "" for the bottom
 * @throws {Error} kind "routeros" on an empty id or a self-move
 */
export func moveMangleRule(c as Client, id as string, beforeId as string) {
    moveRule($c, MANGLE_PATH, $id, $beforeId);
}

/**
 * Move the mangle rule carrying one comment above the rule carrying
 * another.
 *
 * @param c {Client} an open client
 * @param comment {string} comment of the rule to move
 * @param beforeComment {string} comment of the rule to land above, "" for
 *        the bottom
 * @throws {Error} kind "routeros" when either comment matches no rule
 */
export func moveMangleRuleByComment(c as Client, comment as string, beforeComment as string) {
    def target as string init mangleIdByComment($c, $comment);
    def dest as string init "";
    if (strings.trim($beforeComment) != "") {
        $dest = mangleIdByComment($c, $beforeComment);
    }
    moveRule($c, MANGLE_PATH, $target, $dest);
}

/**
 * Resolve a mangle rule comment to the rule's id.
 *
 * @param c {Client}       an open client
 * @param comment {string} the rule's comment
 * @return {string} the rule id
 * @throws {Error} kind "routeros" when no mangle rule carries that comment
 * @internal
 */
func mangleIdByComment(c as Client, comment as string) {
    return requiredIdByComment($c, MANGLE_PATH, $comment, "mangle rule");
}
