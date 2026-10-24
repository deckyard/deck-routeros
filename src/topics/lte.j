# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - LTE / cellular: a mobile-broadband uplink.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the LTE interface list. */
export def const LTE_PATH as string init "/interface/lte";

/** RouterOS API path of the LTE APN profiles. */
export def const LTE_APN_PATH as string init "/interface/lte/apn";

/**
 * One LTE (cellular) interface.
 *
 * @field id {string}       internal RouterOS id
 * @field name {string}     the interface name (e.g. "lte1")
 * @field running {bool}   the modem has a data connection
 * @field disabled {bool}  administratively off
 * @field comment {string}  free-text comment, "" when unset
 */
export def struct LteInterface {
    id as string,
    name as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * The measured state of an LTE modem.
 *
 * @field status {string}             registration status ("registered", ...)
 * @field registered {bool}           the status contains "registered"
 * @field operator {string}           the mobile network operator
 * @field accessTechnology {string}   "lte" / "5g" / "hspa" / ... as reported
 * @field signalStrength {string}     RSSI as reported (dBm)
 * @field rsrp {string}               reference signal received power (LTE)
 * @field rsrq {string}               reference signal received quality (LTE)
 * @field sinr {string}               signal-to-noise ratio
 */
export def struct LteStatus {
    status as string,
    registered as bool,
    operator as string,
    accessTechnology as string,
    signalStrength as string,
    rsrp as string,
    rsrq as string,
    sinr as string
};

/**
 * List the LTE interfaces.
 *
 * Any read error gives an empty list, so a router without a modem reads
 * as empty - and so does a dropped connection.
 *
 * @param c {Client} an open client
 * @return {list of LteInterface} all LTE interfaces
 */
export func lteInterfaces(c as Client) {
    def out as list of LteInterface init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, LTE_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = lteFromRow($row);
    }
    return $out;
}

/**
 * Measure an LTE modem now: registration, operator, signal.
 *
 * Runs `monitor once`. An RSRP below about -100 dBm or a status other
 * than registered explains a flaky uplink; an external antenna or a
 * better modem position are the usual fixes.
 *
 * @param c {Client}    an open client
 * @param name {string} the LTE interface (e.g. "lte1")
 * @return {LteStatus} the measured state
 * @throws {Error} kind "routeros" when no LTE interface has that name
 * @example
 *   def s as mt.LteStatus init mt.lteStatus($c, "lte1");
 *   io.printf("%s on %s: RSRP %s\n", $s.status, $s.operator, $s.rsrp);
 */
export func lteStatus(c as Client, name as string) {
    requiredId($c, LTE_PATH, $name, "LTE interface");
    def rows as list of map of string to string init apiTalk(
        $c,
        LTE_PATH + "/monitor",
        {"numbers": $name, "once": ""});
    return lteStatusFromRow(mergeRows($rows));
}

/**
 * Set the APN (carrier access point name) for an LTE interface.
 *
 * A wrong APN is the usual cause of "registered but no internet".
 * Creates or updates the APN profile "routeros-<interface>" and binds it
 * to the interface.
 *
 * @param c {Client}             an open client
 * @param interfaceName {string} the LTE interface
 * @param apn {string}           the carrier APN (e.g. "internet", "web.provider")
 * @throws {Error} kind "routeros" on an empty APN or unknown interface
 * @example
 *   mt.setLteApn($c, "lte1", "internet");
 */
export func setLteApn(c as Client, interfaceName as string, apn as string) {
    def profile as string init strings.trim($apn);
    if ($profile == "") {
        raiseError("the APN must not be empty - it comes from your mobile carrier");
    }
    def id as string init requiredId($c, LTE_PATH, $interfaceName, "LTE interface");
    def profileName as string init "routeros-" + $interfaceName;
    def apnId as string init idByName($c, LTE_APN_PATH, $profileName);
    if ($apnId == "") {
        add($c, LTE_APN_PATH, {"name": $profileName, "apn": $profile});
    } else {
        set($c, LTE_APN_PATH, $apnId, {"apn": $profile});
    }
    set($c, LTE_PATH, $id, {"apn-profiles": $profileName});
}

/**
 * Enable an LTE interface.
 *
 * @param c {Client}    an open client
 * @param name {string} the LTE interface
 * @throws {Error} kind "routeros" when no LTE interface has that name
 */
export func enableLte(c as Client, name as string) {
    enable($c, LTE_PATH, requiredId($c, LTE_PATH, $name, "LTE interface"));
}

/**
 * Disable an LTE interface; the cellular uplink drops.
 *
 * @param c {Client}    an open client
 * @param name {string} the LTE interface
 * @throws {Error} kind "routeros" when no LTE interface has that name
 */
export func disableLte(c as Client, name as string) {
    disable($c, LTE_PATH, requiredId($c, LTE_PATH, $name, "LTE interface"));
}

/**
 * Fold a reply row into an LteInterface.
 *
 * @param row {map of string to string} an "/interface/lte/print" row
 * @return {LteInterface} the typed interface
 * @internal
 */
func lteFromRow(row as map of string to string) {
    return LteInterface{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold the merged monitor rows into an LteStatus.
 *
 * `registered` is computed here: the status contains "registered".
 *
 * @param row {map of string to string} the merged monitor rows
 * @return {LteStatus} the typed live state
 * @internal
 */
func lteStatusFromRow(row as map of string to string) {
    def status as string init rowValue($row, "registration-status");
    return LteStatus{
        status: $status,
        registered: strings.contains($status, "registered"),
        operator: rowValue($row, "current-operator"),
        accessTechnology: rowValue($row, "access-technology"),
        signalStrength: rowValue($row, "rssi"),
        rsrp: rowValue($row, "rsrp"),
        rsrq: rowValue($row, "rsrq"),
        sinr: rowValue($row, "sinr")
    };
}
