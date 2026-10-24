# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - PPPoE client, and the PPP user database shared by the
# L2TP / SSTP / OpenVPN / PPTP remote-access servers.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the PPP secrets (the VPN and dial-in user database). */
export def const PPP_SECRET_PATH as string init "/ppp/secret";

/** RouterOS API path of the PPP profiles (addresses, DNS and limits per login). */
export def const PPP_PROFILE_PATH as string init "/ppp/profile";

/** RouterOS API path of the active PPP sessions across all servers. */
export def const PPP_ACTIVE_PATH as string init "/ppp/active";

def const PPP_SERVICES as list of string init ["any", "l2tp", "sstp", "ovpn", "pptp", "pppoe"];

/**
 * One PPP secret: a login shared by the PPP-based servers.
 *
 * @field id {string}            internal RouterOS id
 * @field name {string}          login name
 * @field service {string}       servers that accept it: "any", "l2tp", "sstp",
 *                               "ovpn", "pptp" or "pppoe"
 * @field profile {string}       PPP profile applied ("default" unless set)
 * @field localAddress {string}  router's tunnel address, "" when the profile decides
 * @field remoteAddress {string} client's tunnel address, "" when the profile decides
 * @field disabled {bool}        true when switched off
 * @field comment {string}       free-text comment, "" when unset
 */
export def struct PppUser {
    id as string,
    name as string,
    service as string,
    profile as string,
    localAddress as string,
    remoteAddress as string,
    disabled as bool,
    comment as string
};

/**
 * One PPP profile: the addresses, DNS and limits applied to a login.
 *
 * @field id {string}           internal RouterOS id
 * @field name {string}         profile name
 * @field localAddress {string} router's tunnel address, or a pool name
 * @field remoteAddress {string} client address, or a pool name
 * @field dnsServer {string}    DNS handed to clients, "" when unset
 * @field disabled {bool}       true when switched off
 */
export def struct PppProfile {
    id as string,
    name as string,
    localAddress as string,
    remoteAddress as string,
    dnsServer as string,
    disabled as bool
};

/**
 * One active PPP session: a connected VPN or dial-in client.
 *
 * @field name {string}    login used
 * @field service {string} server type ("l2tp", "sstp", "ovpn", "pppoe", ...)
 * @field address {string} client tunnel address
 * @field uptime {string}  session duration so far
 * @field callerId {string} where the client connected from (address or MAC)
 */
export def struct PppSession {
    name as string,
    service as string,
    address as string,
    uptime as string,
    callerId as string
};

/**
 * List the PPP logins.
 *
 * @param c {Client} an open client
 * @return {list of PppUser} all logins
 */
export func vpnUsers(c as Client) {
    def rows as list of map of string to string init getAll($c, PPP_SECRET_PATH);
    def out as list of PppUser init [];
    for (def row in $rows) {
        $out[] = pppUserFromRow($row);
    }
    return $out;
}

/**
 * Create a remote-access VPN login.
 *
 * One login serves every PPP-based server (L2TP, SSTP, OpenVPN, PPTP,
 * PPPoE); `service` "any" admits it everywhere, any other value pins it
 * to one. It gets the "default" profile, which decides the client's
 * address and DNS. The servers themselves are switched on with
 * `enableL2tpServer`, `enableSstpServer` or `enableOvpnServer`.
 *
 * @param c {Client}        an open client
 * @param name {string}     login name
 * @param password {string} login password, not empty
 * @param service {string}  "any", "l2tp", "sstp", "ovpn", "pptp" or "pppoe"
 * @param comment {string}  free-text note, "" for none
 * @return {string} the RouterOS id of the login
 * @throws {Error} kind "routeros" on an empty or spaced name, an empty
 *                 password, an unknown service, or an existing login
 * @example
 *   mt.enableL2tpServer($c, "a long ipsec secret");
 *   mt.addVpnUser($c, "alice", "her password", "any", "field laptop");
 */
