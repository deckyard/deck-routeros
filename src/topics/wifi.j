# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - wifi: the modern wifiwave2 / ax menu (RouterOS v7).
# Spliced into routeros.j via include - not a standalone module.

/**
 * RouterOS API path of the modern WiFi interface list.
 *
 * Used by ax hardware; older boards use the classic "/interface/wireless"
 * (the wireless topic). Each topic's readers return empty lists on the
 * other kind of router.
 */
export def const WIFI_PATH as string init "/interface/wifi";

/** RouterOS API path of the modern WiFi registration table (clients). */
export def const WIFI_REGISTRATION_PATH as string init "/interface/wifi/registration-table";

/**
 * One modern (wifiwave2/ax) WiFi interface: a radio or a virtual AP.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} interface name, e.g. "wifi1"
 * @field ssid {string} configured network name (`configuration.ssid`)
 * @field band {string} configured band (`channel.band`), e.g. "5ghz-ax"
 * @field masterInterface {string} parent radio of a virtual AP, "" for a radio
 * @field running {bool} true when up and serving
 * @field disabled {bool} true when switched off
 * @field comment {string} comment, "" when unset
 */
export def struct WifiInterface {
    id as string,
    name as string,
    ssid as string,
    band as string,
    masterInterface as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * One connected client on a modern WiFi interface.
 *
 * @field interfaceName {string} WiFi interface the client is on
 * @field ssid {string} network it joined
 * @field mac {string} client MAC address
 * @field signal {string} signal in dBm, as reported
 * @field uptime {string} time connected, as reported
 */
export def struct WifiRegistration {
    interfaceName as string,
    ssid as string,
    mac as string,
    signal as string,
    uptime as string
};

/**
 * List the modern WiFi interfaces (radios and virtual APs).
 *
 * Empty on routers without the wifiwave2 menu and on any read error, a
 * dropped connection included.
 *
 * @param c {Client} an open client
 * @return {list of WifiInterface} all modern WiFi interfaces
 */
export func wifiInterfaces(c as Client) {
    def out as list of WifiInterface init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, WIFI_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = wifiFromRow($row);
    }
    return $out;
}

/**
 * Make a modern radio an access point.
 *
 * Sets mode "ap", the SSID, WPA2-PSK + WPA3-PSK and the passphrase on
 * the interface itself (no security profile) and enables it.
 * Idempotent: call again to change the SSID or passphrase. The
 * classic-menu counterpart is `setupWifiAccessPoint`.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} radio, e.g. "wifi1"
 * @param ssid {string} network name, 1-32 characters, spaces allowed
 * @param password {string} passphrase, 8-63 characters
 * @throws {Error} kind "routeros" on a bad SSID/passphrase or unknown interface
 * @example
 *   mt.setupWifi($c, "wifi1", "My Home WiFi", "correct horse battery");
 */
export func setupWifi(c as Client, interfaceName as string, ssid as string, password as string) {
    ensureSsid($ssid);
    ensureWifiPassword($password);
    set(
        $c,
        WIFI_PATH,
        requiredId($c, WIFI_PATH, $interfaceName, "WiFi interface"),
        {
            "configuration.mode": "ap",
            "configuration.ssid": $ssid,
            "security.authentication-types": "wpa2-psk,wpa3-psk",
            "security.passphrase": $password,
            "disabled": "no"
        });
}

/**
 * Change the passphrase of a modern WiFi interface.
 *
 * Connected clients are dropped and rejoin with the new passphrase.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} WiFi interface
 * @param password {string} new passphrase, 8-63 characters
 * @throws {Error} kind "routeros" on a bad passphrase or unknown interface
 */
export func setWifiPassphrase(c as Client, interfaceName as string, password as string) {
    ensureWifiPassword($password);
    set(
        $c,
        WIFI_PATH,
        requiredId($c, WIFI_PATH, $interfaceName, "WiFi interface"),
        {"security.passphrase": $password});
}

/**
 * Add a virtual AP on a modern radio, e.g. guest WiFi (WPA2/WPA3-PSK).
 *
 * @param c {Client} an open client
 * @param masterInterface {string} radio, e.g. "wifi1"
 * @param name {string} new interface name, e.g. "wifiguest"
 * @param ssid {string} network name, 1-32 characters
 * @param password {string} passphrase, 8-63 characters
 * @return {string} the RouterOS id of the new virtual AP
 * @throws {Error} kind "routeros" on bad input or an unknown radio
 */
export func addVirtualWifi(
    c as Client,
    masterInterface as string,
    name as string,
    ssid as string,
    password as string) {
    ensureName($name, "WiFi interface");
    ensureSsid($ssid);
    ensureWifiPassword($password);
    requiredId($c, WIFI_PATH, $masterInterface, "WiFi interface");
    return add(
        $c,
        WIFI_PATH,
        {
            "name": $name,
            "master-interface": $masterInterface,
            "configuration.mode": "ap",
            "configuration.ssid": $ssid,
            "security.authentication-types": "wpa2-psk,wpa3-psk",
            "security.passphrase": $password,
            "disabled": "no"
        });
}

/**
 * Remove a virtual AP; physical radios are refused.
 *
 * @param c {Client} an open client
 * @param name {string} virtual AP interface name
 * @throws {Error} kind "routeros" on an unknown interface or a physical radio
 */
export func removeVirtualWifi(c as Client, name as string) {
    def row as map of string to string init findByName($c, WIFI_PATH, $name);
    if (len($row) == 0) {
        raiseError("the WiFi interface \"" + $name + "\" was not found on the router");
    }
    if (rowValue($row, "master-interface") == "") {
        raiseError("\"" + $name + "\" is a physical radio - it can be disabled, not removed");
    }
    remove($c, WIFI_PATH, rowValue($row, ".id"));
}

/**
 * List the clients connected to the modern WiFi right now.
 *
 * Empty on routers without the wifiwave2 menu and on any read error.
 *
 * @param c {Client} an open client
 * @return {list of WifiRegistration} one entry per connected device
 */
export func wifiRegistrations(c as Client) {
    def out as list of WifiRegistration init [];
    def rows as list of map of string to string init [];
    try {
        $rows = getAll($c, WIFI_REGISTRATION_PATH);
    } catch (e) {
        return $out;
    }
    for (def row in $rows) {
        $out[] = wifiRegistrationFromRow($row);
    }
    return $out;
}

/**
 * Fold a reply row into a WifiInterface.
 *
 * @param row {map of string to string} an "/interface/wifi/print" row
 * @return {WifiInterface} the typed interface
 * @internal
 */
func wifiFromRow(row as map of string to string) {
    return WifiInterface{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        ssid: rowValue($row, "configuration.ssid"),
        band: rowValue($row, "channel.band"),
        masterInterface: rowValue($row, "master-interface"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold a reply row into a WifiRegistration.
 *
 * @param row {map of string to string} a wifi registration-table row
 * @return {WifiRegistration} the typed client entry
 * @internal
 */
func wifiRegistrationFromRow(row as map of string to string) {
    return WifiRegistration{
        interfaceName: rowValue($row, "interface"),
        ssid: rowValue($row, "ssid"),
        mac: rowValue($row, "mac-address"),
        signal: rowValue($row, "signal"),
        uptime: rowValue($row, "uptime")
    };
}
