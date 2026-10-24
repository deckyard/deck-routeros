# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - hotspot: a captive guest portal.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the hotspot server list. */
export def const HOTSPOT_PATH as string init "/ip/hotspot";

/** RouterOS API path of the hotspot server profile list. */
export def const HOTSPOT_PROFILE_PATH as string init "/ip/hotspot/profile";

/** RouterOS API path of the hotspot user list. */
export def const HOTSPOT_USER_PATH as string init "/ip/hotspot/user";

/** RouterOS API path of the active hotspot sessions. */
export def const HOTSPOT_ACTIVE_PATH as string init "/ip/hotspot/active";

/** RouterOS API path of the hotspot IP bindings (bypassed or blocked devices). */
export def const HOTSPOT_BINDING_PATH as string init "/ip/hotspot/ip-binding";

/** RouterOS API path of the walled garden (destinations allowed before login). */
export def const WALLED_GARDEN_PATH as string init "/ip/hotspot/walled-garden";

/**
 * One hotspot server: a captive portal guarding an interface.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          server name
 * @field interfaceName {string} guarded interface, usually the guest bridge
 * @field addressPool {string}   pool guests get addresses from
 * @field profile {string}       server profile: portal address, login method
 * @field disabled {bool}        true when switched off
 */
export def struct HotspotServer {
    id as string,
    name as string,
    interfaceName as string,
    addressPool as string,
    profile as string,
    disabled as bool
};

/**
 * One hotspot user: a portal login.
 *
 * @field id {string}          internal RouterOS id
 * @field name {string}        login name
 * @field profile {string}     user profile ("default" unless customized)
 * @field limitUptime {string} total connect time allowed, "" for unlimited
 * @field uptime {string}      time used so far
 * @field disabled {bool}      true when switched off
 * @field comment {string}     free-text comment, "" when unset
 */
export def struct HotspotUser {
    id as string,
    name as string,
    profile as string,
    limitUptime as string,
    uptime as string,
    disabled as bool,
    comment as string
};

/**
 * One active hotspot session.
 *
 * @field user {string}     login used
 * @field address {string}  guest IP address
 * @field mac {string}      guest MAC address
 * @field uptime {string}   session duration so far
 * @field idleTime {string} time since the guest last sent traffic
 * @field bytesIn {int}     bytes received from the guest
 * @field bytesOut {int}    bytes sent to the guest
 */
export def struct HotspotSession {
    user as string,
    address as string,
    mac as string,
    uptime as string,
    idleTime as string,
    bytesIn as int,
    bytesOut as int
};

/**
 * List the hotspot servers.
 *
 * @param c {Client} an open client
 * @return {list of HotspotServer} all portals
 */
export func hotspotServers(c as Client) {
    def rows as list of map of string to string init getAll($c, HOTSPOT_PATH);
    def out as list of HotspotServer init [];
    for (def row in $rows) {
        $out[] = hotspotFromRow($row);
    }
    return $out;
}

/**
 * Set up a captive guest portal on an interface.
 *
 * Builds what the RouterOS setup wizard builds: the guest DHCP stack
 * (`setupDhcp`, with the gateway as DNS server), a hotspot profile named
 * like the portal, and the hotspot server. Every web request is then
 * redirected to the login page until the guest logs in.
 *
 * Use a dedicated guest interface or bridge: the hotspot intercepts all
 * traffic on its interface, and on the management LAN it locks everyone
 * out, you included. The interface needs an address inside the network
 * first (`addIpAddress`). When a hotspot server with this name exists,
 * its id is returned and nothing is changed.
 *
 * @param c {Client}             an open client
 * @param name {string}          name of the portal, its profile and DHCP pieces
 * @param interfaceName {string} guest interface or bridge (e.g. "brguest")
 * @param network {string}       guest network in CIDR form (e.g. "10.5.50.0/24")
 * @param gateway {string}       router address in that network (e.g. "10.5.50.1")
 * @param rangeFrom {string}     first guest address
 * @param rangeTo {string}       last guest address
 * @return {string} the RouterOS id of the hotspot server
 * @throws {Error} kind "routeros" on an empty or spaced name, or any input
 *                 `setupDhcp` rejects
 * @example
 *   mt.addBridge($c, "brguest");
 *   mt.addBridgePort($c, "brguest", "wifiguest");
 *   mt.addIpAddress($c, "10.5.50.1/24", "brguest");
 *   mt.setupHotspot($c, "guests", "brguest", "10.5.50.0/24",
 *       "10.5.50.1", "10.5.50.10", "10.5.50.254");
 *   mt.addHotspotVoucher($c, "visitor", "day pass 123", "1d", "front desk");
 */
