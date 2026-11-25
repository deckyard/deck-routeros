# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - WiFi: radios, security profiles, clients.
# Spliced into routeros.j via include - not a standalone module.

/**
 * RouterOS API path of the wireless interface list.
 *
 * The classic menu of the "wireless" package. wifiwave2 / ax hardware
 * uses "/interface/wifi" instead (`WIFI_PATH`, the wifi topic).
 */
export def const WIRELESS_PATH as string init "/interface/wireless";

/** RouterOS API path of the wireless security profiles (WPA keys). */
export def const WIRELESS_SECURITY_PATH as string init "/interface/wireless/security-profiles";

/** RouterOS API path of the wireless registration table (connected clients). */
export def const WIRELESS_REGISTRATION_PATH as string init "/interface/wireless/registration-table";

/**
 * One wireless interface: a radio, or a virtual AP on top of one.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} interface name, e.g. "wlan1"
 * @field ssid {string} broadcast network name
 * @field mode {string} "ap-bridge" (access point), "station" (client), ...
 * @field band {string} radio band, e.g. "2ghz-b/g/n", "5ghz-a/n/ac"
 * @field frequency {string} channel frequency in MHz, or "auto"
 * @field securityProfile {string} security profile holding the password
 * @field masterInterface {string} parent radio of a virtual AP, "" for a physical radio
 * @field running {bool} true when the radio is up and serving
 * @field disabled {bool} true when the interface is switched off
 * @field comment {string} comment, "" when unset
 */
