# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - UPnP: let LAN devices open their own port forwards.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the UPnP settings. */
export def const UPNP_PATH as string init "/ip/upnp";

/** RouterOS API path of the UPnP per-interface roles. */
export def const UPNP_INTERFACES_PATH as string init "/ip/upnp/interfaces";

def const UPNP_ROLES as list of string init ["internal", "external"];

/**
 * The UPnP service settings.
 *
 * @field enabled {bool} true when UPnP is running
 */
export def struct UpnpSettings {
    enabled as bool
};

/**
 * One interface's UPnP role.
 *
 * @field id {string}            internal RouterOS id
 * @field interfaceName {string} the interface
 * @field role {string}          "internal" (LAN side) or "external" (WAN side)
 * @field disabled {bool}      true when switched off
 */
export def struct UpnpInterface {
    id as string,
    interfaceName as string,
    role as string,
    disabled as bool
};

/**
 * Read the UPnP settings.
 *
 * @param c {Client} an open client
 * @return {UpnpSettings} the service state
 */
export func upnpStatus(c as Client) {
    return upnpFromRow(singleRow($c, UPNP_PATH));
}

/**
 * List the interfaces' UPnP roles.
 *
 * @param c {Client} an open client
 * @return {list of UpnpInterface} the interfaces that have a role
 */
export func upnpInterfaces(c as Client) {
    def rows as list of map of string to string init getAll($c, UPNP_INTERFACES_PATH);
    def out as list of UpnpInterface init [];
    for (def row in $rows) {
        $out[] = upnpInterfaceFromRow($row);
    }
    return $out;
}

/**
 * Turn UPnP on.
 *
 * Any device on an `internal` interface can then open port forwards from
 * the internet to itself, with no NAT rule written by you. Do not enable
 * it on a guest or untrusted network. UPnP does nothing until
 * `setUpnpInterface` has marked one `internal` and one `external`
 * interface.
 *
 * @param c {Client} an open client
 * @example
 *   mt.enableUpnp($c);
 *   mt.setUpnpInterface($c, "ether1", "external");
 *   mt.setUpnpInterface($c, "brlan", "internal");
 */
export func enableUpnp(c as Client) {
    apiRun($c, UPNP_PATH + "/set", {"enabled": "yes"});
}

/**
 * Turn UPnP off.
 *
 * @param c {Client} an open client
 */
export func disableUpnp(c as Client) {
    apiRun($c, UPNP_PATH + "/set", {"enabled": "no"});
}

/**
 * Mark an interface as the internal (LAN) or external (WAN) side for UPnP.
 *
 * Devices on `internal` interfaces may request forwards, which open on
 * the `external` interface. Idempotent: setting an interface again
 * updates its role.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface
 * @param role {string}          "internal" or "external"
 * @return {string} the RouterOS id of the entry
 * @throws {Error} kind "routeros" on a role other than "internal" or "external",
 *                 or an interface the router does not have
 */
export func setUpnpInterface(c as Client, interfaceName as string, role as string) {
    if (not lists.contains(UPNP_ROLES, $role)) {
        raiseError("unknown UPnP role \"" + $role + "\" - use \"internal\" or \"external\"");
    }
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def rows as list of map of string to string init getAll($c, UPNP_INTERFACES_PATH);
    def existing as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($existing) > 0) {
        set($c, UPNP_INTERFACES_PATH, rowValue($existing, ".id"), {"type": $role});
        return rowValue($existing, ".id");
    }
    return add($c, UPNP_INTERFACES_PATH, {"interface": $interfaceName, "type": $role});
}

/**
 * Remove an interface's UPnP role.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the interface
 * @throws {Error} kind "routeros" when the interface has no UPnP role
 */
export func removeUpnpInterface(c as Client, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, UPNP_INTERFACES_PATH);
    def row as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($row) == 0) {
        raiseError("the interface \"" + $interfaceName + "\" has no UPnP role");
    }
    remove($c, UPNP_INTERFACES_PATH, rowValue($row, ".id"));
}

/**
 * Fold a reply row into the UpnpSettings.
 *
 * @param row {map of string to string} the "/ip/upnp/print" row
 * @return {UpnpSettings} the typed settings
 * @internal
 */
func upnpFromRow(row as map of string to string) {
    return UpnpSettings{enabled: rowBool($row, "enabled")};
}

/**
 * Fold a reply row into an UpnpInterface.
 *
 * @param row {map of string to string} an "/ip/upnp/interfaces/print" row
 * @return {UpnpInterface} the typed interface role
 * @internal
 */
func upnpInterfaceFromRow(row as map of string to string) {
    return UpnpInterface{
        id: rowValue($row, ".id"),
        interfaceName: rowValue($row, "interface"),
        role: rowValue($row, "type"),
        disabled: rowBool($row, "disabled")
    };
}
