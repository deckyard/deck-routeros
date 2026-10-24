# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - ethernet ports: speed, duplex, MTU, PoE, link state.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the ethernet port list. */
export def const ETHERNET_PATH as string init "/interface/ethernet";

def const ETHERNET_SPEEDS as list of string init [
    "10Mbps",
    "100Mbps",
    "1Gbps",
    "2.5Gbps",
    "5Gbps",
    "10Gbps"
];

def const POE_MODES as list of string init ["auto-on", "forced-on", "off"];

/**
 * One physical ethernet port and its configuration.
 *
 * @field id {string}              internal RouterOS id
 * @field name {string}            current name (e.g. "ether1")
 * @field defaultName {string}     factory name, stable across renames
 * @field mac {string}             MAC address
 * @field mtu {string}             configured MTU as reported
 * @field autoNegotiation {bool}   speed and duplex negotiated (the default)
 * @field poeOut {string}          PoE mode ("auto-on", "forced-on", "off"),
 *                                 "" on ports without PoE
 * @field running {bool}           link up
 * @field slave {bool}             member of a bridge or bond, whose settings
 *                                 then mostly apply instead
 * @field disabled {bool}          administratively off
 * @field comment {string}         free-text comment, "" when unset
 */
export def struct EthernetPort {
    id as string,
    name as string,
    defaultName as string,
    mac as string,
    mtu as string,
    autoNegotiation as bool,
    poeOut as string,
    running as bool,
    slave as bool,
    disabled as bool,
    comment as string
};

/**
 * The measured state of one ethernet link.
 *
 * @field name {string}            the port
 * @field up {bool}                status is "link-ok"
 * @field status {string}          raw status ("link-ok", "no-link", ...)
 * @field rate {string}            negotiated speed (e.g. "1Gbps"), "" when down
 * @field fullDuplex {bool}        full-duplex link
 * @field autoNegotiation {string} negotiation state ("done", "incomplete",
 *                                 "disabled")
 */
export def struct LinkStatus {
    name as string,
    up as bool,
    status as string,
    rate as string,
    fullDuplex as bool,
    autoNegotiation as string
};

/**
 * List the ethernet ports with their settings.
 *
 * @param c {Client} an open client
 * @return {list of EthernetPort} all physical ports
 */
export func ethernetPorts(c as Client) {
    def rows as list of map of string to string init getAll($c, ETHERNET_PATH);
    def out as list of EthernetPort init [];
    for (def row in $rows) {
        $out[] = ethernetFromRow($row);
    }
    return $out;
}

/**
 * Look an ethernet port up by name.
 *
 * @param c {Client}    an open client
 * @param name {string} port name (e.g. "ether1")
 * @return {EthernetPort} the port
 * @throws {Error} kind "routeros" when no ethernet port has that name
 */
export func ethernetPortByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, ETHERNET_PATH, $name);
    if (len($row) == 0) {
        raiseError("the ethernet port \"" + $name + "\" was not found on the router");
    }
    return ethernetFromRow($row);
}

/**
 * Measure a link now: up or down, speed, duplex.
 *
 * Runs `monitor once`. A gigabit port that negotiated 100Mbps or half
 * duplex is the usual cause of a slow link.
 *
 * @param c {Client}    an open client
 * @param name {string} the ethernet port
 * @return {LinkStatus} the measured state
 * @throws {Error} kind "routeros" when no ethernet port has that name
 * @example
 *   def ls as mt.LinkStatus init mt.linkStatus($c, "ether1");
 *   if ($ls.up and $ls.rate != "1Gbps") {
 *       io.printf("ether1 came up at only %s\n", $ls.rate);
 *   }
 */
export func linkStatus(c as Client, name as string) {
    requiredId($c, ETHERNET_PATH, $name, "ethernet port");
    def rows as list of map of string to string init apiTalk(
        $c,
        ETHERNET_PATH + "/monitor",
        {"numbers": $name, "once": ""});
    return linkStatusFromRow(mergeRows($rows));
}

/**
 * Force a port to a fixed speed and duplex (auto-negotiation off).
 *
 * For link partners that cannot negotiate (old industrial gear, some
 * media converters). Both ends must be forced to the same values: forcing
 * one side against an auto-negotiating peer gives a duplex mismatch, a
 * link that comes up and then loses packets under load.
 *
 * @param c {Client}          an open client
 * @param name {string}       the ethernet port
 * @param speed {string}      "10Mbps", "100Mbps", "1Gbps", "2.5Gbps",
 *                            "5Gbps" or "10Gbps"; the hardware may refuse
 * @param fullDuplex {bool}   full duplex
 * @throws {Error} kind "routeros" on an unknown port or speed
 */
export func forceEthernetLink(c as Client, name as string, speed as string, fullDuplex as bool) {
    ensureEthernetSpeed($speed);
    set(
        $c,
        ETHERNET_PATH,
        requiredId($c, ETHERNET_PATH, $name, "ethernet port"),
        {"auto-negotiation": "no", "speed": $speed, "full-duplex": boolWord($fullDuplex)});
}