export def struct WirelessInterface {
    id as string,
    name as string,
    ssid as string,
    mode as string,
    band as string,
    frequency as string,
    securityProfile as string,
    masterInterface as string,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * One connected wireless client (a registration-table entry).
 *
 * @field interfaceName {string} wireless interface the client is on
 * @field mac {string} client MAC address
 * @field signalStrength {string} signal as reported, e.g. "-52dBm"
 * @field txRate {string} current transmit rate as reported
 * @field rxRate {string} current receive rate as reported
 * @field uptime {string} time connected, as reported
 */
export def struct WifiClient {
    interfaceName as string,
    mac as string,
    signalStrength as string,
    txRate as string,
    rxRate as string,
    uptime as string
};

/**
 * List every wireless interface: physical radios and virtual APs.
 *
 * Empty on routers without the classic wireless menu (wired-only models,
 * wifiwave2 hardware); any other failure (a dropped connection, a
 * timeout) is thrown.
 *
 * @param c {Client} an open client
 * @return {list of WirelessInterface} all wireless interfaces
 */
export func wirelessInterfaces(c as Client) {
    def out as list of WirelessInterface init [];
    def rows as list of map of string to string init optionalMenuRows($c, WIRELESS_PATH);
    for (def row in $rows) {
        $out[] = wirelessFromRow($row);
    }
    return $out;
}

/**
 * Make a radio a WPA2-PSK access point.
 *
 * Sets the SSID and mode "ap-bridge", stores the password in a dedicated
 * security profile "routeros-<interface>" (never the shared "default"
 * profile, so other radios are unaffected), attaches it and enables the
 * interface. Idempotent: call again to change the SSID or password.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} radio, e.g. "wlan1"
 * @param ssid {string} network name, 1-32 characters, spaces allowed
 * @param password {string} WPA2 passphrase, 8-63 characters
 * @throws {Error} kind "routeros" on a bad SSID / password or an
 *                 unknown wireless interface
 * @example
 *   mt.setupWifiAccessPoint($c, "wlan1", "My Home WiFi", "correct horse battery");
 */
export func setupWifiAccessPoint(
    c as Client,
    interfaceName as string,
    ssid as string,
    password as string) {
    ensureSsid($ssid);
    ensureWifiPassword($password);
    def id as string init requiredId($c, WIRELESS_PATH, $interfaceName, "wireless interface");
    def profile as string init ensureWifiProfile($c, wifiProfileName($interfaceName), $password);
    set(
        $c,
        WIRELESS_PATH,
        $id,
        {"ssid": $ssid, "security-profile": $profile, "mode": "ap-bridge", "disabled": "no"});
}

/**
 * Change the network name (SSID) a radio broadcasts.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} wireless interface
 * @param ssid {string} new name, 1-32 characters
 * @throws {Error} kind "routeros" on a bad SSID or unknown interface
 */
export func setWifiSsid(c as Client, interfaceName as string, ssid as string) {
    ensureSsid($ssid);
    set(
        $c,
        WIRELESS_PATH,
        requiredId($c, WIRELESS_PATH, $interfaceName, "wireless interface"),
        {"ssid": $ssid});
}

/**
 * Change the WiFi password of a radio.
 *
 * The password lives in the interface's security profile. An interface
 * on the "default" profile, on none, or on a profile another interface
 * also uses is first moved to a dedicated WPA2-PSK profile, so other
 * radios keep their password and settings. A profile this interface
 * uses alone keeps its mode and authentication types; only its
 * `wpa2-pre-shared-key` changes. Connected clients are dropped and must
 * reconnect with the new password.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} wireless interface
 * @param password {string} new WPA2 passphrase, 8-63 characters
 * @throws {Error} kind "routeros" on a bad password or unknown interface
 */
export func setWifiPassword(c as Client, interfaceName as string, password as string) {
    ensureWifiPassword($password);
    def rows as list of map of string to string init getAll($c, WIRELESS_PATH);
    def row as map of string to string init findRowByField($rows, "name", $interfaceName);
    if (len($row) == 0) {
        raiseError("the wireless interface \"" + $interfaceName + "\" was not found on the router");
    }
    def profile as string init rowValue($row, "security-profile");
    if (profileIsShared($rows, $interfaceName, $profile)) {
        def dedicated as string init ensureWifiProfile(
            $c,
            wifiProfileName($interfaceName),
            $password);
        set($c, WIRELESS_PATH, rowValue($row, ".id"), {"security-profile": $dedicated});
        return;
    }
    set(
        $c,
        WIRELESS_SECURITY_PATH,
        requiredId($c, WIRELESS_SECURITY_PATH, $profile, "security profile"),
        {"wpa2-pre-shared-key": $password});
}

/**
 * Whether changing a profile would touch more than one interface: the
 * built-in "default", no profile at all, or a profile another interface
 * uses too.
 *
 * @param rows {list of map of string to string} "/interface/wireless" rows
 * @param interfaceName {string} the interface being changed
 * @param profile {string} its security profile
 * @return {bool} true when the interface needs a dedicated profile
 * @internal
 */
func profileIsShared(
    rows as list of map of string to string,
    interfaceName as string,
    profile as string) {
    if ($profile == "" or $profile == "default") {
        return true;
    }
    for (def row in $rows) {
        if (rowValue($row, "name") != $interfaceName and
            rowValue($row, "security-profile") == $profile) {
            return true;
        }
    }
    return false;
}

/**
 * Add a virtual AP: a second network on an existing radio, e.g. guest WiFi.
 *
 * It gets its own SSID and its own security profile, and shares the
 * radio and channel of its master.
 *
 * @param c {Client} an open client
 * @param masterInterface {string} physical radio, e.g. "wlan1"
 * @param name {string} new interface name, e.g. "wlanguest"
 * @param ssid {string} network name, 1-32 characters
 * @param password {string} WPA2 passphrase, 8-63 characters
 * @return {string} the RouterOS id of the new virtual AP
 * @throws {Error} kind "routeros" on bad input or an unknown master radio
 */
export func addVirtualAp(
    c as Client,
    masterInterface as string,
    name as string,
    ssid as string,
    password as string) {
    ensureName($name, "interface");
    ensureSsid($ssid);
    ensureWifiPassword($password);
    requiredId($c, WIRELESS_PATH, $masterInterface, "wireless interface");
    def profile as string init ensureWifiProfile($c, wifiProfileName($name), $password);
    return add(
        $c,
        WIRELESS_PATH,
        {
            "name": $name,
            "master-interface": $masterInterface,
            "ssid": $ssid,
            "security-profile": $profile,
            "mode": "ap-bridge",
            "disabled": "no"
        });
}

/**
 * Remove a virtual AP.
 *
 * Refuses a physical radio (it can only be disabled) before the router
 * would. The dedicated security profile is kept and reused if the AP is
 * added again.
 *
 * @param c {Client} an open client
 * @param name {string} virtual AP interface name
 * @throws {Error} kind "routeros" when the interface is unknown or is
 *                 a physical radio
 */
export func removeVirtualAp(c as Client, name as string) {
    def row as map of string to string init findByName($c, WIRELESS_PATH, $name);
    if (len($row) == 0) {
        raiseError("the wireless interface \"" + $name + "\" was not found on the router");
    }
    if (rowValue($row, "master-interface") == "") {
        raiseError("\"" + $name + "\" is a physical radio - it can be disabled, not removed");
    }
    remove($c, WIRELESS_PATH, rowValue($row, ".id"));
}

/**
 * Switch a wireless interface on.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} wireless interface
 * @throws {Error} kind "routeros" when no such wireless interface exists
 */
export func enableWifi(c as Client, interfaceName as string) {
    enable($c, WIRELESS_PATH, requiredId($c, WIRELESS_PATH, $interfaceName, "wireless interface"));
}

/**
 * Switch a wireless interface off; its network disappears from the air.
 *
 * @param c {Client} an open client
 * @param interfaceName {string} wireless interface
 * @throws {Error} kind "routeros" when no such wireless interface exists
 */
export func disableWifi(c as Client, interfaceName as string) {
    disable($c, WIRELESS_PATH, requiredId($c, WIRELESS_PATH, $interfaceName, "wireless interface"));
}

/**
 * List the wireless clients connected right now.
 *
 * Empty on routers without the classic wireless menu; any other failure
 * (a dropped connection, a timeout) is thrown.
 *
 * @param c {Client} an open client
 * @return {list of WifiClient} one entry per connected device
 */
export func wifiClients(c as Client) {
    def out as list of WifiClient init [];
    def rows as list of map of string to string init optionalMenuRows(
        $c,
        WIRELESS_REGISTRATION_PATH);
    for (def row in $rows) {
        $out[] = wifiClientFromRow($row);
    }
    return $out;
}

/**
 * Validate an SSID: 1-32 bytes (UTF-8), spaces allowed.
 *
 * @param ssid {string} the candidate network name
 * @throws {Error} kind "routeros" when empty or over 32 bytes
 * @internal
 */
func ensureSsid(ssid as string) {
    if (strings.trim($ssid) == "") {
        raiseError("the SSID (network name) must not be empty");
    }
    if (len(encoding.encode("utf-8", $ssid)) > 32) {
        raiseError("the SSID must be at most 32 bytes (UTF-8): fewer characters outside ASCII");
    }
}

/**
 * Validate a WPA2 passphrase: 8 to 63 printable ASCII characters.
 *
 * @param password {string} the candidate passphrase
 * @throws {Error} kind "routeros" when outside 8-63 characters or holding
 *         a character outside printable ASCII
 * @internal
 */
func ensureWifiPassword(password as string) {
    if (len($password) < 8) {
        raiseError("the WiFi password must be at least 8 characters (WPA2 requirement)");
    }
    if (len($password) > 63) {
        raiseError("the WiFi password must be at most 63 characters (WPA2 requirement)");
    }
    def raw as bytes init encoding.encode("utf-8", $password);
    if (len($raw) != len($password)) {
        raiseError("the WiFi password must be printable ASCII (WPA2 requirement)");
    }
    for (def i as int init 0; $i < len($raw); $i = $i + 1) {
        if ($raw[$i] < 32 or $raw[$i] > 126) {
            raiseError("the WiFi password must be printable ASCII (WPA2 requirement)");
        }
    }
}

/**
 * The name of the dedicated security profile routeros manages for a
 * wireless interface.
 *
 * @param interfaceName {string} the wireless interface
 * @return {string} the deterministic profile name
 * @internal
 */
func wifiProfileName(interfaceName as string) {
    return "routeros-" + $interfaceName;
}

/**
 * Create or update a WPA2-PSK security profile with a password.
 *
 * Idempotent: an existing profile of that name is updated in place.
 *
 * @param c {Client} an open client
 * @param profileName {string} profile to create or update
 * @param password {string} WPA2 passphrase, already validated
 * @return {string} the profile name, for wiring into an interface
 * @internal
 */
func ensureWifiProfile(c as Client, profileName as string, password as string) {
    def attrs as map of string to string init {
        "mode": "dynamic-keys",
        "authentication-types": "wpa2-psk",
        "wpa2-pre-shared-key": $password
    };
    def id as string init idByName($c, WIRELESS_SECURITY_PATH, $profileName);
    if ($id == "") {
        $attrs["name"] = $profileName;
        add($c, WIRELESS_SECURITY_PATH, $attrs);
    } else {
        set($c, WIRELESS_SECURITY_PATH, $id, $attrs);
    }
    return $profileName;
}

/**
 * Fold a reply row into a WirelessInterface.
 *
 * @param row {map of string to string} an "/interface/wireless/print" row
 * @return {WirelessInterface} the typed wireless interface
 * @internal
 */
func wirelessFromRow(row as map of string to string) {
    return WirelessInterface{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        ssid: rowValue($row, "ssid"),
        mode: rowValue($row, "mode"),
        band: rowValue($row, "band"),
        frequency: rowValue($row, "frequency"),
        securityProfile: rowValue($row, "security-profile"),
        masterInterface: rowValue($row, "master-interface"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold a reply row into a WifiClient.
 *
 * @param row {map of string to string} a registration-table row
 * @return {WifiClient} the typed client entry
 * @internal
 */
func wifiClientFromRow(row as map of string to string) {
    return WifiClient{
        interfaceName: rowValue($row, "interface"),
        mac: rowValue($row, "mac-address"),
        signalStrength: rowValue($row, "signal-strength"),
        txRate: rowValue($row, "tx-rate"),
        rxRate: rowValue($row, "rx-rate"),
        uptime: rowValue($row, "uptime")
    };
}
