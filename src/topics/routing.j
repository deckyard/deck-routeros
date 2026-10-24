# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - static routes.
# Spliced into routeros.j via include - not a standalone module.

/**
 * RouterOS API path of the route list.
 *
 * Static routes live under "/ip/route"; RouterOS's "/routing" menu holds
 * the dynamic protocols (OSPF, BGP) and their filters.
 */
export def const ROUTE_PATH as string init "/ip/route";

/** The destination that matches everything: the default route. */
export def const DEFAULT_ROUTE as string init "0.0.0.0/0";

/**
 * RouterOS API path of the policy routing rules (RouterOS v7).
 *
 * RouterOS 6 keeps them under "/ip/route/rule"; use the generic verbs
 * there.
 */
export def const ROUTING_RULE_PATH as string init "/routing/rule";

/** RouterOS API path of the routing tables (RouterOS v7). */
export def const ROUTING_TABLE_PATH as string init "/routing/table";

/**
 * One policy routing rule: which traffic looks routes up in which table.
 *
 * @field id {string}            internal RouterOS id
 * @field srcAddress {string}    matched source, "" for any
 * @field dstAddress {string}    matched destination, "" for any
 * @field interfaceName {string} matched incoming interface, "" for any
 * @field action {string}        e.g. "lookup" (falls back to main) or
 *                               "lookup-only-in-table" (no fallback)
 * @field table {string}         the routing table consulted
 * @field disabled {bool}      true when switched off
 * @field comment {string}       free-text comment, "" when unset
 */
export def struct RoutingRule {
    id as string,
    srcAddress as string,
    dstAddress as string,
    interfaceName as string,
    action as string,
    table as string,
    disabled as bool,
    comment as string
};

/**
 * One route: the next hop for a destination network.
 *
 * @field id {string}           internal RouterOS id
 * @field dstAddress {string}   destination network in CIDR; "0.0.0.0/0" is the default route
 * @field gateway {string}      next hop, an IP address or an interface name
 * @field distance {string}     preference, lower wins (RouterOS default "1")
 * @field routingTable {string} routing table holding the route, normally "main"
 * @field active {bool}       true when the route is currently usable
 * @field dynamic {bool}      true when a protocol or service created it;
 *                              such routes cannot be removed by hand
 * @field disabled {bool}     true when the route is switched off
 * @field comment {string}      free-text comment, "" when unset
 */
export def struct Route {
    id as string,
    dstAddress as string,
    gateway as string,
    distance as string,
    routingTable as string,
    active as bool,
    dynamic as bool,
    disabled as bool,
    comment as string
};

/**
 * List every route: static, connected and dynamic.
 *
 * Filter on `dynamic` to keep only the static ones.
 *
 * @param c {Client} an open client
 * @return {list of Route} all routes
 */
export func routes(c as Client) {
    def rows as list of map of string to string init getAll($c, ROUTE_PATH);
    def out as list of Route init [];
    for (def row in $rows) {
        $out[] = routeFromRow($row);
    }
    return $out;
}

/**
 * Add a static route to a destination network via a next hop.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} destination network in CIDR (e.g. "10.20.0.0/16")
 * @param gateway {string}    next hop: the neighbouring router's IP address,
 *                            or an interface name on point-to-point links
 * @param comment {string}    comment, "" for none
 * @return {string} the RouterOS id of the new route
 * @throws {Error} kind "routeros" on a destination that is not CIDR, an
 *                 empty gateway, or a gateway that is neither an IP address
 *                 nor an interface on the router
 * @example
 *   mt.addRoute($c, "10.20.0.0/16", "192.168.88.254", "to branch office");
 */
export func addRoute(c as Client, dstAddress as string, gateway as string, comment as string) {
    return routeAdd($c, $dstAddress, $gateway, 0, $comment);
}

/**
 * Add a static route with an explicit distance.
 *
 * Lower distance wins; RouterOS defaults a static route to 1. A second
 * route to the same destination with a higher distance is a backup that
 * takes over when the preferred one becomes inactive.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} destination network in CIDR
 * @param gateway {string}    next hop, IP address or interface name
 * @param distance {int}   route preference, 1-255
 * @param comment {string}    comment, "" for none
 * @return {string} the RouterOS id of the new route
 * @throws {Error} kind "routeros" on a distance outside 1-255, or the
 *                 destination and gateway errors of `addRoute`
 */
export func addRouteWithDistance(
    c as Client,
    dstAddress as string,
    gateway as string,
    distance as int,
    comment as string) {
    ensureDistance($distance);
    return routeAdd($c, $dstAddress, $gateway, $distance, $comment);
}

/**
 * Add the default route (`DEFAULT_ROUTE`, "0.0.0.0/0"), used by all
 * traffic without a more specific route. The gateway is normally the
 * ISP's router.
 *
 * @param c {Client}       an open client
 * @param gateway {string} next hop, IP address or interface name
 * @param comment {string} comment, "" for none
 * @return {string} the RouterOS id of the new route
 * @throws {Error} kind "routeros" on an empty gateway, or one that is
 *                 neither an IP address nor an interface on the router
 */
