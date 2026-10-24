# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - system: packages, updates, firmware, reboot.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the installed-package list. */
export def const SYSTEM_PACKAGE_PATH as string init "/system/package";

/** RouterOS API path of the package-update menu. */
export def const SYSTEM_UPDATE_PATH as string init "/system/package/update";

/** RouterOS API path of the routerboard (firmware) menu. */
export def const SYSTEM_ROUTERBOARD_PATH as string init "/system/routerboard";

/** RouterOS API path of the resource (version / memory / load) menu. */
export def const SYSTEM_RESOURCE_PATH as string init "/system/resource";

/** RouterOS API path of the identity (router name) menu. */
export def const SYSTEM_IDENTITY_PATH as string init "/system/identity";

/**
 * One installed RouterOS software package.
 *
 * @field id {string}       internal RouterOS id
 * @field name {string}     package name (e.g. "routeros", "wireless")
 * @field version {string}  installed version (e.g. "7.15.2")
 * @field disabled {bool} true when the package is disabled
 */
export def struct Package {
    id as string,
    name as string,
    version as string,
    disabled as bool
};

/**
 * The state of the RouterOS package updater.
 *
 * @field channel {string}          release channel ("stable", "testing", ...)
 * @field installedVersion {string} the RouterOS version running now
 * @field latestVersion {string}    the newest version the channel offers, "" when unknown
 * @field status {string}           the updater's own status text
 * @field updateAvailable {bool}  true when a newer version can be installed
 */
export def struct UpdateStatus {
    channel as string,
    installedVersion as string,
    latestVersion as string,
    status as string,
    updateAvailable as bool
};

/**
 * The routerboard: the hardware and its boot firmware.
 *
 * @field model {string}            hardware model (e.g. "RB4011iGS+")
 * @field serialNumber {string}     hardware serial number
 * @field firmwareType {string}     firmware family (e.g. "al2")
 * @field currentFirmware {string}  firmware version running now
 * @field upgradeFirmware {string}  firmware version available to flash
 * @field upgradeAvailable {bool} true when `upgradeRouterboard` would change anything
 */
export def struct Routerboard {
    model as string,
    serialNumber as string,
    firmwareType as string,
    currentFirmware as string,
    upgradeFirmware as string,
    upgradeAvailable as bool
};

/**
 * The router's software version, hardware and load.
 *
 * Values are strings exactly as the router reports them, so a unit change
 * in RouterOS does not break parsing.
 *
 * @field version {string}      RouterOS version (e.g. "7.15.2 (stable)")
 * @field boardName {string}    board name (e.g. "RB4011iGS+")
 * @field architecture {string} CPU architecture (e.g. "arm64")
 * @field uptime {string}       time since the last boot (e.g. "2w3d4h5m6s")
 * @field cpuLoad {string}      current CPU load in percent
 * @field freeMemory {string}   free RAM in bytes
 * @field totalMemory {string}  total RAM in bytes
 */
export def struct SystemInfo {
    version as string,
    boardName as string,
    architecture as string,
    uptime as string,
    cpuLoad as string,
    freeMemory as string,
    totalMemory as string
};

/**
 * Read version, hardware, uptime, CPU load and memory.
 *
 * @param c {Client} an open client
 * @return {SystemInfo} the snapshot
 */
export func systemInfo(c as Client) {
    return systemInfoFromRow(singleRow($c, SYSTEM_RESOURCE_PATH));
}

/**
 * Read the router's name (its identity).
 *
 * @param c {Client} an open client
 * @return {string} the router name
 */
export func identity(c as Client) {
    return rowValue(singleRow($c, SYSTEM_IDENTITY_PATH), "name");
}

/**
 * Give the router a new name (its identity).
 *
 * @param c {Client}    an open client
 * @param name {string} the new router name
 * @throws {Error} kind "routeros" on an empty name
 */
export func setIdentity(c as Client, name as string) {
    if (strings.trim($name) == "") {
        raiseError("the router name must not be empty");
    }
    apiRun($c, SYSTEM_IDENTITY_PATH + "/set", {"name": $name});
}