/**
 * Put a port back on auto-negotiation, the default.
 *
 * @param c {Client}    an open client
 * @param name {string} the ethernet port
 * @throws {Error} kind "routeros" when no ethernet port has that name
 */
export func autoNegotiateEthernet(c as Client, name as string) {
    set(
        $c,
        ETHERNET_PATH,
        requiredId($c, ETHERNET_PATH, $name, "ethernet port"),
        {"auto-negotiation": "yes"});
}

/**
 * Change a port's MTU.
 *
 * Jumbo frames (e.g. 9000) need every device on the path to agree. The
 * port's l2mtu caps the value; the router refuses anything above it.
 *
 * @param c {Client}    an open client
 * @param name {string} the ethernet port
 * @param mtu {int}     the MTU, 68-65535 (ethernet default 1500)
 * @throws {Error} kind "routeros" on an unknown port or an MTU outside
 *                 68-65535, kind "mikrotik" when the hardware refuses
 */
export func setEthernetMtu(c as Client, name as string, mtu as int) {
    ensureMtu($mtu);
    set(
        $c,
        ETHERNET_PATH,
        requiredId($c, ETHERNET_PATH, $name, "ethernet port"),
        {"mtu": convert.toString($mtu)});
}

/**
 * Set the PoE output mode of a port.
 *
 * "auto-on" powers a detected device (the default), "forced-on" powers
 * unconditionally, "off" cuts power. "off" then "auto-on" power-cycles a
 * hung PoE device.
 *
 * @param c {Client}    an open client
 * @param name {string} the ethernet port
 * @param mode {string} "auto-on", "forced-on", or "off"
 * @throws {Error} kind "routeros" on an unknown port, a port without
 *                 PoE, or an unknown mode
 * @example
 *   mt.setPoe($c, "ether5", "off");      # camera hung?
 *   mt.setPoe($c, "ether5", "auto-on");  # power-cycle done
 */
export func setPoe(c as Client, name as string, mode as string) {
    ensurePoeMode($mode);
    def row as map of string to string init findByName($c, ETHERNET_PATH, $name);
    if (len($row) == 0) {
        raiseError("the ethernet port \"" + $name + "\" was not found on the router");
    }
    if (rowValue($row, "poe-out") == "") {
        raiseError("the port \"" + $name + "\" has no PoE output");
    }
    set($c, ETHERNET_PATH, rowValue($row, ".id"), {"poe-out": $mode});
}

/**
 * Validate a forced ethernet speed.
 *
 * @param speed {string} the candidate
 * @throws {Error} kind "routeros" on an unknown speed
 * @internal
 */
func ensureEthernetSpeed(speed as string) {
    if (not lists.contains(ETHERNET_SPEEDS, $speed)) {
        raiseError("unknown speed \"" + $speed + "\" - use one of: " +
            strings.join(ETHERNET_SPEEDS, ", "));
    }
}

/**
 * Validate a PoE mode.
 *
 * @param mode {string} the candidate
 * @throws {Error} kind "routeros" on an unknown mode
 * @internal
 */
func ensurePoeMode(mode as string) {
    if (not lists.contains(POE_MODES, $mode)) {
        raiseError("unknown PoE mode \"" + $mode + "\" - use one of: " +
            strings.join(POE_MODES, ", "));
    }
}

/**
 * Validate an MTU value.
 *
 * @param mtu {int} the candidate
 * @throws {Error} kind "routeros" when outside 68-65535
 * @internal
 */
func ensureMtu(mtu as int) {
    if ($mtu < 68 or $mtu > 65535) {
        raiseError("the MTU must be between 68 and 65535 (1500 is the ethernet default)");
    }
}

/**
 * Fold a reply row into an EthernetPort.
 *
 * @param row {map of string to string} an "/interface/ethernet/print" row
 * @return {EthernetPort} the typed port
 * @internal
 */
func ethernetFromRow(row as map of string to string) {
    return EthernetPort{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        defaultName: rowValue($row, "default-name"),
        mac: rowValue($row, "mac-address"),
        mtu: rowValue($row, "mtu"),
        autoNegotiation: rowBool($row, "auto-negotiation"),
        poeOut: rowValue($row, "poe-out"),
        running: rowBool($row, "running"),
        slave: rowBool($row, "slave"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold the merged monitor rows into a LinkStatus.
 *
 * `up` is computed here: the status equals "link-ok".
 *
 * @param row {map of string to string} the merged monitor rows
 * @return {LinkStatus} the typed link state
 * @internal
 */
func linkStatusFromRow(row as map of string to string) {
    def status as string init rowValue($row, "status");
    return LinkStatus{
        name: rowValue($row, "name"),
        up: $status == "link-ok",
        status: $status,
        rate: rowValue($row, "rate"),
        fullDuplex: rowBool($row, "full-duplex"),
        autoNegotiation: rowValue($row, "auto-negotiation")
    };
}
