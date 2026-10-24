# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - VRRP: two routers, one gateway address, automatic failover.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the VRRP interface list. */
export def const VRRP_PATH as string init "/interface/vrrp";

/**
 * One VRRP instance: this router's share of a redundant gateway.
 *
 * Routers with the same `vrid` on one network share a virtual address;
 * the highest priority is master and answers for it, the others stand by.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          VRRP interface name (e.g. "vrrplan")
 * @field interfaceName {string} underlying interface (the shared network)
 * @field vrid {int}          virtual router id, 1-255, the same on all peers
 * @field priority {int}      priority, 1-254; the highest becomes master
 * @field interval {string}      advertisement interval as reported
 * @field version {int}       VRRP protocol version (2 or 3)
 * @field preemption {bool}    true when a returning higher-priority peer takes over
 * @field running {bool}       true when the instance is active
 * @field backup {bool}        true while standing by
 * @field master {bool}        computed as running and not backup: this
 *                               router answers for the address now
 * @field disabled {bool}      true when the instance is switched off
 * @field comment {string}       free-text comment, "" when unset
 */
export def struct VrrpInterface {
    id as string,
    name as string,
    interfaceName as string,
    vrid as int,
    priority as int,
    interval as string,
    version as int,
    preemption as bool,
    running as bool,
    backup as bool,
    master as bool,
    disabled as bool,
    comment as string
};

/**
 * List every VRRP instance on the router.
 *
 * @param c {Client} an open client
 * @return {list of VrrpInterface} all instances, with master/backup state
 */
export func vrrpInterfaces(c as Client) {
    def rows as list of map of string to string init getAll($c, VRRP_PATH);
    def out as list of VrrpInterface init [];
    for (def row in $rows) {
        $out[] = vrrpFromRow($row);
    }
    return $out;
}

/**
 * Look up a VRRP instance by name.
 *
 * `.master` tells whether this router answers for the shared address now.
 *
 * @param c {Client}    an open client
 * @param name {string} the VRRP interface name
 * @return {VrrpInterface} the instance
 * @throws {Error} kind "routeros" when no VRRP interface has that name
 */
export func vrrpByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, VRRP_PATH, $name);
    if (len($row) == 0) {
        raiseError("the VRRP interface \"" + $name + "\" was not found on the router");
    }
    return vrrpFromRow($row);
}

/**
 * Make this router one half of a redundant gateway.
 *
 * Creates the VRRP instance (`addVrrp`) and puts the shared virtual
 * address on it. Run the same call on the other router with the same
 * `vrid` and `virtualAddress` and a different priority; the higher one
 * is master (e.g. 200 preferred, 100 standby). Clients use the virtual
 * address as their gateway; when the master fails, the standby answers
 * within seconds. Not idempotent: a second call fails on the taken name.
 *
 * @param c {Client}              an open client
 * @param name {string}           VRRP interface name (e.g. "vrrplan")
 * @param interfaceName {string}  interface on the shared network (e.g. "brlan")
 * @param vrid {int}           virtual router id, 1-255, identical on all peers
 * @param priority {int}       priority, 1-254; the highest becomes master
 * @param virtualAddress {string} shared gateway address in CIDR, "/32" by
 *                                convention (e.g. "192.168.88.254/32")
 * @return {string} the RouterOS id of the VRRP interface
 * @throws {Error} kind "routeros" on an address without prefix, the
 *                 `addVrrp` errors
 * @example
 *   # router A (preferred):
 *   mt.setupVrrp($c, "vrrplan", "brlan", 10, 200, "192.168.88.254/32");
 *   # router B (standby): same vrid + address, lower priority
 *   # mt.setupVrrp($cb, "vrrplan", "brlan", 10, 100, "192.168.88.254/32");
 */
export func setupVrrp(
    c as Client,
    name as string,
    interfaceName as string,
    vrid as int,
    priority as int,
    virtualAddress as string) {
    ensureCidr($virtualAddress);
    def id as string init addVrrp($c, $name, $interfaceName, $vrid, $priority);
    add($c, IP_ADDRESS_PATH, {"address": $virtualAddress, "interface": $name});
    return $id;
}

/**
 * Create a VRRP instance without an address; `setupVrrp` adds one too.
 *
 * The same vrid may be reused on a different interface.
 *
 * @param c {Client}             an open client
 * @param name {string}          VRRP interface name
 * @param interfaceName {string} underlying interface
 * @param vrid {int}          virtual router id, 1-255
 * @param priority {int}      priority, 1-254; the highest becomes master
 * @return {string} the RouterOS id of the new instance
 * @throws {Error} kind "routeros" on an empty or spaced name, a vrid
 *                 outside 1-255, a priority outside 1-254, an unknown
 *                 interface, a taken name, or a vrid already used on that
 *                 interface
 */
