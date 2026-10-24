# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - network interfaces.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the interface list. */
export def const INTERFACE_PATH as string init "/interface";

/**
 * One network interface as reported by the router.
 *
 * @field id {string}       internal RouterOS id (e.g. "*1")
 * @field name {string}     interface name (e.g. "ether1")
 * @field kind {string}     interface type (e.g. "ether", "bridge", "wlan")
 * @field mac {string}      hardware MAC address, "" when the router reports none
 * @field running {bool}   link up and passing traffic
 * @field disabled {bool}  administratively off
 * @field comment {string}  free-text comment, "" when unset
 */
export def struct Interface {
    id as string,
    name as string,
    kind as string,
    mac as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * List every network interface on the router.
 *
 * @param c {Client} an open client
 * @return {list of Interface} all interfaces, physical and virtual
 */
export func interfaces(c as Client) {
    def rows as list of map of string to string init getAll($c, INTERFACE_PATH);
    def out as list of Interface init [];
    for (def row in $rows) {
        $out[] = interfaceFromRow($row);
    }
    return $out;
}

/**
 * Look an interface up by name.
 *
 * @param c {Client}    an open client
 * @param name {string} interface name (e.g. "ether1")
 * @return {Interface} the interface
 * @throws {Error} kind "routeros" when no interface has that name
 */
export func interfaceByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, INTERFACE_PATH, $name);
    if (len($row) == 0) {
        raiseError("interface \"" + $name + "\" was not found");
    }
    return interfaceFromRow($row);
}

/**
 * Enable an interface.
 *
 * @param c {Client}    an open client
 * @param name {string} interface name
 * @throws {Error} kind "routeros" when no interface has that name
 */
export func enableInterface(c as Client, name as string) {
    enable($c, INTERFACE_PATH, requiredId($c, INTERFACE_PATH, $name, "interface"));
}

/**
 * Disable an interface; no traffic passes until it is enabled.
 *
 * @param c {Client}    an open client
 * @param name {string} interface name
 * @throws {Error} kind "routeros" when no interface has that name
 */
export func disableInterface(c as Client, name as string) {
    disable($c, INTERFACE_PATH, requiredId($c, INTERFACE_PATH, $name, "interface"));
}

/**
 * Rename an interface.
 *
 * @param c {Client}       an open client
 * @param current {string} current name
 * @param next {string}    new name, non-empty, no spaces
 * @throws {Error} kind "routeros" on a bad new name or an unknown interface
 */
export func renameInterface(c as Client, current as string, next as string) {
    ensureName($next, "interface");
    set($c, INTERFACE_PATH, requiredId($c, INTERFACE_PATH, $current, "interface"), {"name": $next});
}

/**
 * Attach a free-text comment to an interface.
 *
 * @param c {Client}       an open client
 * @param name {string}    interface name
 * @param comment {string} the comment, "" to clear it
 * @throws {Error} kind "routeros" when no interface has that name
 */
export func commentInterface(c as Client, name as string, comment as string) {
    set(
        $c,
        INTERFACE_PATH,
        requiredId($c, INTERFACE_PATH, $name, "interface"),
        {"comment": $comment});
}

/**
 * Fold a reply row into an Interface.
 *
 * @param row {map of string to string} a "/interface/print" row
 * @return {Interface} the typed interface
 * @internal
 */
func interfaceFromRow(row as map of string to string) {
    return Interface{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        kind: rowValue($row, "type"),
        mac: rowValue($row, "mac-address"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