export func addVpnUser(
    c as Client,
    name as string,
    password as string,
    service as string,
    comment as string) {
    ensureName($name, "VPN user");
    if (strings.trim($password) == "") {
        raiseError("the VPN user password must not be empty");
    }
    ensurePppService($service);
    if (idByName($c, PPP_SECRET_PATH, $name) != "") {
        raiseError("the VPN user \"" + $name + "\" already exists");
    }
    def attrs as map of string to string init {
        "name": $name,
        "password": $password,
        "service": $service
    };
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, PPP_SECRET_PATH, $attrs);
}

/**
 * Delete a VPN login.
 *
 * @param c {Client}    an open client
 * @param name {string} login name
 * @throws {Error} kind "routeros" when no such login exists
 */
export func removeVpnUser(c as Client, name as string) {
    remove($c, PPP_SECRET_PATH, requiredId($c, PPP_SECRET_PATH, $name, "VPN user"));
}

/**
 * Enable a VPN login.
 *
 * @param c {Client}    an open client
 * @param name {string} login name
 * @throws {Error} kind "routeros" when no such login exists
 */
export func enableVpnUser(c as Client, name as string) {
    enable($c, PPP_SECRET_PATH, requiredId($c, PPP_SECRET_PATH, $name, "VPN user"));
}

/**
 * Disable a VPN login; it is kept and can be enabled again.
 *
 * @param c {Client}    an open client
 * @param name {string} login name
 * @throws {Error} kind "routeros" when no such login exists
 */
export func disableVpnUser(c as Client, name as string) {
    disable($c, PPP_SECRET_PATH, requiredId($c, PPP_SECRET_PATH, $name, "VPN user"));
}

/**
 * List the PPP profiles.
 *
 * @param c {Client} an open client
 * @return {list of PppProfile} all profiles
 */
export func pppProfiles(c as Client) {
    def rows as list of map of string to string init getAll($c, PPP_PROFILE_PATH);
    def out as list of PppProfile init [];
    for (def row in $rows) {
        $out[] = pppProfileFromRow($row);
    }
    return $out;
}

/**
 * List the active sessions on every PPP server.
 *
 * @param c {Client} an open client
 * @return {list of PppSession} the active sessions, all server types
 */
export func pppActive(c as Client) {
    def rows as list of map of string to string init getAll($c, PPP_ACTIVE_PATH);
    def out as list of PppSession init [];
    for (def row in $rows) {
        $out[] = pppSessionFromRow($row);
    }
    return $out;
}

/**
 * Disconnect a VPN or dial-in client now.
 *
 * @param c {Client}    an open client
 * @param name {string} login whose session to end
 * @throws {Error} kind "routeros" when that login has no active session
 */
export func kickPppUser(c as Client, name as string) {
    def rows as list of map of string to string init getAll($c, PPP_ACTIVE_PATH);
    def row as map of string to string init findRowByField($rows, "name", $name);
    if (len($row) == 0) {
        raiseError("\"" + $name + "\" has no active PPP session");
    }
    remove($c, PPP_ACTIVE_PATH, rowValue($row, ".id"));
}

/**
 * Validate a PPP secret service value.
 *
 * @param service {string} the candidate
 * @throws {Error} kind "routeros" on an unknown service
 * @internal
 */
func ensurePppService(service as string) {
    if (not lists.contains(PPP_SERVICES, $service)) {
        raiseError("unknown VPN service \"" + $service + "\" - use one of: " +
            strings.join(PPP_SERVICES, ", "));
    }
}

/**
 * Add a VPN client interface that dials out to a remote server; shared
 * by the L2TP, SSTP and OpenVPN client helpers. Idempotent by name.
 *
 * @param c {Client}             an open client
 * @param path {string}          the client list path
 * @param kind {string}          VPN kind, for error messages
 * @param name {string}          client interface name
 * @param serverAddress {string} server address or DNS name
 * @param user {string}          login on the server
 * @param password {string}      login password, not empty
 * @param extra {map of string to string} additional attributes
 * @return {string} the RouterOS id of the (new or existing) client
 * @throws {Error} kind "routeros" on an empty or spaced name or user, an
 *                 empty password, or an empty or spaced server
 * @internal
 */
