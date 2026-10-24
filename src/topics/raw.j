# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - firewall raw: drop / notrack before connection tracking.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the firewall raw table. */
export def const RAW_PATH as string init "/ip/firewall/raw";

/**
 * One raw-table rule as read back from the router.
 *
 * Rules are built with the firewall builder (`firewallRule` and the
 * `with*` refiners); this struct is the query result.
 *
 * @field id {string} internal RouterOS id
 * @field chain {string} "prerouting" or "output"
 * @field action {string} "accept", "drop", "notrack", ...
 * @field protocol {string} matched protocol, "" for any
 * @field srcAddress {string} matched source, "" for any
 * @field dstAddress {string} matched destination, "" for any
 * @field srcAddressList {string} source address list, "" for none
 * @field inInterfaceList {string} incoming interface list, "" for none
 * @field comment {string} comment; the *ByComment handle
 * @field disabled {bool} true when switched off
 */
export def struct RawRule {
    id as string,
    chain as string,
    action as string,
    protocol as string,
    srcAddress as string,
    dstAddress as string,
    srcAddressList as string,
    inInterfaceList as string,
    comment as string,
    disabled as bool
};

/**
 * List the firewall raw rules in table order.
 *
 * @param c {Client} an open client
 * @return {list of RawRule} all raw rules
 */
export func rawRules(c as Client) {
    def rows as list of map of string to string init getAll($c, RAW_PATH);
    def out as list of RawRule init [];
    for (def row in $rows) {
        $out[] = rawFromRow($row);
    }
    return $out;
}

/**
 * Append a raw-table rule built with the firewall builder.
 *
 * The raw table runs before connection tracking: the cheapest place to
 * drop spoofed sources, bogons or a flood, and the place to `notrack`
 * traffic that should stay out of the connection table. Raw takes the
 * chains CHAIN_PREROUTING (incoming, the usual one) and CHAIN_OUTPUT and
 * the actions `accept`, `drop` and ACTION_NOTRACK. These limits are not
 * checked locally: a chain or action raw lacks is refused by the router
 * (kind "mikrotik").
 *
 * @param c {Client} an open client
 * @param rule {FirewallRule} the matcher, built with the firewall builder
 * @return {string} id of the new rule
 * @throws {Error} kind "routeros" on an inconsistent rule (e.g. a port
 *                match without a protocol), kind "mikrotik" when the
 *                router refuses it
 * @example
 *   def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_PREROUTING, mt.ACTION_DROP);
 *   $r = mt.withInInterfaceList($r, "WAN");
 *   $r = mt.withSrcAddressList($r, "bogons");
 *   $r = mt.withComment($r, "drop bogons from WAN");
 *   mt.addRawRule($c, $r);
 */
export func addRawRule(c as Client, rule as FirewallRule) {
    return add($c, RAW_PATH, ruleAttrs($rule));
}

/**
 * Append a raw prerouting rule that drops every source on an address
 * list, e.g. bogons or a blocklist.
 *
 * @param c {Client} an open client
 * @param listName {string} address list whose members are dropped
 * @param comment {string} rule handle
 * @return {string} id of the new rule
 * @throws {Error} kind "routeros" on an empty or spaced list name
 * @example
 *   mt.dropRawAddressList($c, "bogons", "drop bogons early");
 */
export func dropRawAddressList(c as Client, listName as string, comment as string) {
    def r as FirewallRule init firewallRule(CHAIN_PREROUTING, ACTION_DROP);
    $r = withSrcAddressList($r, $listName);
    $r = withComment($r, $comment);
    return addRawRule($c, $r);
}

/**
 * Delete a raw rule by id.
 *
 * @param c {Client} an open client
 * @param id {string} rule id
 * @throws {Error} kind "routeros" on an empty id
 */
export func removeRawRule(c as Client, id as string) {
    remove($c, RAW_PATH, $id);
}

/**
 * Delete the raw rule that carries a comment.
 *
 * @param c {Client} an open client
 * @param comment {string} the rule's comment
 * @throws {Error} kind "routeros" when no raw rule carries that comment
 */
export func removeRawRuleByComment(c as Client, comment as string) {
    remove($c, RAW_PATH, rawIdByComment($c, $comment));
}

/**
 * Move a raw rule directly above another one.
 *
 * Order decides inside raw too: a `notrack` above a `drop` spares the
 * connection tracker work the drop would have made pointless.
 *
 * @param c {Client} an open client
 * @param id {string} rule to move
 * @param beforeId {string} rule to land above, "" for the bottom
 * @throws {Error} kind "routeros" on an empty id or a self-move
 */
export func moveRawRule(c as Client, id as string, beforeId as string) {
    moveRule($c, RAW_PATH, $id, $beforeId);
}

/**
 * Move the raw rule carrying one comment above the rule carrying another.
 *
 * @param c {Client} an open client
 * @param comment {string} comment of the rule to move
 * @param beforeComment {string} comment of the rule to land above, "" for
 *        the bottom
 * @throws {Error} kind "routeros" when either comment matches no rule
 */
export func moveRawRuleByComment(c as Client, comment as string, beforeComment as string) {
    def target as string init rawIdByComment($c, $comment);
    def dest as string init "";
    if (strings.trim($beforeComment) != "") {
        $dest = rawIdByComment($c, $beforeComment);
    }
    moveRule($c, RAW_PATH, $target, $dest);
}

/**
 * Resolve a raw rule comment to the rule's id.
 *
 * @param c {Client}       an open client
 * @param comment {string} the rule's comment
 * @return {string} the rule id
 * @throws {Error} kind "routeros" when no raw rule carries that comment
 * @internal
 */
func rawIdByComment(c as Client, comment as string) {
    return requiredIdByComment($c, RAW_PATH, $comment, "raw rule");
}

/**
 * Fold a reply row into a RawRule.
 *
 * @param row {map of string to string} an "/ip/firewall/raw/print" row
 * @return {RawRule} the typed rule
 * @internal
 */
func rawFromRow(row as map of string to string) {
    return RawRule{
        id: rowValue($row, ".id"),
        chain: rowValue($row, "chain"),
        action: rowValue($row, "action"),
        protocol: rowValue($row, "protocol"),
        srcAddress: rowValue($row, "src-address"),
        dstAddress: rowValue($row, "dst-address"),
        srcAddressList: rowValue($row, "src-address-list"),
        inInterfaceList: rowValue($row, "in-interface-list"),
        comment: rowValue($row, "comment"),
        disabled: rowBool($row, "disabled")
    };
}
