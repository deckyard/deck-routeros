# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - MikroTik Cloud DDNS: a stable name for a dynamic address.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the MikroTik Cloud menu. */
export def const CLOUD_PATH as string init "/ip/cloud";

/**
 * MikroTik Cloud DDNS state.
 *
 * @field ddnsEnabled {bool} whether the router keeps its cloud name updated
 * @field dnsName {string} `<serial>.sn.mynetname.net`, "" until the first
 *        update completes
 * @field publicAddress {string} the public address MikroTik's servers last saw
 * @field updateTime {string} time of the last update, as RouterOS prints it
 */
export def struct CloudStatus {
    ddnsEnabled as bool,
    dnsName as string,
    publicAddress as string,
    updateTime as string
};

/**
 * Read the cloud DDNS state.
 *
 * @param c {Client} an open client
 * @return {CloudStatus} the current state
 */
export func cloudStatus(c as Client) {
    return cloudFromRow(singleRow($c, CLOUD_PATH));
}

/**
 * Turn on MikroTik Cloud DDNS and force an update.
 *
 * The router registers `<serial>.sn.mynetname.net` and keeps it pointing
 * at its current public address. Use the name as the `connectWireguard`
 * endpoint or the `enableLetsEncrypt` dns-name. It usually resolves
 * within a minute.
 *
 * @param c {Client} an open client
 * @throws {Error} kind "mikrotik" when the router cannot reach the
 *         cloud servers
 */
export func enableCloudDns(c as Client) {
    apiRun($c, CLOUD_PATH + "/set", {"ddns-enabled": "yes"});
    def none as map of string to string init {};
    apiRun($c, CLOUD_PATH + "/force-update", $none);
}

/**
 * Turn cloud DDNS off; the name stops following the public address.
 *
 * @param c {Client} an open client
 */
export func disableCloudDns(c as Client) {
    apiRun($c, CLOUD_PATH + "/set", {"ddns-enabled": "no"});
}

/**
 * Read the router's cloud DNS name.
 *
 * @param c {Client} an open client
 * @return {string} the name, e.g. "1234567890ab.sn.mynetname.net"
 * @throws {Error} kind "routeros" when no name is assigned yet
 */
export func routerDnsName(c as Client) {
    def status as CloudStatus init cloudStatus($c);
    if ($status.dnsName == "") {
        raiseError("no cloud DNS name assigned yet - enableCloudDns and give it a minute");
    }
    return $status.dnsName;
}

/**
 * Fold the "/ip/cloud/print" row into a CloudStatus.
 *
 * @param row {map of string to string} the reply row
 * @return {CloudStatus} the typed state
 * @internal
 */
func cloudFromRow(row as map of string to string) {
    return CloudStatus{
        ddnsEnabled: rowBool($row, "ddns-enabled"),
        dnsName: rowValue($row, "dns-name"),
        publicAddress: rowValue($row, "public-address"),
        updateTime: rowValue($row, "update-time")
    };
}
