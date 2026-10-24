# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - bridges and bridge ports.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the bridge list. */
export def const BRIDGE_PATH as string init "/interface/bridge";

/** RouterOS API path of the bridge-port list. */
export def const BRIDGE_PORT_PATH as string init "/interface/bridge/port";

/** RouterOS API path of the bridge VLAN table (VLAN-aware bridging). */
export def const BRIDGE_VLAN_PATH as string init "/interface/bridge/vlan";

/**
 * One bridge VLAN-table entry: which ports carry a VLAN, tagged or not.
 *
 * @field id {string}       internal RouterOS id
 * @field bridge {string}   the bridge this applies to
 * @field vlanIds {string}  VLAN ids as reported (list or range)
 * @field tagged {string}   trunk ports, carrying the VLAN tagged
 * @field untagged {string} access ports, carrying it untagged
 * @field dynamic {bool}    added by RouterOS, not configured
 */
export def struct BridgeVlan {
    id as string,
    bridge as string,
    vlanIds as string,
    tagged as string,
    untagged as string,
    dynamic as bool
};

/**
 * One bridge: a software switch joining its ports into one LAN.
 *
 * @field id {string}       internal RouterOS id
 * @field name {string}     bridge name (e.g. "bridge1")
 * @field mac {string}      MAC address
 * @field running {bool}    bridge is up
 * @field disabled {bool}   administratively off
 * @field comment {string}  free-text comment, "" when unset
 */
export def struct Bridge {
    id as string,
    name as string,
    mac as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * One bridge membership: an interface attached to a bridge.
 *
 * @field id {string}              internal RouterOS id
 * @field bridge {string}          name of the bridge
 * @field interfaceName {string}   name of the member interface
 * @field hardwareOffload {bool} the `hw` flag: the port may forward in
 *                                the switch chip; whether it does depends
 *                                on the bridge config (see `switchHosts`)
 * @field disabled {bool}        membership is off
 */
export def struct BridgePort {
    id as string,
    bridge as string,
    interfaceName as string,
    hardwareOffload as bool,
    disabled as bool
};

/**
 * List the bridges.
 *
 * @param c {Client} an open client
 * @return {list of Bridge} all bridges
 */
export func bridges(c as Client) {
    def rows as list of map of string to string init getAll($c, BRIDGE_PATH);
    def out as list of Bridge init [];
    for (def row in $rows) {
        $out[] = bridgeFromRow($row);
    }
    return $out;
}

/**
 * Create a bridge. Ports added with `addBridgePort` share one LAN.
 *
 * @param c {Client}    an open client
 * @param name {string} name for the new bridge (e.g. "brlan")
 * @return {string} the RouterOS id of the new bridge
 * @throws {Error} kind "routeros" on an invalid name, kind "mikrotik" when the router refuses
 */
export func addBridge(c as Client, name as string) {
    ensureName($name, "bridge");
    return add($c, BRIDGE_PATH, {"name": $name});
}

/**
 * Delete a bridge by name.
 *
 * @param c {Client}    an open client
 * @param name {string} name of the bridge to delete
 * @throws {Error} kind "routeros" when no bridge has that name
 */
export func removeBridge(c as Client, name as string) {
    remove($c, BRIDGE_PATH, requiredId($c, BRIDGE_PATH, $name, "bridge"));
}

/**
 * List the ports of a bridge; an unknown bridge gives an empty list.
 *
 * @param c {Client}          an open client
 * @param bridgeName {string} name of the bridge
 * @return {list of BridgePort} the bridge's member ports
 */
export func bridgePorts(c as Client, bridgeName as string) {
    def rows as list of map of string to string init getAll($c, BRIDGE_PORT_PATH);
    def out as list of BridgePort init [];
    for (def row in $rows) {
        if (rowValue($row, "bridge") == $bridgeName) {
            $out[] = bridgePortFromRow($row);
        }
    }
    return $out;
}

/**
 * Attach an interface to a bridge.
 *
 * @param c {Client}             an open client
 * @param bridgeName {string}    name of the bridge (must exist)
 * @param interfaceName {string} name of the interface to attach
 * @return {string} the RouterOS id of the new bridge port
 * @throws {Error} kind "routeros" when the bridge does not exist or a name is invalid
 */
export func addBridgePort(c as Client, bridgeName as string, interfaceName as string) {
    ensureName($interfaceName, "interface");
    requiredId($c, BRIDGE_PATH, $bridgeName, "bridge");
    return add($c, BRIDGE_PORT_PATH, {"bridge": $bridgeName, "interface": $interfaceName});
}

/**
 * Detach an interface from whatever bridge it is a member of.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} name of the member interface
 * @throws {Error} kind "routeros" when the interface is on no bridge
 */
export func removeBridgePort(c as Client, interfaceName as string) {
    def rows as list of map of string to string init getAll($c, BRIDGE_PORT_PATH);
    def row as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($row) == 0) {
        raiseError("interface \"" + $interfaceName + "\" is not a port of any bridge");
    }
    remove($c, BRIDGE_PORT_PATH, rowValue($row, ".id"));
}