export func setupHotspot(
    c as Client,
    name as string,
    interfaceName as string,
    network as string,
    gateway as string,
    rangeFrom as string,
    rangeTo as string) {
    ensureName($name, "hotspot");
    def existing as string init idByName($c, HOTSPOT_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    setupDhcp($c, $name, $interfaceName, $network, $gateway, $rangeFrom, $rangeTo, $gateway);
    if (idByName($c, HOTSPOT_PROFILE_PATH, $name) == "") {
        add($c, HOTSPOT_PROFILE_PATH, {"name": $name, "hotspot-address": $gateway});
    }
    return add(
        $c,
        HOTSPOT_PATH,
        {"name": $name, "interface": $interfaceName, "address-pool": $name, "profile": $name});
}

/**
 * Remove a portal: server, profile and DHCP stack.
 *
 * Each piece is removed when present. Users, bindings and walled-garden
 * entries do not belong to one portal and stay.
 *
 * @param c {Client}       an open client
 * @param name {string}    the name given to `setupHotspot`
 * @param network {string} the CIDR string given to `setupHotspot`
 * @throws {Error} kind "routeros" when nothing of the portal exists
 */
export func teardownHotspot(c as Client, name as string, network as string) {
    def found as int init 0;
    def serverId as string init idByName($c, HOTSPOT_PATH, $name);
    if ($serverId != "") {
        remove($c, HOTSPOT_PATH, $serverId);
        $found = $found + 1;
    }
    def profileId as string init idByName($c, HOTSPOT_PROFILE_PATH, $name);
    if ($profileId != "") {
        remove($c, HOTSPOT_PROFILE_PATH, $profileId);
        $found = $found + 1;
    }
    try {
        teardownDhcp($c, $name, $network);
        $found = $found + 1;
    } catch (e) { # lint-disable: L103
        # Deliberate: the DHCP half may already be gone, or never have been
        # set up. That is not a failure to remove the hotspot - $found simply
        # does not count it, and an entirely absent hotspot still raises below.
    }
    if ($found == 0) {
        raiseError("no hotspot named \"" + $name + "\" was found");
    }
}

/**
 * List the portal logins.
 *
 * @param c {Client} an open client
 * @return {list of HotspotUser} all hotspot users
 */
export func hotspotUsers(c as Client) {
    def rows as list of map of string to string init getAll($c, HOTSPOT_USER_PATH);
    def out as list of HotspotUser init [];
    for (def row in $rows) {
        $out[] = hotspotUserFromRow($row);
    }
    return $out;
}

/**
 * Create a portal login.
 *
 * @param c {Client}        an open client
 * @param name {string}     login name
 * @param password {string} login password, not empty
 * @param comment {string}  free-text note, "" for none
 * @return {string} the RouterOS id of the user
 * @throws {Error} kind "routeros" on an empty or spaced name, an empty
 *                 password, or a login that already exists
 */
export func addHotspotUser(c as Client, name as string, password as string, comment as string) {
    return hotspotUserAdd($c, $name, $password, "", $comment);
}

/**
 * Create a time-limited portal login (a voucher).
 *
 * The login stops working once its total connect time is used up (a day
 * pass). Connect time, not calendar time.
 *
 * @param c {Client}           an open client
 * @param name {string}        login name
 * @param password {string}    login password, not empty
 * @param uptimeLimit {string} total connect time: "4h", "1d", "1d12h" or
 *                            "HH:MM:SS"
 * @param comment {string}     free-text note, "" for none
 * @return {string} the RouterOS id of the user
 * @throws {Error} kind "routeros" on a malformed limit, an empty or spaced
 *                 name, an empty password, or an existing login
 */
export func addHotspotVoucher(
    c as Client,
    name as string,
    password as string,
    uptimeLimit as string,
    comment as string) {
    def limit as string init strings.trim($uptimeLimit);
    ensureSchedulerInterval($limit);
    return hotspotUserAdd($c, $name, $password, $limit, $comment);
}

/**
 * Delete a portal login.
 *
 * @param c {Client}    an open client
 * @param name {string} login name
 * @throws {Error} kind "routeros" when no such login exists
 */
export func removeHotspotUser(c as Client, name as string) {
    remove($c, HOTSPOT_USER_PATH, requiredId($c, HOTSPOT_USER_PATH, $name, "hotspot user"));
}

/**
 * List the active portal sessions with their usage counters.
 *
 * @param c {Client} an open client
 * @return {list of HotspotSession} the active sessions
 */
export func hotspotActive(c as Client) {
    def rows as list of map of string to string init getAll($c, HOTSPOT_ACTIVE_PATH);
    def out as list of HotspotSession init [];
    for (def row in $rows) {
        $out[] = hotspotSessionFromRow($row);
    }
    return $out;
}

/**
 * End a guest's session now; the guest is sent back to the login page.
 *
 * @param c {Client}    an open client
 * @param user {string} login whose session to end
 * @throws {Error} kind "routeros" when that login has no active session
 */
export func kickHotspotUser(c as Client, user as string) {
    def rows as list of map of string to string init getAll($c, HOTSPOT_ACTIVE_PATH);
    def row as map of string to string init findRowByField($rows, "user", $user);
    if (len($row) == 0) {
        raiseError("\"" + $user + "\" has no active hotspot session");
    }
    remove($c, HOTSPOT_ACTIVE_PATH, rowValue($row, ".id"));
}

/**
 * Let a device through the portal without logging in (a bypass binding).
 *
 * For devices that cannot use a login page: printers, TVs, payment
 * terminals. Idempotent by MAC.
 *
 * @param c {Client}       an open client
 * @param mac {string}     device MAC, any case; sent uppercased
 * @param comment {string} free-text note (e.g. "lobby printer"), "" for none
 * @return {string} the RouterOS id of the binding
 * @throws {Error} kind "routeros" on a malformed MAC
 */
export func bypassHotspotMac(c as Client, mac as string, comment as string) {
    ensureMac($mac);
    def wanted as string init strings.upper($mac);
    def rows as list of map of string to string init getAll($c, HOTSPOT_BINDING_PATH);
    def existing as map of string to string init findRowByField($rows, "mac-address", $wanted);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {"mac-address": $wanted, "type": "bypassed"};
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, HOTSPOT_BINDING_PATH, $attrs);
}

