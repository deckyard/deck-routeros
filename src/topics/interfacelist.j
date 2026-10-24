# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - interface lists: named groups of interfaces (WAN/LAN/...).
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the interface lists. */
export def const INTERFACE_LIST_PATH as string init "/interface/list";

/** RouterOS API path of the interface-list members. */
export def const INTERFACE_LIST_MEMBER_PATH as string init "/interface/list/member";

/**
 * One interface list: a named group of interfaces.
 *
 * @field id {string}      internal RouterOS id
 * @field name {string}    the list name (e.g. "WAN", "LAN")
 * @field dynamic {bool}  created by the system, not configured
 * @field comment {string} free-text comment, "" when unset
 */
export def struct InterfaceList {
    id as string,
    name as string,
    dynamic as bool,
    comment as string
};

/**
 * List the interface lists, including the built-in "all", "none" and
 * "dynamic".
 *
 * @param c {Client} an open client
 * @return {list of InterfaceList} all lists
 */
export func interfaceLists(c as Client) {
    def rows as list of map of string to string init getAll($c, INTERFACE_LIST_PATH);
    def out as list of InterfaceList init [];
    for (def row in $rows) {
        $out[] = interfaceListFromRow($row);
    }
    return $out;
}

/**
 * Create an interface list.
 *
 * Firewall rules can match a whole list (`withInInterfaceList`,
 * `withOutInterfaceList`), so moving an interface between lists needs no
 * rule edits. The RouterOS v7 default configuration uses "WAN" and "LAN".
 * Idempotent by name: an existing list's id is returned unchanged.
 *
 * @param c {Client}       an open client
 * @param name {string}    list name (e.g. "WAN")
 * @param comment {string} comment, "" for none
 * @return {string} the id of the new or existing list
 * @throws {Error} kind "routeros" on an invalid name
 * @example
 *   mt.addInterfaceList($c, "WAN", "internet-facing ports");
 *   mt.addToInterfaceList($c, "WAN", "ether1");
 *   def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_INPUT, mt.ACTION_DROP);
 *   $r = mt.withInInterfaceList($r, "WAN");
 *   $r = mt.withComment($r, "drop from WAN");
 *   mt.addFirewallRule($c, $r);
 */
export func addInterfaceList(c as Client, name as string, comment as string) {
    ensureName($name, "interface list");
    def existing as string init idByName($c, INTERFACE_LIST_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    def attrs as map of string to string init {"name": $name};
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, INTERFACE_LIST_PATH, $attrs);
}

/**
 * Delete an interface list; RouterOS drops its memberships with it.
 *
 * @param c {Client}    an open client
 * @param name {string} the list name
 * @throws {Error} kind "routeros" when no list has that name
 */
export func removeInterfaceList(c as Client, name as string) {
    remove($c, INTERFACE_LIST_PATH, requiredId($c, INTERFACE_LIST_PATH, $name, "interface list"));
}

/**
 * Name the interfaces in a list.
 *
 * An unknown list gives an empty list, not an error.
 *
 * @param c {Client}        an open client
 * @param listName {string} the list name
 * @return {list of string} member interface names, in router order
 */
export func interfaceListMembers(c as Client, listName as string) {
    def rows as list of map of string to string init getAll($c, INTERFACE_LIST_MEMBER_PATH);
    def out as list of string init [];
    for (def row in $rows) {
        if (rowValue($row, "list") == $listName) {
            $out[] = rowValue($row, "interface");
        }
    }
    return $out;
}

/**
 * Put an interface into a list.
 *
 * Creates the list when missing; the interface must exist. Idempotent:
 * an existing membership's id is returned.
 *
 * @param c {Client}             an open client
 * @param listName {string}      the list (e.g. "WAN")
 * @param interfaceName {string} the interface to add
 * @return {string} the id of the new or existing membership
 * @throws {Error} kind "routeros" on a bad list name or unknown interface
 */
export func addToInterfaceList(c as Client, listName as string, interfaceName as string) {
    ensureName($listName, "interface list");
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    if (idByName($c, INTERFACE_LIST_PATH, $listName) == "") {
        add($c, INTERFACE_LIST_PATH, {"name": $listName});
    }
    def rows as list of map of string to string init getAll($c, INTERFACE_LIST_MEMBER_PATH);
    def existing as map of string to string init memberRow($rows, $listName, $interfaceName);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    return add($c, INTERFACE_LIST_MEMBER_PATH, {"list": $listName, "interface": $interfaceName});
}

/**
 * Remove an interface from a list.
 *
 * @param c {Client}             an open client
 * @param listName {string}      the list
 * @param interfaceName {string} the member interface
 * @throws {Error} kind "routeros" when the interface is not in the list
 */
export func removeFromInterfaceList(c as Client, listName as string, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, INTERFACE_LIST_MEMBER_PATH);
    def row as map of string to string init memberRow($rows, $listName, $interfaceName);
    if (len($row) == 0) {
        raiseError("\"" + $interfaceName + "\" is not a member of the interface list \"" +
            $listName + "\"");
    }
    remove($c, INTERFACE_LIST_MEMBER_PATH, rowValue($row, ".id"));
}

/**
 * Find a membership row by list and interface.
 *
 * @param rows {list of map of string to string} member rows
 * @param listName {string}      the list
 * @param interfaceName {string} the interface
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func memberRow(
    rows as list of map of string to string,
    listName as string,
    interfaceName as string) {
    for (def row in $rows) {
        if (rowValue($row, "list") == $listName and rowValue($row, "interface") == $interfaceName) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a reply row into an InterfaceList.
 *
 * @param row {map of string to string} an "/interface/list/print" row
 * @return {InterfaceList} the typed list
 * @internal
 */
func interfaceListFromRow(row as map of string to string) {
    return InterfaceList{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        dynamic: rowBool($row, "dynamic"),
        comment: rowValue($row, "comment")
    };
}