export func addVrrp(
    c as Client,
    name as string,
    interfaceName as string,
    vrid as int,
    priority as int) {
    ensureName($name, "VRRP interface");
    ensureVrid($vrid);
    ensureVrrpPriority($priority);
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    if (idByName($c, VRRP_PATH, $name) != "") {
        raiseError("the VRRP interface \"" + $name + "\" already exists");
    }
    def rows as list of map of string to string init getAll($c, VRRP_PATH);
    def clash as map of string to string init findVrrpRow($rows, $interfaceName, $vrid);
    if (len($clash) > 0) {
        raiseError("vrid " + convert.toString($vrid) + " on \"" + $interfaceName +
            "\" is already used by \"" + rowValue($clash, "name") + "\"");
    }
    return add(
        $c,
        VRRP_PATH,
        {
            "name": $name,
            "interface": $interfaceName,
            "vrid": convert.toString($vrid),
            "priority": convert.toString($priority)
        });
}

/**
 * Change a VRRP instance's priority.
 *
 * Raise it to make this router take over (with preemption on); lower it
 * to hand the master role away, e.g. before maintenance.
 *
 * @param c {Client}        an open client
 * @param name {string}     VRRP interface name
 * @param priority {int} new priority, 1-254
 * @throws {Error} kind "routeros" on an unknown instance or a priority
 *                 outside 1-254
 */
export func setVrrpPriority(c as Client, name as string, priority as int) {
    ensureVrrpPriority($priority);
    set(
        $c,
        VRRP_PATH,
        requiredId($c, VRRP_PATH, $name, "VRRP interface"),
        {"priority": convert.toString($priority)});
}

/**
 * Delete a VRRP instance and the static addresses on it.
 *
 * The peer router, if any, takes over the shared address.
 *
 * @param c {Client}    an open client
 * @param name {string} VRRP interface name
 * @throws {Error} kind "routeros" when no VRRP interface has that name
 */
export func removeVrrp(c as Client, name as string) {
    def id as string init requiredId($c, VRRP_PATH, $name, "VRRP interface");
    def addrRows as list of map of string to string init getAll($c, IP_ADDRESS_PATH);
    for (def row in $addrRows) {
        if (rowValue($row, "interface") == $name and not rowBool($row, "dynamic")) {
            remove($c, IP_ADDRESS_PATH, rowValue($row, ".id"));
        }
    }
    remove($c, VRRP_PATH, $id);
}

/**
 * Switch a VRRP instance on.
 *
 * @param c {Client}    an open client
 * @param name {string} VRRP interface name
 * @throws {Error} kind "routeros" when no VRRP interface has that name
 */
export func enableVrrp(c as Client, name as string) {
    enable($c, VRRP_PATH, requiredId($c, VRRP_PATH, $name, "VRRP interface"));
}

/**
 * Switch a VRRP instance off; the peer takes over the shared address.
 *
 * @param c {Client}    an open client
 * @param name {string} VRRP interface name
 * @throws {Error} kind "routeros" when no VRRP interface has that name
 */
export func disableVrrp(c as Client, name as string) {
    disable($c, VRRP_PATH, requiredId($c, VRRP_PATH, $name, "VRRP interface"));
}

/**
 * Validate a virtual router id.
 *
 * @param vrid {int} the candidate id
 * @throws {Error} kind "routeros" when outside 1-255
 * @internal
 */
func ensureVrid(vrid as int) {
    if ($vrid < 1 or $vrid > 255) {
        raiseError("the vrid must be between 1 and 255 (and identical on all peers)");
    }
}

/**
 * Validate a VRRP priority.
 *
 * @param priority {int} the candidate priority
 * @throws {Error} kind "routeros" when outside 1-254 (RFC 5798 reserves
 *                 255 for the address owner)
 * @internal
 */
func ensureVrrpPriority(priority as int) {
    if ($priority < 1 or $priority > 254) {
        raiseError("the priority must be between 1 and 254 - the highest peer becomes master");
    }
}

/**
 * Find a VRRP instance using a vrid on an interface.
 *
 * A vrid has to be unique per network segment only, so the same vrid on
 * another interface does not match.
 *
 * @param rows {list of map of string to string} "/interface/vrrp/print" rows
 * @param interfaceName {string} the underlying interface
 * @param vrid {int}          the virtual router id
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findVrrpRow(rows as list of map of string to string, interfaceName as string, vrid as int) {
    for (def row in $rows) {
        if (rowValue($row, "interface") == $interfaceName and rowInt($row, "vrid") == $vrid) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a reply row into a VrrpInterface.
 *
 * `master` is computed here: running and not in backup state.
 *
 * @param row {map of string to string} an "/interface/vrrp/print" row
 * @return {VrrpInterface} the typed instance
 * @internal
 */
func vrrpFromRow(row as map of string to string) {
    def running as bool init rowBool($row, "running");
    def backup as bool init rowBool($row, "backup");
    return VrrpInterface{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        interfaceName: rowValue($row, "interface"),
        vrid: rowInt($row, "vrid"),
        priority: rowInt($row, "priority"),
        interval: rowValue($row, "interval"),
        version: rowInt($row, "version"),
        preemption: rowBool($row, "preemption-mode"),
        running: $running,
        backup: $backup,
        master: $running and not $backup,
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