/**
 * Remove a device's portal bypass, so it has to log in again.
 *
 * @param c {Client}   an open client
 * @param mac {string} device MAC, any case
 * @throws {Error} kind "routeros" on a malformed MAC or when no bypass
 *                 exists for it
 */
export func removeHotspotBypass(c as Client, mac as string) {
    ensureMac($mac);
    def rows as list of map of string to string init getAll($c, HOTSPOT_BINDING_PATH);
    def row as map of string to string init findRowByField(
        $rows,
        "mac-address",
        strings.upper($mac));
    if (len($row) == 0) {
        raiseError("no hotspot bypass for MAC \"" + $mac + "\" was found");
    }
    remove($c, HOTSPOT_BINDING_PATH, rowValue($row, ".id"));
}

/**
 * Allow a destination before login (walled garden).
 *
 * Guests who have not logged in can still reach the host: your own site,
 * a payment provider, terms pages. Idempotent by host.
 *
 * @param c {Client}       an open client
 * @param dstHost {string} destination host name; wildcards like
 *                        "*.example.org" work
 * @param comment {string} free-text note, "" for none
 * @return {string} the RouterOS id of the entry
 * @throws {Error} kind "routeros" on an empty or spaced host
 */
export func allowBeforeLogin(c as Client, dstHost as string, comment as string) {
    def host as string init strings.trim($dstHost);
    ensureHost($host);
    def rows as list of map of string to string init getAll($c, WALLED_GARDEN_PATH);
    def existing as map of string to string init findRowByField($rows, "dst-host", $host);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {"dst-host": $host, "action": "allow"};
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, WALLED_GARDEN_PATH, $attrs);
}