/**
 * Turn hardware switch-chip offload on or off for a bridge port (`hw`).
 *
 * With offload the switch chip forwards the port's frames at wire speed
 * without the CPU. RouterOS turns it on where the hardware allows; turn
 * it off to force software forwarding, e.g. for a software-only feature.
 * On only permits offload: whether the chip forwards also depends on the
 * bridge config; check with `switchHosts`.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the bridge port
 * @param on {bool}              allow offload; false forces software forwarding
 * @throws {Error} kind "routeros" when the interface is on no bridge
 * @example
 *   def ports as list of mt.BridgePort init mt.bridgePorts($c, "brlan");
 *   for (def p in $ports) { io.printf("%s offload=%t\n", $p.interfaceName, $p.hardwareOffload); }
 */
export func setBridgePortHardwareOffload(c as Client, interfaceName as string, on as bool) {
    def rows as list of map of string to string init getAll($c, BRIDGE_PORT_PATH);
    def row as map of string to string init findRowByField($rows, "interface", $interfaceName);
    if (len($row) == 0) {
        raiseError("interface \"" + $interfaceName + "\" is not a port of any bridge");
    }
    set($c, BRIDGE_PORT_PATH, rowValue($row, ".id"), {"hw": boolWord($on)});
}

/**
 * Fold a reply row into a Bridge.
 *
 * @param row {map of string to string} a "/interface/bridge/print" row
 * @return {Bridge} the typed bridge
 * @internal
 */
