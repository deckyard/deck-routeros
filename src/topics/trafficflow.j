# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - traffic flow: export NetFlow / IPFIX to a collector.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the traffic-flow settings. */
export def const TRAFFIC_FLOW_PATH as string init "/ip/traffic-flow";

/** RouterOS API path of the traffic-flow export targets (collectors). */
export def const TRAFFIC_FLOW_TARGET_PATH as string init "/ip/traffic-flow/target";

def const FLOW_VERSIONS as list of string init ["1", "5", "9", "ipfix"];

/**
 * The traffic-flow (NetFlow/IPFIX) settings.
 *
 * @field enabled {bool} true when flow accounting is running
 * @field interfaces {string} accounted interfaces, "all" for every one
 */
export def struct TrafficFlowSettings {
    enabled as bool,
    interfaces as string
};

/**
 * One traffic-flow export target (a collector).
 *
 * @field id {string} internal RouterOS id
 * @field address {string} collector address
 * @field port {string} collector UDP port
 * @field version {string} export protocol version ("1", "5", "9", "ipfix")
 * @field disabled {bool} true when switched off
 */
export def struct FlowTarget {
    id as string,
    address as string,
    port as string,
    version as string,
    disabled as bool
};

/**
 * Read the traffic-flow settings.
 *
 * @param c {Client} an open client
 * @return {TrafficFlowSettings} the settings
 */
export func trafficFlowStatus(c as Client) {
    return trafficFlowFromRow(singleRow($c, TRAFFIC_FLOW_PATH));
}

/**
 * List the traffic-flow export targets.
 *
 * @param c {Client} an open client
 * @return {list of FlowTarget} all collectors
 */
export func flowTargets(c as Client) {
    def rows as list of map of string to string init getAll($c, TRAFFIC_FLOW_TARGET_PATH);
    def out as list of FlowTarget init [];
    for (def row in $rows) {
        $out[] = flowTargetFromRow($row);
    }
    return $out;
}

/**
 * Turn flow accounting on, for all interfaces.
 *
 * Records are exported only once a collector is added with
 * `addFlowTarget`.
 *
 * @param c {Client} an open client
 * @example
 *   mt.enableTrafficFlow($c);
 *   mt.addFlowTarget($c, "10.0.9.30", 2055, "ipfix");
 */
export func enableTrafficFlow(c as Client) {
    apiRun($c, TRAFFIC_FLOW_PATH + "/set", {"enabled": "yes", "interfaces": "all"});
}

/**
 * Turn flow accounting off.
 *
 * @param c {Client} an open client
 */
export func disableTrafficFlow(c as Client) {
    apiRun($c, TRAFFIC_FLOW_PATH + "/set", {"enabled": "no"});
}

/**
 * Export flow records to a collector.
 *
 * `ipfix` or NetFlow v9 for modern collectors; v5 is the widely
 * supported legacy format. When a target with this address and port
 * exists, its id is returned and nothing is changed.
 *
 * @param c {Client} an open client
 * @param address {string} collector IP address
 * @param port {int} collector UDP port (e.g. 2055 for NetFlow, 4739 for IPFIX)
 * @param version {string} "1", "5", "9" or "ipfix" (any case; sent as
 *        RouterOS's "IPFIX")
 * @return {string} the RouterOS id of the new or existing target
 * @throws {Error} kind "routeros" on a bad address, port or version
 */
export func addFlowTarget(c as Client, address as string, port as int, version as string) {
    def collector as string init strings.trim($address);
    ensureIpAddress($collector);
    ensurePort($port);
    def wire as string init flowVersionWord($version);
    def portStr as string init convert.toString($port);
    def rows as list of map of string to string init getAll($c, TRAFFIC_FLOW_TARGET_PATH);
    for (def row in $rows) {
        if (flowTargetAddress($row) == $collector and rowValue($row, "port") == $portStr) {
            return rowValue($row, ".id");
        }
    }
    return add(
        $c,
        TRAFFIC_FLOW_TARGET_PATH,
        {"dst-address": $collector, "port": $portStr, "version": $wire});
}

/**
 * The `version` word RouterOS takes for a NetFlow version.
 *
 * @param version {string} "1", "5", "9" or "ipfix" in any case
 * @return {string} the version, "IPFIX" in RouterOS's spelling
 * @throws {Error} kind "routeros" on any other version
 * @internal
 */
func flowVersionWord(version as string) {
    def v as string init strings.lower(strings.trim($version));
    if (not lists.contains(FLOW_VERSIONS, $v)) {
        raiseError("unknown NetFlow version \"" + $version + "\" - use one of: " +
            strings.join(FLOW_VERSIONS, ", "));
    }
    if ($v == "ipfix") {
        return "IPFIX";
    }
    return $v;
}

/**
 * A target row's collector address: `dst-address` (RouterOS v6.x and
 * v7), else the pre-v6 `address` written "ip:port".
 *
 * @param row {map of string to string} a target row
 * @return {string} the collector address, "" when absent
 * @internal
 */
func flowTargetAddress(row as map of string to string) {
    def a as string init rowValue($row, "dst-address");
    if ($a != "") {
        return $a;
    }
    def old as string init rowValue($row, "address");
    def colon as int init strings.lastIndexOf($old, ":");
    if ($colon > 0 and not strings.contains($old[..$colon], ":")) {
        return $old[..$colon];
    }
    return $old;
}

/**
 * Remove a traffic-flow target by address; with several targets on that
 * address, the first one listed.
 *
 * @param c {Client} an open client
 * @param address {string} collector address
 * @throws {Error} kind "routeros" when no target has that address
 */
export func removeFlowTarget(c as Client, address as string) {
    def target as string init strings.trim($address);
    def rows as list of map of string to string init getAll($c, TRAFFIC_FLOW_TARGET_PATH);
    for (def row in $rows) {
        if ($target != "" and flowTargetAddress($row) == $target) {
            remove($c, TRAFFIC_FLOW_TARGET_PATH, rowValue($row, ".id"));
            return;
        }
    }
    raiseError("no traffic-flow target at \"" + $address + "\" was found");
}

/**
 * Fold a reply row into the TrafficFlowSettings.
 *
 * @param row {map of string to string} the "/ip/traffic-flow/print" row
 * @return {TrafficFlowSettings} the typed settings
 * @internal
 */
func trafficFlowFromRow(row as map of string to string) {
    return TrafficFlowSettings{
        enabled: rowBool($row, "enabled"),
        interfaces: rowValue($row, "interfaces")
    };
}

/**
 * Fold a reply row into a FlowTarget.
 *
 * @param row {map of string to string} an "/ip/traffic-flow/target/print" row
 * @return {FlowTarget} the typed target
 * @internal
 */
func flowTargetFromRow(row as map of string to string) {
    return FlowTarget{
        id: rowValue($row, ".id"),
        address: flowTargetAddress($row),
        port: rowValue($row, "port"),
        version: rowValue($row, "version"),
        disabled: rowBool($row, "disabled")
    };
}