/**
 * Remove a walled-garden entry.
 *
 * @param c {Client}       an open client
 * @param dstHost {string} host the entry was created for
 * @throws {Error} kind "routeros" when no such entry exists
 */
export func removeWalledGardenEntry(c as Client, dstHost as string) {
    def rows as list of map of string to string init getAll($c, WALLED_GARDEN_PATH);
    def row as map of string to string init findRowByField(
        $rows,
        "dst-host",
        strings.trim($dstHost));
    if (len($row) == 0) {
        raiseError("no walled-garden entry for \"" + $dstHost + "\" was found");
    }
    remove($c, WALLED_GARDEN_PATH, rowValue($row, ".id"));
}

/**
 * Validate and create a hotspot user; empty limit omits the cap.
 *
 * @param c {Client}        an open client
 * @param name {string}     login name
 * @param password {string} its password
 * @param limit {string}    limit-uptime, "" for unlimited
 * @param comment {string}  note, "" for none
 * @return {string} the RouterOS id of the user
 * @throws {Error} kind "routeros" on bad input or an existing login
 * @internal
 */
func hotspotUserAdd(
    c as Client,
    name as string,
    password as string,
    limit as string,
    comment as string) {
    ensureName($name, "hotspot user");
    if (strings.trim($password) == "") {
        raiseError("the hotspot user password must not be empty");
    }
    if (idByName($c, HOTSPOT_USER_PATH, $name) != "") {
        raiseError("the hotspot user \"" + $name + "\" already exists");
    }
    def attrs as map of string to string init {"name": $name, "password": $password};
    if ($limit != "") {
        $attrs["limit-uptime"] = $limit;
    }
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, HOTSPOT_USER_PATH, $attrs);
}

/**
 * Fold a reply row into a HotspotServer.
 *
 * @param row {map of string to string} an "/ip/hotspot/print" row
 * @return {HotspotServer} the typed server
 * @internal
 */
func hotspotFromRow(row as map of string to string) {
    return HotspotServer{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        interfaceName: rowValue($row, "interface"),
        addressPool: rowValue($row, "address-pool"),
        profile: rowValue($row, "profile"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Fold a reply row into a HotspotUser.
 *
 * @param row {map of string to string} an "/ip/hotspot/user/print" row
 * @return {HotspotUser} the typed user
 * @internal
 */
func hotspotUserFromRow(row as map of string to string) {
    return HotspotUser{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        profile: rowValue($row, "profile"),
        limitUptime: rowValue($row, "limit-uptime"),
        uptime: rowValue($row, "uptime"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold a reply row into a HotspotSession.
 *
 * @param row {map of string to string} an "/ip/hotspot/active/print" row
 * @return {HotspotSession} the typed session
 * @internal
 */
func hotspotSessionFromRow(row as map of string to string) {
    return HotspotSession{
        user: rowValue($row, "user"),
        address: rowValue($row, "address"),
        mac: rowValue($row, "mac-address"),
        uptime: rowValue($row, "uptime"),
        idleTime: rowValue($row, "idle-time"),
        bytesIn: rowInt($row, "bytes-in"),
        bytesOut: rowInt($row, "bytes-out")
    };
}
