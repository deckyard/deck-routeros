# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - firewall NAT: masquerade and port forwarding.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the firewall NAT-rule list. */
export def const NAT_PATH as string init "/ip/firewall/nat";

/** NAT chain that rewrites the source of outgoing traffic. */
export def const CHAIN_SRCNAT as string init "srcnat";

/** NAT chain that rewrites the destination of incoming traffic. */
export def const CHAIN_DSTNAT as string init "dstnat";

/** NAT action that replaces the source with the out-interface's address. */
export def const ACTION_MASQUERADE as string init "masquerade";

/** NAT action that redirects traffic to another address and port. */
export def const ACTION_DST_NAT as string init "dst-nat";

/**
 * One firewall NAT rule as read back from the router.
 *
 * `addMasquerade` and `forwardPort` create the two everyday kinds; other
 * rules go through the generic `add` on NAT_PATH.
 *
 * @field id {string} internal RouterOS id
 * @field chain {string} "srcnat" (outgoing) or "dstnat" (incoming)
 * @field action {string} "masquerade", "dst-nat", ...
 * @field protocol {string} matched IP protocol, "" for any
 * @field srcAddress {string} matched source address or network, "" for any
 * @field dstAddress {string} matched destination address or network, "" for any
 * @field dstPort {string} matched destination port(s), "" for any
 * @field toAddresses {string} dst-nat target address
 * @field toPorts {string} dst-nat target port
 * @field inInterface {string} incoming interface match, "" for any
 * @field outInterface {string} outgoing interface match, "" for any
 * @field comment {string} comment; the *ByComment handle
 * @field disabled {bool} true when the rule is switched off
 */
export def struct NatRule {
    id as string,
    chain as string,
    action as string,
    protocol as string,
    srcAddress as string,
    dstAddress as string,
    dstPort as string,
    toAddresses as string,
    toPorts as string,
    inInterface as string,
    outInterface as string,
    comment as string,
    disabled as bool
};

/**
 * List the firewall NAT rules in table order.
 *
 * @param c {Client} an open client
 * @return {list of NatRule} all NAT rules
 */
export func natRules(c as Client) {
    def rows as list of map of string to string init getAll($c, NAT_PATH);
    def out as list of NatRule init [];
    for (def row in $rows) {
        $out[] = natFromRow($row);
    }
    return $out;
}

/**
 * Masquerade traffic leaving through an interface, so the LAN reaches the
 * internet with the router's address.
 *
 * Idempotent: when a srcnat masquerade rule for that out-interface
 * exists, its id is returned and `comment` is ignored.
 *
 * @param c {Client} an open client
 * @param outInterface {string} internet-facing interface, e.g. "ether1"
 * @param comment {string} comment for a new rule, "" for none
 * @return {string} id of the new or existing rule
 * @throws {Error} kind "routeros" when the interface does not exist
 * @example
 *   mt.addMasquerade($c, "ether1", "lan to internet");
 */
export func addMasquerade(c as Client, outInterface as string, comment as string) {
    requiredId($c, INTERFACE_PATH, $outInterface, "interface");
    def rows as list of map of string to string init getAll($c, NAT_PATH);
    def existing as map of string to string init findMasqueradeRow($rows, $outInterface);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {
        "chain": CHAIN_SRCNAT,
        "action": ACTION_MASQUERADE,
        "out-interface": $outInterface
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, NAT_PATH, $attrs);
}

/**
 * Forward a port to a LAN host (dst-nat).
 *
 * Traffic arriving on `publicPort` from any interface is redirected to
 * `toAddress`:`toPort`. `forwardPortOn` limits it to the WAN interface,
 * which keeps the rule from catching LAN connections to the router too.
 * The firewall forward chain must also let the traffic through. Not
 * idempotent: each call adds a rule.
 *
 * @param c {Client} an open client
 * @param protocol {string} "tcp" or "udp"
 * @param publicPort {int} outside port, 1-65535
 * @param toAddress {string} LAN address of the service
 * @param toPort {int} port the service listens on, 1-65535
 * @param comment {string} rule handle, e.g. "web server"; "" for none
 * @return {string} id of the new rule
 * @throws {Error} kind "routeros" on a protocol other than tcp/udp, a
 *                port out of range, or a malformed address
 * @example
 *   mt.forwardPort($c, "tcp", 8080, "192.168.88.10", 80, "web server");
 */