func bridgeFromRow(row as map of string to string) {
    return Bridge{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        mac: rowValue($row, "mac-address"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * List the bridge VLAN table.
 *
 * @param c {Client} an open client
 * @return {list of BridgeVlan} all VLAN-table entries
 */
export func bridgeVlans(c as Client) {
    def rows as list of map of string to string init getAll($c, BRIDGE_VLAN_PATH);
    def out as list of BridgeVlan init [];
    for (def row in $rows) {
        $out[] = bridgeVlanFromRow($row);
    }
    return $out;
}

/**
 * Turn on VLAN filtering: the bridge tags, untags and filters per port,
 * in hardware where the switch chip supports it, instead of separate
 * `/interface/vlan` interfaces.
 *
 * DANGER: with an incomplete VLAN table, filtering drops untagged
 * traffic, including your management session if it uses this bridge.
 * Declare the VLANs (`addBridgeVlan`) and PVIDs (`setPortPvid`) first,
 * enable filtering last, and keep a second way in.
 *
 * @param c {Client}      an open client
 * @param bridge {string} the bridge name
 * @throws {Error} kind "routeros" when the bridge does not exist
 * @example
 *   mt.addBridgeVlan($c, "brlan", 10, "ether1", "ether2,ether3");
 *   mt.setPortPvid($c, "brlan", "ether2", 10);
 *   mt.enableVlanFiltering($c, "brlan");   # last, once the table is right
 */
export func enableVlanFiltering(c as Client, bridge as string) {
    set($c, BRIDGE_PATH, requiredId($c, BRIDGE_PATH, $bridge, "bridge"), {"vlan-filtering": "yes"});
}

/**
 * Turn VLAN filtering off on a bridge.
 *
 * @param c {Client}      an open client
 * @param bridge {string} the bridge name
 * @throws {Error} kind "routeros" when the bridge does not exist
 */
export func disableVlanFiltering(c as Client, bridge as string) {
    set($c, BRIDGE_PATH, requiredId($c, BRIDGE_PATH, $bridge, "bridge"), {"vlan-filtering": "no"});
}

/**
 * Declare a VLAN on a bridge: which ports carry it, tagged or untagged.
 *
 * Tagged ports are trunks (links to switches, or the bridge itself for
 * the router's own VLAN interface); untagged ports are access ports for
 * end devices and need a matching `pvid`. Idempotent by bridge and VLAN
 * id: an existing entry's id is returned and its ports are not changed.
 *
 * @param c {Client}        an open client
 * @param bridge {string}   the VLAN-aware bridge
 * @param vlanId {int}      VLAN id, 1-4094
 * @param tagged {string}   trunk ports, comma-separated, "" for none
 * @param untagged {string} access ports, comma-separated, "" for none
 * @return {string} the id of the new or existing entry
 * @throws {Error} kind "routeros" on a bad VLAN id, an unknown bridge or
 *                 an empty or spaced port name
 */
export func addBridgeVlan(
    c as Client,
    bridge as string,
    vlanId as int,
    tagged as string,
    untagged as string) {
    requiredId($c, BRIDGE_PATH, $bridge, "bridge");
    ensureVlanId($vlanId);
    def vid as string init convert.toString($vlanId);
    def rows as list of map of string to string init getAll($c, BRIDGE_VLAN_PATH);
    def existing as map of string to string init findBridgeVlanRow($rows, $bridge, $vid);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {"bridge": $bridge, "vlan-ids": $vid};
    if (strings.trim($tagged) != "") {
        $attrs["tagged"] = normalizedPortList($tagged);
    }
    if (strings.trim($untagged) != "") {
        $attrs["untagged"] = normalizedPortList($untagged);
    }
    return add($c, BRIDGE_VLAN_PATH, $attrs);
}

/**
 * Set an access port's default VLAN (its PVID).
 *
 * Untagged frames entering the port join this VLAN. It must match the
 * VLAN the port is untagged in.
 *
 * @param c {Client}      an open client
 * @param bridge {string} the VLAN-aware bridge
 * @param port {string}   the member interface
 * @param pvid {int}      VLAN id, 1-4094
 * @throws {Error} kind "routeros" on a bad id, or a port not on the bridge
 */
export func setPortPvid(c as Client, bridge as string, port as string, pvid as int) {
    ensureVlanId($pvid);
    def rows as list of map of string to string init getAll($c, BRIDGE_PORT_PATH);
    def row as map of string to string init bridgePortRow($rows, $bridge, $port);
    if (len($row) == 0) {
        raiseError("\"" + $port + "\" is not a port of the bridge \"" + $bridge + "\"");
    }
    set($c, BRIDGE_PORT_PATH, rowValue($row, ".id"), {"pvid": convert.toString($pvid)});
}

/**
 * Remove a VLAN from a bridge's VLAN table.
 *
 * @param c {Client}      an open client
 * @param bridge {string} the bridge
 * @param vlanId {int}   the VLAN id
 * @throws {Error} kind "routeros" when no such entry exists
 */
export func removeBridgeVlan(c as Client, bridge as string, vlanId as int) {
    def rows as list of map of string to string init getAll($c, BRIDGE_VLAN_PATH);
    def row as map of string to string init findBridgeVlanRow(
        $rows,
        $bridge,
        convert.toString($vlanId));
    if (len($row) == 0) {
        raiseError("the bridge \"" + $bridge + "\" has no VLAN " + convert.toString($vlanId));
    }
    remove($c, BRIDGE_VLAN_PATH, rowValue($row, ".id"));
}

/**
 * Validate and normalize a comma-separated bridge-port list.
 *
 * @param csv {string} the candidate list
 * @return {string} the normalized list
 * @throws {Error} kind "routeros" on an empty or spaced entry
 * @internal
 */
func normalizedPortList(csv as string) {
    def parts as list of string init strings.split($csv, ",");
    def out as list of string init [];
    for (def part in $parts) {
        def p as string init strings.trim($part);
        ensureName($p, "bridge port");
        $out[] = $p;
    }
    return strings.join($out, ",");
}

/**
 * Find a bridge VLAN entry by bridge and vlan id.
 *
 * @param rows {list of map of string to string} "/interface/bridge/vlan/print" rows
 * @param bridge {string} the bridge
 * @param vid {string}    the vlan id as a string
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findBridgeVlanRow(rows as list of map of string to string, bridge as string, vid as string) {
    for (def row in $rows) {
        if (rowValue($row, "bridge") == $bridge and rowValue($row, "vlan-ids") == $vid) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Find a bridge-port entry by bridge and interface.
 *
 * @param rows {list of map of string to string} "/interface/bridge/port/print" rows
 * @param bridge {string} the bridge
 * @param port {string}   the member interface
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func bridgePortRow(rows as list of map of string to string, bridge as string, port as string) {
    for (def row in $rows) {
        if (rowValue($row, "bridge") == $bridge and rowValue($row, "interface") == $port) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a reply row into a BridgeVlan.
 *
 * @param row {map of string to string} an "/interface/bridge/vlan/print" row
 * @return {BridgeVlan} the typed entry
 * @internal
 */
func bridgeVlanFromRow(row as map of string to string) {
    return BridgeVlan{
        id: rowValue($row, ".id"),
        bridge: rowValue($row, "bridge"),
        vlanIds: rowValue($row, "vlan-ids"),
        tagged: rowValue($row, "tagged"),
        untagged: rowValue($row, "untagged"),
        dynamic: rowBool($row, "dynamic")
    };
}

/**
 * Fold a reply row into a BridgePort.
 *
 * @param row {map of string to string} a "/interface/bridge/port/print" row
 * @return {BridgePort} the typed bridge port
 * @internal
 */
func bridgePortFromRow(row as map of string to string) {
    return BridgePort{
        id: rowValue($row, ".id"),
        bridge: rowValue($row, "bridge"),
        interfaceName: rowValue($row, "interface"),
        hardwareOffload: rowBool($row, "hw"),
        disabled: rowBool($row, "disabled")
    };
}