/**
 * List the installed RouterOS software packages.
 *
 * @param c {Client} an open client
 * @return {list of Package} the installed packages
 */
export func packages(c as Client) {
    def rows as list of map of string to string init getAll($c, SYSTEM_PACKAGE_PATH);
    def out as list of Package init [];
    for (def row in $rows) {
        $out[] = packageFromRow($row);
    }
    return $out;
}

/**
 * Ask the update servers whether a newer RouterOS version exists.
 *
 * Read-only: nothing is downloaded or installed. The router needs
 * internet access (DNS and HTTPS).
 *
 * @param c {Client} an open client
 * @return {UpdateStatus} the updater state; check `updateAvailable`
 * @throws {Error} kind "mikrotik" when the router cannot reach the update servers
 * @example
 *   def st as mt.UpdateStatus init mt.checkForUpdates($c);
 *   if ($st.updateAvailable) {
 *       io.printf("%s -> %s\n", $st.installedVersion, $st.latestVersion);
 *   }
 */
export func checkForUpdates(c as Client) {
    def none as map of string to string init {};
    def rows as list of map of string to string init apiTalk(
        $c,
        SYSTEM_UPDATE_PATH + "/check-for-updates",
        $none);
    return updateStatusFromRow(mergeRows($rows));
}

/**
 * Download the newest RouterOS packages without installing them.
 *
 * The update is installed on the next reboot. Blocks until the download
 * finishes.
 *
 * @param c {Client} an open client
 * @return {UpdateStatus} the updater state after the download
 * @throws {Error} kind "mikrotik" when the download fails
 */
export func downloadUpdates(c as Client) {
    def none as map of string to string init {};
    def rows as list of map of string to string init apiTalk(
        $c,
        SYSTEM_UPDATE_PATH + "/download",
        $none);
    return updateStatusFromRow(mergeRows($rows));
}

/**
 * Download and install the newest RouterOS packages.
 *
 * The router downloads the update, then reboots itself to apply it. The
 * client is unusable afterwards; reconnect once the router is back.
 * `checkForUpdates` shows the target version first.
 *
 * @param c {Client} an open client
 * @throws {Error} kind "mikrotik" when the router refuses (e.g. no
 *                 update reachable); a dropped connection caused by the
 *                 reboot itself is expected and swallowed
 */
export func installUpdates(c as Client) {
    runSystemCommand($c, SYSTEM_UPDATE_PATH + "/install");
}

/**
 * Read the hardware model and the boot-firmware versions.
 *
 * @param c {Client} an open client
 * @return {Routerboard} the routerboard state; check `upgradeAvailable`
 */
export func routerboard(c as Client) {
    return routerboardFromRow(singleRow($c, SYSTEM_ROUTERBOARD_PATH));
}

/**
 * Stage the routerboard (boot firmware) upgrade.
 *
 * Every package update ships a matching firmware, flashed only on request.
 * This call stages the flash; the firmware takes effect on the next
 * reboot, so the sequence is `upgradeRouterboard`, then `reboot`. The
 * connection stays up and nothing changes until that reboot.
 *
 * @param c {Client} an open client
 * @throws {Error} kind "mikrotik" when the router refuses
 */
export func upgradeRouterboard(c as Client) {
    def none as map of string to string init {};
    apiRun($c, SYSTEM_ROUTERBOARD_PATH + "/upgrade", $none);
}

/**
 * Reboot the router now.
 *
 * The connection drops and the client is unusable afterwards; reconnect
 * once the router is back.
 *
 * @param c {Client} an open client
 * @throws {Error} kind "mikrotik" when the router refuses (e.g. the
 *                 user lacks the reboot policy); a dropped connection
 *                 caused by the reboot itself is expected and swallowed
 */
export func reboot(c as Client) {
    runSystemCommand($c, "/system/reboot");
}