export func forwardPort(
    c as Client,
    protocol as string,
    publicPort as int,
    toAddress as string,
    toPort as int,
    comment as string) {
    return natForward($c, "", $protocol, $publicPort, $toAddress, $toPort, $comment);
}

/**
 * Forward a port to a LAN host, for traffic arriving on one interface only.
 *
 * The interface is looked up on the router before the other inputs are
 * checked.
 *
 * @param c {Client} an open client
 * @param inInterface {string} internet-facing interface, e.g. "ether1"
 * @param protocol {string} "tcp" or "udp"
 * @param publicPort {int} outside port, 1-65535
 * @param toAddress {string} LAN address of the service
 * @param toPort {int} port the service listens on, 1-65535
 * @param comment {string} rule handle, "" for none
 * @return {string} id of the new rule
 * @throws {Error} kind "routeros" on an unknown interface or the input
 *                errors of `forwardPort`
 */
export func forwardPortOn(
    c as Client,
    inInterface as string,
    protocol as string,
    publicPort as int,
    toAddress as string,
    toPort as int,
    comment as string) {
    requiredId($c, INTERFACE_PATH, $inInterface, "interface");
    return natForward($c, $inInterface, $protocol, $publicPort, $toAddress, $toPort, $comment);
}

/**
 * Delete a NAT rule by id.
 *
 * @param c {Client} an open client
 * @param id {string} rule id
 * @throws {Error} kind "routeros" on an empty id
 */
export func removeNatRule(c as Client, id as string) {
    remove($c, NAT_PATH, $id);
}

/**
 * Delete the NAT rule that carries a comment.
 *
 * @param c {Client} an open client
 * @param comment {string} the rule's comment
 * @throws {Error} kind "routeros" when no NAT rule carries that comment
 */
export func removeNatRuleByComment(c as Client, comment as string) {
    remove($c, NAT_PATH, natIdByComment($c, $comment));
}

/**
 * Enable the NAT rule that carries a comment.
 *
 * @param c {Client} an open client
 * @param comment {string} the rule's comment
 * @throws {Error} kind "routeros" when no NAT rule carries that comment
 */
export func enableNatRuleByComment(c as Client, comment as string) {
    enable($c, NAT_PATH, natIdByComment($c, $comment));
}

/**
 * Disable the NAT rule that carries a comment, e.g. to close a port
 * forward without deleting it.
 *
 * @param c {Client} an open client
 * @param comment {string} the rule's comment
 * @throws {Error} kind "routeros" when no NAT rule carries that comment
 */
export func disableNatRuleByComment(c as Client, comment as string) {
    disable($c, NAT_PATH, natIdByComment($c, $comment));
}

/**
 * Move a NAT rule directly above another one.
 *
 * The first matching rule translates: a catch-all dst-nat above a port
 * forward shadows it.
 *
 * @param c {Client} an open client
 * @param id {string} rule to move
 * @param beforeId {string} rule to land above, "" for the bottom
 * @throws {Error} kind "routeros" on an empty id or a self-move
 */
export func moveNatRule(c as Client, id as string, beforeId as string) {
    moveRule($c, NAT_PATH, $id, $beforeId);
}

/**
 * Move the NAT rule carrying one comment above the rule carrying another.
 *
 * @param c {Client} an open client
 * @param comment {string} comment of the rule to move
 * @param beforeComment {string} comment of the rule to land above, "" for
 *        the bottom
 * @throws {Error} kind "routeros" when either comment matches no rule
 * @example
 *   mt.moveNatRuleByComment($c, "web server", "masquerade out");
 */