export func addDefaultRoute(c as Client, gateway as string, comment as string) {
    return routeAdd($c, DEFAULT_ROUTE, $gateway, 0, $comment);
}

/**
 * Remove the static route to a destination.
 *
 * Dynamic routes are skipped. With several static routes to the same
 * destination (e.g. a backup with a higher distance) the first one listed
 * is removed; for another, pass its id from `routes` to the generic
 * `remove`.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} destination network, exactly as the router lists it
 * @throws {Error} kind "routeros" when no static route to it exists
 */
export func removeRoute(c as Client, dstAddress as string) {
    remove($c, ROUTE_PATH, requiredStaticRouteId($c, $dstAddress));
}

/**
 * Switch the first static route to a destination on.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} destination network, exactly as the router lists it
 * @throws {Error} kind "routeros" when no static route to it exists
 */
export func enableRoute(c as Client, dstAddress as string) {
    enable($c, ROUTE_PATH, requiredStaticRouteId($c, $dstAddress));
}

/**
 * Switch the first static route to a destination off; it is kept but
 * unused until enabled again.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} destination network, exactly as the router lists it
 * @throws {Error} kind "routeros" when no static route to it exists
 */
export func disableRoute(c as Client, dstAddress as string) {
    disable($c, ROUTE_PATH, requiredStaticRouteId($c, $dstAddress));
}

/**
 * Validate a route distance.
 *
 * @param distance {int} the candidate distance
 * @throws {Error} kind "routeros" when outside 1-255
 * @internal
 */
func ensureDistance(distance as int) {
    if ($distance < 1 or $distance > 255) {
        raiseError("the route distance must be between 1 and 255");
    }
}

/**
 * Validate and create a route; distance 0 leaves the router default.
 *
 * A gateway that is not an IP address must name an interface on the
 * router.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} destination network in CIDR
 * @param gateway {string}    next hop, IP address or interface name
 * @param distance {int}   validated distance, or 0 to omit
 * @param comment {string}    comment, "" for none
 * @return {string} the RouterOS id of the new route
 * @throws {Error} kind "routeros" on a malformed destination or gateway
 * @internal
 */
func routeAdd(
    c as Client,
    dstAddress as string,
    gateway as string,
    distance as int,
    comment as string) {
    ensureCidr($dstAddress);
    def gw as string init strings.trim($gateway);
    if ($gw == "") {
        raiseError("the gateway must not be empty");
    }
    if (not isIpAddress($gw)) {
        requiredId($c, INTERFACE_PATH, $gw, "gateway interface");
    }
    def attrs as map of string to string init {"dst-address": $dstAddress, "gateway": $gw};
    if ($distance > 0) {
        $attrs["distance"] = convert.toString($distance);
    }
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, ROUTE_PATH, $attrs);
}

/**
 * Find the first static (non-dynamic) route row to a destination.
 *
 * @param rows {list of map of string to string} "/ip/route/print" rows
 * @param dstAddress {string} the destination network to look for
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func staticRouteRow(rows as list of map of string to string, dstAddress as string) {
    for (def row in $rows) {
        if (rowValue($row, "dst-address") == $dstAddress and not rowBool($row, "dynamic")) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Resolve a destination to the id of its first static route.
 *
 * @param c {Client}          an open client
 * @param dstAddress {string} the destination network
 * @return {string} the route id
 * @throws {Error} kind "routeros" when no static route matches
 * @internal
 */
func requiredStaticRouteId(c as Client, dstAddress as string) {
    def rows as list of map of string to string init getAll($c, ROUTE_PATH);
    def row as map of string to string init staticRouteRow($rows, $dstAddress);
    if (len($row) == 0) {
        raiseError("no static route to \"" + $dstAddress + "\" was found");
    }
    return rowValue($row, ".id");
}

/**
 * Fold a reply row into a Route.
 *
 * @param row {map of string to string} an "/ip/route/print" row
 * @return {Route} the typed route
 * @internal
 */
