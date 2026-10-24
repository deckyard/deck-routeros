# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - clock and NTP.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the system clock menu. */
export def const CLOCK_PATH as string init "/system/clock";

/** RouterOS API path of the NTP client menu (RouterOS v7 shape). */
export def const NTP_CLIENT_PATH as string init "/system/ntp/client";

/**
 * The router's clock state.
 *
 * @field time {string}       current time as reported
 * @field date {string}       current date as reported
 * @field timezone {string}   timezone name (e.g. "Europe/Berlin")
 * @field autodetect {bool} true when the router guesses the timezone
 * @field gmtOffset {string}  the resulting UTC offset as reported
 */
export def struct Clock {
    time as string,
    date as string,
    timezone as string,
    autodetect as bool,
    gmtOffset as string
};

/**
 * The NTP client state.
 *
 * @field enabled {bool} true when the router syncs its clock
 * @field servers {string} the configured NTP servers, comma-separated
 * @field status {string}  the sync state as reported
 * @field synced {bool}  computed: the status equals "synchronized"
 */
export def struct NtpStatus {
    enabled as bool,
    servers as string,
    status as string,
    synced as bool
};

/**
 * Read the router's clock.
 *
 * Certificate validation, scheduler times and log timestamps depend on
 * it; check it first when one of them misbehaves.
 *
 * @param c {Client} an open client
 * @return {Clock} the clock state
 */
export func clock(c as Client) {
    return clockFromRow(singleRow($c, CLOCK_PATH));
}

/**
 * Set the router's timezone.
 *
 * @param c {Client}        an open client
 * @param timezone {string} an IANA name like "Europe/Berlin", or "UTC"
 * @throws {Error} kind "routeros" on an empty or spaced name,
 *                 kind "mikrotik" when the router does not know the zone
 */
export func setTimezone(c as Client, timezone as string) {
    def tz as string init strings.trim($timezone);
    ensureName($tz, "timezone");
    apiRun($c, CLOCK_PATH + "/set", {"time-zone-name": $tz, "time-zone-autodetect": "no"});
}

/**
 * Enable the NTP client with the given servers.
 *
 * MikroTik routers have no battery-backed clock: without NTP the time
 * restarts at boot, and certificates, schedules and logs go wrong.
 *
 * @param c {Client}       an open client
 * @param servers {string} NTP servers, comma-separated - DNS names or
 *                         IPs (e.g. "pool.ntp.org" or "192.168.88.1")
 * @throws {Error} kind "routeros" on an empty list, an empty entry or an
 *                 entry containing a space
 * @example
 *   mt.useNtp($c, "pool.ntp.org");
 *   mt.setTimezone($c, "Europe/Berlin");
 */
export func useNtp(c as Client, servers as string) {
    def serverList as string init normalizedNtpServers($servers);
    apiRun($c, NTP_CLIENT_PATH + "/set", {"enabled": "yes", "servers": $serverList});
}

/**
 * Switch the NTP client off; the clock free-runs and resets at boot.
 *
 * @param c {Client} an open client
 */
export func disableNtp(c as Client) {
    apiRun($c, NTP_CLIENT_PATH + "/set", {"enabled": "no"});
}

/**
 * Read the NTP client state; `synced` says whether the clock is synchronized.
 *
 * @param c {Client} an open client
 * @return {NtpStatus} the NTP state
 */
export func ntpStatus(c as Client) {
    return ntpFromRow(singleRow($c, NTP_CLIENT_PATH));
}

/**
 * Validate and normalize a comma-separated NTP server list (DNS names
 * or IPs, spaces tolerated).
 *
 * @param csv {string} the candidate list
 * @return {string} the normalized list
 * @throws {Error} kind "routeros" on an empty list or a spaced entry
 * @internal
 */
func normalizedNtpServers(csv as string) {
    def parts as list of string init strings.split($csv, ",");
    def out as list of string init [];
    for (def part in $parts) {
        def p as string init strings.trim($part);
        if ($p == "") {
            raiseError("the NTP server list \"" + $csv + "\" must not contain empty entries");
        }
        ensureHost($p);
        $out[] = $p;
    }
    if (len($out) == 0) {
        raiseError("the NTP server list must contain at least one server");
    }
    return strings.join($out, ",");
}

/**
 * Fold a reply row into the Clock.
 *
 * @param row {map of string to string} the "/system/clock/print" row
 * @return {Clock} the typed clock state
 * @internal
 */
func clockFromRow(row as map of string to string) {
    return Clock{
        time: rowValue($row, "time"),
        date: rowValue($row, "date"),
        timezone: rowValue($row, "time-zone-name"),
        autodetect: rowBool($row, "time-zone-autodetect"),
        gmtOffset: rowValue($row, "gmt-offset")
    };
}

/**
 * Fold a reply row into the NtpStatus.
 *
 * `synced` is computed here: the status equals "synchronized".
 *
 * @param row {map of string to string} the "/system/ntp/client/print" row
 * @return {NtpStatus} the typed NTP state
 * @internal
 */
func ntpFromRow(row as map of string to string) {
    def status as string init rowValue($row, "status");
    return NtpStatus{
        enabled: rowBool($row, "enabled"),
        servers: rowValue($row, "servers"),
        status: $status,
        synced: $status == "synchronized"
    };
}