/**
 * Power the router down now.
 *
 * Switching it back on needs physical access; on a remote router use
 * `reboot`.
 *
 * @param c {Client} an open client
 * @throws {Error} kind "mikrotik" when the router refuses; a dropped
 *                 connection caused by the shutdown itself is expected
 *                 and swallowed
 */
export func shutdown(c as Client) {
    runSystemCommand($c, "/system/shutdown");
}

/**
 * Run a command that takes the router down (reboot, shutdown, install).
 *
 * A `!trap` from the router (bad policy, refused command) is re-thrown;
 * a transport error is swallowed, because the connection dropping is
 * exactly what success looks like for these commands.
 *
 * @param c {Client}       an open client
 * @param command {string} the command path (e.g. "/system/reboot")
 * @throws {Error} kind "mikrotik" when the router itself refused
 * @internal
 */
func runSystemCommand(c as Client, command as string) {
    def none as map of string to string init {};
    try {
        apiRun($c, $command, $none);
    } catch (e) {
        if ($e.kind == "mikrotik") {
            throw $e;
        }
    }
}

/**
 * Fold a reply row into a Package.
 *
 * @param row {map of string to string} a "/system/package/print" row
 * @return {Package} the typed package
 * @internal
 */
func packageFromRow(row as map of string to string) {
    return Package{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        version: rowValue($row, "version"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Fold a (merged) updater row into an UpdateStatus.
 *
 * `updateAvailable` is computed here: both versions known and different.
 *
 * @param row {map of string to string} the merged updater row
 * @return {UpdateStatus} the typed updater state
 * @internal
 */
func updateStatusFromRow(row as map of string to string) {
    def installed as string init rowValue($row, "installed-version");
    def latest as string init rowValue($row, "latest-version");
    return UpdateStatus{
        channel: rowValue($row, "channel"),
        installedVersion: $installed,
        latestVersion: $latest,
        status: rowValue($row, "status"),
        updateAvailable: $installed != "" and $latest != "" and $installed != $latest
    };
}

/**
 * Fold a reply row into a Routerboard.
 *
 * `upgradeAvailable` is computed here: both firmware versions known and
 * different.
 *
 * @param row {map of string to string} a "/system/routerboard/print" row
 * @return {Routerboard} the typed routerboard state
 * @internal
 */
func routerboardFromRow(row as map of string to string) {
    def current as string init rowValue($row, "current-firmware");
    def upgrade as string init rowValue($row, "upgrade-firmware");
    return Routerboard{
        model: rowValue($row, "model"),
        serialNumber: rowValue($row, "serial-number"),
        firmwareType: rowValue($row, "firmware-type"),
        currentFirmware: $current,
        upgradeFirmware: $upgrade,
        upgradeAvailable: $current != "" and $upgrade != "" and $current != $upgrade
    };
}

/**
 * Fold a reply row into a SystemInfo.
 *
 * @param row {map of string to string} a "/system/resource/print" row
 * @return {SystemInfo} the typed snapshot
 * @internal
 */
func systemInfoFromRow(row as map of string to string) {
    return SystemInfo{
        version: rowValue($row, "version"),
        boardName: rowValue($row, "board-name"),
        architecture: rowValue($row, "architecture-name"),
        uptime: rowValue($row, "uptime"),
        cpuLoad: rowValue($row, "cpu-load"),
        freeMemory: rowValue($row, "free-memory"),
        totalMemory: rowValue($row, "total-memory")
    };
}

/** RouterOS API path of the device-mode settings. */
export def const DEVICE_MODE_PATH as string init "/system/device-mode";

/** RouterOS API command that requests a device-mode change. */
export def const DEVICE_MODE_UPDATE_COMMAND as string init "/system/device-mode/update";

/** Device mode: the locked-down factory default on most models. */
export def const DEVICE_MODE_HOME as string init "home";

/** Device mode: unlocks container, scheduler, fetch and e-mail. */
export def const DEVICE_MODE_ADVANCED as string init "advanced";

/** Device mode: everything unlocked, for managed deployments. */
export def const DEVICE_MODE_ENTERPRISE as string init "enterprise";

/**
 * The router's device mode and the features it gates.
 *
 * @field mode {string}              the active mode ("home" / "advanced" / "enterprise")
 * @field flaggingEnabled {bool}   true when tamper flagging is on
 * @field container {bool}         true when containers may run
 * @field scheduler {bool}         true when the scheduler may run scripts
 * @field fetch {bool}             true when /tool/fetch is allowed
 * @field email {bool}             true when the router may send e-mail
 * @field socks {bool}             true when the SOCKS proxy is allowed
 * @field installAnyVersion {bool} true when downgrades are permitted
 */
export def struct DeviceMode {
    mode as string,
    flaggingEnabled as bool,
    container as bool,
    scheduler as bool,
    fetch as bool,
    email as bool,
    socks as bool,
    installAnyVersion as bool
};

/**
 * Read the router's device mode.
 *
 * Check it first when a feature seems missing: in `home` mode the
 * scheduler, fetch, e-mail and containers are gated off, and the API
 * reports them as missing rather than refused.
 *
 * @param c {Client} an open client
 * @return {DeviceMode} the active mode and its feature flags
 * @example
 *   def d as mt.DeviceMode init mt.deviceMode($c);
 *   if (not $d.scheduler) { io.printf("scheduler is gated off in %s mode\n", $d.mode); }
 */
export func deviceMode(c as Client) {
    return deviceModeFromRow(singleRow($c, DEVICE_MODE_PATH));
}

/**
 * Request a device-mode change.
 *
 * The change is only pending when this returns. RouterOS requires
 * physical presence: it applies the change when someone power-cycles the
 * router (a cold boot, not `reboot`) or presses the reset button within a
 * few minutes. Otherwise the request is discarded silently and the mode
 * stays as it was. An unattended script cannot complete it, and a soft
 * `reboot` does not confirm it.
 *
 * Raising the mode (`home` -> `advanced` -> `enterprise`) needs this
 * confirmation because it unlocks code execution. Read the result with
 * `deviceMode` once the router is back.
 *
 * @param c {Client}    an open client
 * @param mode {string} one of the DEVICE_MODE_* constants
 * @throws {Error} kind "routeros" on an unknown mode, kind "mikrotik"
 *                 when the router refuses the request
 * @example
 *   mt.updateDeviceMode($c, mt.DEVICE_MODE_ADVANCED);
 *   # now power-cycle the router, then:
 *   #   io.printf("%s\n", mt.deviceMode($c).mode);
 */
export func updateDeviceMode(c as Client, mode as string) {
    def target as string init strings.trim($mode);
    ensureDeviceMode($target);
    apiRun($c, DEVICE_MODE_UPDATE_COMMAND, {"mode": $target});
}

/**
 * Fold a reply row into a DeviceMode.
 *
 * @param row {map of string to string} a "/system/device-mode/print" row
 * @return {DeviceMode} the typed mode
 * @internal
 */
func deviceModeFromRow(row as map of string to string) {
    return DeviceMode{
        mode: rowValue($row, "mode"),
        flaggingEnabled: rowBool($row, "flagging-enabled"),
        container: rowBool($row, "container"),
        scheduler: rowBool($row, "scheduler"),
        fetch: rowBool($row, "fetch"),
        email: rowBool($row, "email"),
        socks: rowBool($row, "socks"),
        installAnyVersion: rowBool($row, "install-any-version")
    };
}

/**
 * Validate a device mode against the DEVICE_MODE_* constants.
 *
 * @param mode {string} the candidate mode
 * @throws {Error} kind "routeros" on an unknown mode
 * @internal
 */
func ensureDeviceMode(mode as string) {
    if ($mode != DEVICE_MODE_HOME and $mode != DEVICE_MODE_ADVANCED and
        $mode != DEVICE_MODE_ENTERPRISE) {
        raiseError("\"" + $mode +
            "\" is not a device mode - use DEVICE_MODE_HOME, DEVICE_MODE_ADVANCED, or DEVICE_MODE_ENTERPRISE");
    }
}