export func moveNatRuleByComment(c as Client, comment as string, beforeComment as string) {
    def target as string init natIdByComment($c, $comment);
    def dest as string init "";
    if (strings.trim($beforeComment) != "") {
        $dest = natIdByComment($c, $beforeComment);
    }
    moveRule($c, NAT_PATH, $target, $dest);
}

/**
 * Validate a port-forward protocol: dst-nat needs tcp or udp.
 *
 * @param protocol {string} the candidate
 * @throws {Error} kind "routeros" on anything but "tcp" / "udp"
 * @internal
 */
func ensureForwardProtocol(protocol as string) {
    if ($protocol != "tcp" and $protocol != "udp") {
        raiseError("port forwarding needs protocol \"tcp\" or \"udp\", not \"" + $protocol + "\"");
    }
}

/**
 * Find an existing masquerade rule for an outgoing interface.
 *
 * @param rows {list of map of string to string} "/ip/firewall/nat/print" rows
 * @param outInterface {string} the interface to look for
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findMasqueradeRow(rows as list of map of string to string, outInterface as string) {
    for (def row in $rows) {
        if (rowValue($row, "chain") == CHAIN_SRCNAT and
            rowValue($row, "action") == ACTION_MASQUERADE and
            rowValue($row, "out-interface") == $outInterface) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Validate and create a dst-nat port forward; empty inInterface omits
 * the interface match.
 *
 * @param c {Client}           an open client
 * @param inInterface {string} interface match, "" for any
 * @param protocol {string}    "tcp" or "udp"
 * @param publicPort {int}  outside port
 * @param toAddress {string}   inside address
 * @param toPort {int}      inside port
 * @param comment {string}     friendly handle, "" for none
 * @return {string} the RouterOS id of the new rule
 * @throws {Error} kind "routeros" on bad input
 * @internal
 */
func natForward(
    c as Client,
    inInterface as string,
    protocol as string,
    publicPort as int,
    toAddress as string,
    toPort as int,
    comment as string) {
    ensureForwardProtocol($protocol);
    ensurePort($publicPort);
    ensurePort($toPort);
    ensureIpAddress($toAddress);
    def attrs as map of string to string init {
        "chain": CHAIN_DSTNAT,
        "action": ACTION_DST_NAT,
        "protocol": $protocol,
        "dst-port": convert.toString($publicPort),
        "to-addresses": strings.trim($toAddress),
        "to-ports": convert.toString($toPort)
    };
    if ($inInterface != "") {
        $attrs["in-interface"] = $inInterface;
    }
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, NAT_PATH, $attrs);
}

/**
 * Resolve a NAT rule comment to the rule's id.
 *
 * @param c {Client}       an open client
 * @param comment {string} the rule's comment
 * @return {string} the rule id
 * @throws {Error} kind "routeros" when no NAT rule carries that comment
 * @internal
 */
func natIdByComment(c as Client, comment as string) {
    return requiredIdByComment($c, NAT_PATH, $comment, "NAT rule");
}

/**
 * Fold a reply row into a NatRule.
 *
 * @param row {map of string to string} an "/ip/firewall/nat/print" row
 * @return {NatRule} the typed rule
 * @internal
 */
func natFromRow(row as map of string to string) {
    return NatRule{
        id: rowValue($row, ".id"),
        chain: rowValue($row, "chain"),
        action: rowValue($row, "action"),
        protocol: rowValue($row, "protocol"),
        srcAddress: rowValue($row, "src-address"),
        dstAddress: rowValue($row, "dst-address"),
        dstPort: rowValue($row, "dst-port"),
        toAddresses: rowValue($row, "to-addresses"),
        toPorts: rowValue($row, "to-ports"),
        inInterface: rowValue($row, "in-interface"),
        outInterface: rowValue($row, "out-interface"),
        comment: rowValue($row, "comment"),
        disabled: rowBool($row, "disabled")
    };
}