func routeFromRow(row as map of string to string) {
    return Route{
        id: rowValue($row, ".id"),
        dstAddress: rowValue($row, "dst-address"),
        gateway: rowValue($row, "gateway"),
        distance: rowValue($row, "distance"),
        routingTable: rowValue($row, "routing-table"),
        active: rowBool($row, "active"),
        dynamic: rowBool($row, "dynamic"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * List the policy routing rules.
 *
 * @param c {Client} an open client
 * @return {list of RoutingRule} all rules, in evaluation order
 */
export func routingRules(c as Client) {
    def rows as list of map of string to string init getAll($c, ROUTING_RULE_PATH);
    def out as list of RoutingRule init [];
    for (def row in $rows) {
        $out[] = routingRuleFromRow($row);
    }
    return $out;
}

/**
 * Route a source's traffic through another routing table, falling back
 * to the main table.
 *
 * Adds a policy rule (action "lookup") sending traffic from `srcAddress`
 * to `table`; no packet marking is needed. For matches that need
 * firewall conditions use `markRoutingFor` (mangle). The table is created
 * if missing; give it a default route with the generic `add` on
 * `ROUTE_PATH` and `"routing-table": table`. Destinations the table has
 * no route for fall back to the main table; `useRoutingTableOnly` does
 * not fall back. Idempotent: an existing rule for the same source and
 * table is reused.
 *
 * @param c {Client}          an open client
 * @param srcAddress {string} source, an IP address or CIDR network
 * @param table {string}      routing table to consult
 * @param comment {string}    comment, "" for none
 * @return {string} the RouterOS id of the new or existing rule
 * @throws {Error} kind "routeros" on a bad address, or an empty or spaced
 *                 table name
 * @example
 *   mt.useRoutingTable($c, "10.30.0.0/24", "backupisp", "guests via backup");
 *   mt.add($c, mt.ROUTE_PATH, {"dst-address": "0.0.0.0/0",
 *       "gateway": "198.51.100.1", "routing-table": "backupisp"});
 */
export func useRoutingTable(c as Client, srcAddress as string, table as string, comment as string) {
    return routingRuleAdd($c, $srcAddress, $table, "lookup", $comment);
}

/**
 * Route a source's traffic through another table with no fallback
 * (action "lookup-only-in-table").
 *
 * Destinations the table has no route for are unreachable for that
 * source. Otherwise as `useRoutingTable`.
 *
 * @param c {Client}          an open client
 * @param srcAddress {string} source, an IP address or CIDR network
 * @param table {string}      routing table to consult
 * @param comment {string}    comment, "" for none
 * @return {string} the RouterOS id of the new or existing rule
 * @throws {Error} kind "routeros" on a bad address, or an empty or spaced
 *                 table name
 */
export func useRoutingTableOnly(
    c as Client,
    srcAddress as string,
    table as string,
    comment as string) {
    return routingRuleAdd($c, $srcAddress, $table, "lookup-only-in-table", $comment);
}

/**
 * Remove the policy routing rule sending a source to a table.
 *
 * @param c {Client}          an open client
 * @param srcAddress {string} rule source, as given when it was added
 * @param table {string}      rule table
 * @throws {Error} kind "routeros" when no such rule exists
 */
export func removeRoutingRule(c as Client, srcAddress as string, table as string) {
    def rows as list of map of string to string init getAll($c, ROUTING_RULE_PATH);
    def row as map of string to string init findRoutingRuleRow(
        $rows,
        strings.trim($srcAddress),
        $table);
    if (len($row) == 0) {
        raiseError("no routing rule sends \"" + $srcAddress + "\" to table \"" + $table + "\"");
    }
    remove($c, ROUTING_RULE_PATH, rowValue($row, ".id"));
}

/**
 * Validate and create (or reuse) a policy routing rule.
 *
 * @param c {Client}          an open client
 * @param srcAddress {string} the source (IP or CIDR)
 * @param table {string}      the routing table (created if missing)
 * @param action {string}     "lookup" or "lookup-only-in-table"
 * @param comment {string}    note, "" for none
 * @return {string} the RouterOS id of the rule
 * @throws {Error} kind "routeros" on a bad address or table name
 * @internal
 */
func routingRuleAdd(
    c as Client,
    srcAddress as string,
    table as string,
    action as string,
    comment as string) {
    def src as string init strings.trim($srcAddress);
    if (strings.contains($src, "/")) {
        ensureCidr($src);
    } else {
        ensureIpAddress($src);
    }
    ensureName($table, "routing table");
    ensureRoutingTable($c, $table);
    def rows as list of map of string to string init getAll($c, ROUTING_RULE_PATH);
    def existing as map of string to string init findRoutingRuleRow($rows, $src, $table);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {
        "src-address": $src,
        "action": $action,
        "table": $table
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, ROUTING_RULE_PATH, $attrs);
}

/**
 * Create a routing table if it does not exist ("main" always does).
 *
 * @param c {Client}     an open client
 * @param table {string} the table name
 * @internal
 */
func ensureRoutingTable(c as Client, table as string) {
    if ($table == "main") {
        return;
    }
    if (idByName($c, ROUTING_TABLE_PATH, $table) == "") {
        add($c, ROUTING_TABLE_PATH, {"name": $table, "fib": ""});
    }
}

/**
 * Find the rule matching a source and a table.
 *
 * @param rows {list of map of string to string} "/routing/rule/print" rows
 * @param src {string}   the source address/network
 * @param table {string} the table name
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findRoutingRuleRow(rows as list of map of string to string, src as string, table as string) {
    for (def row in $rows) {
        if (rowValue($row, "src-address") == $src and rowValue($row, "table") == $table) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a reply row into a RoutingRule.
 *
 * @param row {map of string to string} a "/routing/rule/print" row
 * @return {RoutingRule} the typed rule
 * @internal
 */
func routingRuleFromRow(row as map of string to string) {
    return RoutingRule{
        id: rowValue($row, ".id"),
        srcAddress: rowValue($row, "src-address"),
        dstAddress: rowValue($row, "dst-address"),
        interfaceName: rowValue($row, "interface"),
        action: rowValue($row, "action"),
        table: rowValue($row, "table"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
