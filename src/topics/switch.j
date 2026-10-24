# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - switch chip: hardware-offload inventory and host table.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the ethernet switch chip(s). */
export def const ETHERNET_SWITCH_PATH as string init "/interface/ethernet/switch";

/** RouterOS API path of the switch chip's hardware MAC table. */
export def const ETHERNET_SWITCH_HOST_PATH as string init "/interface/ethernet/switch/host";

/**
 * One switch chip on the router.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} chip name, e.g. "switch1"
 * @field kind {string} chip model as reported (the `type` property), e.g. "Atheros-8327"
 */
export def struct SwitchChip {
    id as string,
    name as string,
    kind as string
};

/**
 * One entry in the switch chip's hardware MAC table.
 *
 * An entry means the chip learned the MAC, so traffic to it is forwarded
 * in hardware, not by the CPU.
 *
 * @field mac {string} learned MAC address
 * @field ports {string} switch port(s) it was learned on
 * @field vlanId {int} VLAN id, 0 when untagged or not reported
 * @field dynamic {bool} true when learned, false for a static entry
 */
export def struct SwitchHost {
    mac as string,
    ports as string,
    vlanId as int,
    dynamic as bool
};

/**
 * List the switch chips on the router.
 *
 * Empty on a board without a switch chip (pure CPU), which cannot
 * offload bridging to hardware. Any read error, a dropped connection
 * included, also yields an empty list.
 *
 * @param c {Client} an open client
 * @return {list of SwitchChip} the switch chips
 */
export func switchChips(c as Client) {
    def out as list of SwitchChip init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, ETHERNET_SWITCH_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = switchChipFromRow($row);
    }
    return $out;
}

/**
 * Read the switch chip's hardware MAC table, all of it (it can be large).
 *
 * LAN MACs in this table mean the chip forwards their traffic. An empty
 * table on a busy LAN with high CPU load means offload is not engaging
 * and the bridge forwards in software. Any read error, a dropped
 * connection included, yields an empty list.
 *
 * @param c {Client} an open client
 * @return {list of SwitchHost} the hardware MAC entries
 */
export func switchHosts(c as Client) {
    def out as list of SwitchHost init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, ETHERNET_SWITCH_HOST_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = switchHostFromRow($row);
    }
    return $out;
}

/**
 * Fold a reply row into a SwitchChip.
 *
 * @param row {map of string to string} an "/interface/ethernet/switch/print" row
 * @return {SwitchChip} the typed chip
 * @internal
 */
func switchChipFromRow(row as map of string to string) {
    return SwitchChip{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        kind: rowValue($row, "type")
    };
}

/**
 * Fold a reply row into a SwitchHost.
 *
 * @param row {map of string to string} a switch host-table row
 * @return {SwitchHost} the typed entry
 * @internal
 */
func switchHostFromRow(row as map of string to string) {
    return SwitchHost{
        mac: rowValue($row, "mac-address"),
        ports: rowValue($row, "ports"),
        vlanId: rowInt($row, "vlan-id"),
        dynamic: rowBool($row, "dynamic")
    };
}