func vpnClientAdd(
    c as Client,
    path as string,
    kind as string,
    name as string,
    serverAddress as string,
    user as string,
    password as string,
    extra as map of string to string) {
    ensureName($name, $kind + " client");
    ensureName($user, $kind + " user");
    if (strings.trim($password) == "") {
        raiseError("the " + $kind + " password must not be empty");
    }
    def server as string init strings.trim($serverAddress);
    ensureHost($server);
    def existing as string init idByName($c, $path, $name);
    if ($existing != "") {
        return $existing;
    }
    def attrs as map of string to string init {
        "name": $name,
        "connect-to": $server,
        "user": $user,
        "password": $password
    };
    def keys as list of string init maps.keys($extra);
    for (def k in $keys) {
        $attrs[$k] = $extra[$k];
    }
    return add($c, $path, $attrs);
}

/**
 * Fold a reply row into a PppUser.
 *
 * @param row {map of string to string} a "/ppp/secret/print" row
 * @return {PppUser} the typed login
 * @internal
 */
func pppUserFromRow(row as map of string to string) {
    return PppUser{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        service: rowValue($row, "service"),
        profile: rowValue($row, "profile"),
        localAddress: rowValue($row, "local-address"),
        remoteAddress: rowValue($row, "remote-address"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * Fold a reply row into a PppProfile.
 *
 * @param row {map of string to string} a "/ppp/profile/print" row
 * @return {PppProfile} the typed profile
 * @internal
 */
func pppProfileFromRow(row as map of string to string) {
    return PppProfile{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        localAddress: rowValue($row, "local-address"),
        remoteAddress: rowValue($row, "remote-address"),
        dnsServer: rowValue($row, "dns-server"),
        disabled: rowBool($row, "disabled")
    };
}

/**
 * Fold a reply row into a PppSession.
 *
 * @param row {map of string to string} a "/ppp/active/print" row
 * @return {PppSession} the typed session
 * @internal
 */
func pppSessionFromRow(row as map of string to string) {
    return PppSession{
        name: rowValue($row, "name"),
        service: rowValue($row, "service"),
        address: rowValue($row, "address"),
        uptime: rowValue($row, "uptime"),
        callerId: rowValue($row, "caller-id")
    };
}

/**
 * RouterOS API path of the PPPoE client list (dial-in WAN).
 */
export def const PPPOE_CLIENT_PATH as string init "/interface/pppoe-client";

/** RouterOS API path of the PPPoE server service list. */
export def const PPPOE_SERVER_PATH as string init "/interface/pppoe-server/server";

/**
 * One PPPoE client: a dial-in uplink over user name and password.
 *
 * Has no password field: the password is written on setup and never read
 * back.
 *
 * @field id {string}              internal RouterOS id
 * @field name {string}            PPPoE interface name (e.g. "pppoewan")
 * @field interfaceName {string}   physical interface the session dials over
 * @field user {string}            ISP dial-in user name
 * @field usePeerDns {bool}        true when the router adopts the ISP's DNS servers
 * @field addDefaultRoute {bool}   true when the session installs the default route
 * @field running {bool}           true when the session is up
 * @field disabled {bool}          true when switched off
 * @field comment {string}         free-text comment, "" when unset
 */
export def struct PppoeClient {
    id as string,
    name as string,
    interfaceName as string,
    user as string,
    usePeerDns as bool,
    addDefaultRoute as bool,
    running as bool,
    disabled as bool,
    comment as string
};

/**
 * List every PPPoE client on the router.
 *
 * @param c {Client} an open client
 * @return {list of PppoeClient} all PPPoE clients with their session state
 */
export func pppoeClients(c as Client) {
    def rows as list of map of string to string init getAll($c, PPPOE_CLIENT_PATH);
    def out as list of PppoeClient init [];
    for (def row in $rows) {
        $out[] = pppoeFromRow($row);
    }
    return $out;
}

/**
 * Set up a PPPoE dial-in uplink (DSL, fiber).
 *
 * Creates an enabled PPPoE client on the physical WAN port that installs
 * the ISP's default route and adopts its DNS servers (change either with
 * `set` on `PPPOE_CLIENT_PATH`). Idempotent by name: an existing client
 * of that name is returned untouched.
 *
 * Once up, `name` is a routable interface: masquerade it for the LAN
 * (`addMasquerade`), not the physical port.
 *
 * @param c {Client}             an open client
 * @param name {string}          PPPoE interface name (e.g. "pppoewan"), the
 *                               handle for the other calls
 * @param interfaceName {string} physical interface of the ISP line (e.g. "ether1")
 * @param user {string}          ISP user name (e.g. "user@provider.example")
 * @param password {string}      ISP password, not empty
 * @return {string} the RouterOS id of the (new or existing) PPPoE client
 * @throws {Error} kind "routeros" on an empty or spaced name or user, an
 *                 empty password, or an unknown interface
 * @example
 *   mt.setupPppoe($c, "pppoewan", "ether1", "user@provider.example", "secret");
 *   mt.addMasquerade($c, "pppoewan", "lan to internet");
 */
export func setupPppoe(
    c as Client,
    name as string,
    interfaceName as string,
    user as string,
    password as string) {
    ensureName($name, "PPPoE client");
    ensureName($user, "PPPoE user");
    if (strings.trim($password) == "") {
        raiseError("the PPPoE password must not be empty - it comes from your ISP");
    }
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def existing as string init idByName($c, PPPOE_CLIENT_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    return add(
        $c,
        PPPOE_CLIENT_PATH,
        {
            "name": $name,
            "interface": $interfaceName,
            "user": $user,
            "password": $password,
            "add-default-route": "yes",
            "use-peer-dns": "yes",
            "disabled": "no"
        });
}

/**
 * Read the state of a PPPoE uplink.
 *
 * @param c {Client}    an open client
 * @param name {string} PPPoE interface name
 * @return {PppoeClient} the client state; `running` is true when connected
 * @throws {Error} kind "routeros" when no PPPoE client has that name
 * @example
 *   def dsl as mt.PppoeClient init mt.pppoeStatus($c, "pppoewan");
 *   if (not $dsl.running) { io.printf("dial-in is down\n"); }
 */
export func pppoeStatus(c as Client, name as string) {
    def row as map of string to string init findByName($c, PPPOE_CLIENT_PATH, $name);
    if (len($row) == 0) {
        raiseError("no PPPoE client named \"" + $name + "\" was found - set one up with setupPppoe");
    }
    return pppoeFromRow($row);
}

/**
 * Change the dial-in credentials of a PPPoE uplink.
 *
 * The session reconnects with the new user name and password.
 *
 * @param c {Client}        an open client
 * @param name {string}     PPPoE interface name
 * @param user {string}     new ISP user name
 * @param password {string} new ISP password, not empty
 * @throws {Error} kind "routeros" on an empty or spaced user, an empty
 *                 password, or an unknown client
 */
export func setPppoeCredentials(c as Client, name as string, user as string, password as string) {
    ensureName($user, "PPPoE user");
    if (strings.trim($password) == "") {
        raiseError("the PPPoE password must not be empty - it comes from your ISP");
    }
    set(
        $c,
        PPPOE_CLIENT_PATH,
        requiredId($c, PPPOE_CLIENT_PATH, $name, "PPPoE client"),
        {"user": $user, "password": $password});
}

/**
 * Remove a PPPoE client; the dial-in uplink goes away.
 *
 * @param c {Client}    an open client
 * @param name {string} PPPoE interface name
 * @throws {Error} kind "routeros" when no PPPoE client has that name
 */
export func removePppoeClient(c as Client, name as string) {
    remove($c, PPPOE_CLIENT_PATH, requiredId($c, PPPOE_CLIENT_PATH, $name, "PPPoE client"));
}

/**
 * Enable a PPPoE client; it starts dialing at once.
 *
 * @param c {Client}    an open client
 * @param name {string} PPPoE interface name
 * @throws {Error} kind "routeros" when no PPPoE client has that name
 */
export func enablePppoeClient(c as Client, name as string) {
    enable($c, PPPOE_CLIENT_PATH, requiredId($c, PPPOE_CLIENT_PATH, $name, "PPPoE client"));
}

/**
 * Disable a PPPoE client; the session disconnects.
 *
 * @param c {Client}    an open client
 * @param name {string} PPPoE interface name
 * @throws {Error} kind "routeros" when no PPPoE client has that name
 */
export func disablePppoeClient(c as Client, name as string) {
    disable($c, PPPOE_CLIENT_PATH, requiredId($c, PPPOE_CLIENT_PATH, $name, "PPPoE client"));
}

/**
 * Fold a reply row into a PppoeClient.
 *
 * @param row {map of string to string} an "/interface/pppoe-client/print" row
 * @return {PppoeClient} the typed client state
 * @internal
 */
func pppoeFromRow(row as map of string to string) {
    return PppoeClient{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        interfaceName: rowValue($row, "interface"),
        user: rowValue($row, "user"),
        usePeerDns: rowBool($row, "use-peer-dns"),
        addDefaultRoute: rowBool($row, "add-default-route"),
        running: rowBool($row, "running"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * One PPPoE server service: the router accepting PPPoE dial-ins on an
 * interface.
 *
 * @field id {string}             internal RouterOS id
 * @field serviceName {string}    PPPoE service name clients may ask for
 * @field interfaceName {string}  interface it serves on
 * @field defaultProfile {string} PPP profile applied to sessions
 * @field disabled {bool}         true when switched off
 */
export def struct PppoeServer {
    id as string,
    serviceName as string,
    interfaceName as string,
    defaultProfile as string,
    disabled as bool
};

/**
 * List the PPPoE server services.
 *
 * @param c {Client} an open client
 * @return {list of PppoeServer} all PPPoE server services
 */
export func pppoeServers(c as Client) {
    def rows as list of map of string to string init getAll($c, PPPOE_SERVER_PATH);
    def out as list of PppoeServer init [];
    for (def row in $rows) {
        $out[] = pppoeServerFromRow($row);
    }
    return $out;
}

/**
 * Run a PPPoE server on an interface, accepting dial-in clients.
 *
 * The router is the concentrator that downstream routers dial. Sessions
 * authenticate against the PPP user database: add logins with
 * `addVpnUser` and service "pppoe" or "any". Sets
 * `one-session-per-host`. Idempotent by service name and interface.
 *
 * @param c {Client}             an open client
 * @param serviceName {string}   PPPoE service name, visible to clients
 * @param interfaceName {string} interface to serve on
 * @return {string} the RouterOS id of the (new or existing) service
 * @throws {Error} kind "routeros" on an empty or spaced service name or an
 *                 unknown interface
 * @example
 *   mt.addPppoeServer($c, "office", "ether2");
 *   mt.addVpnUser($c, "branch", "a password", "pppoe", "downstream router");
 */
export func addPppoeServer(c as Client, serviceName as string, interfaceName as string) {
    ensureName($serviceName, "PPPoE service");
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    def rows as list of map of string to string init getAll($c, PPPOE_SERVER_PATH);
    for (def row in $rows) {
        if (rowValue($row, "service-name") == $serviceName and
            rowValue($row, "interface") == $interfaceName) {
            return rowValue($row, ".id");
        }
    }
    return add(
        $c,
        PPPOE_SERVER_PATH,
        {"service-name": $serviceName, "interface": $interfaceName, "one-session-per-host": "yes"});
}

/**
 * Remove a PPPoE server service by its service name.
 *
 * @param c {Client}           an open client
 * @param serviceName {string} service name
 * @throws {Error} kind "routeros" when no such service exists
 */
export func removePppoeServer(c as Client, serviceName as string) {
    def rows as list of map of string to string init getAll($c, PPPOE_SERVER_PATH);
    def row as map of string to string init findRowByField($rows, "service-name", $serviceName);
    if (len($row) == 0) {
        raiseError("no PPPoE server service named \"" + $serviceName + "\" was found");
    }
    remove($c, PPPOE_SERVER_PATH, rowValue($row, ".id"));
}

/**
 * Fold a reply row into a PppoeServer.
 *
 * @param row {map of string to string} an "/interface/pppoe-server/server/print" row
 * @return {PppoeServer} the typed service
 * @internal
 */
func pppoeServerFromRow(row as map of string to string) {
    return PppoeServer{
        id: rowValue($row, ".id"),
        serviceName: rowValue($row, "service-name"),
        interfaceName: rowValue($row, "interface"),
        defaultProfile: rowValue($row, "default-profile"),
        disabled: rowBool($row, "disabled")
    };
}
