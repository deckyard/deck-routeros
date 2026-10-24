# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - management services (/ip/service).
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the management service list. */
export def const SERVICE_PATH as string init "/ip/service";

def const KNOWN_SERVICES as list of string init [
    "api",
    "api-ssl",
    "ftp",
    "ssh",
    "telnet",
    "winbox",
    "www",
    "www-ssl"
];

/**
 * One management service: a way to log into the router.
 *
 * The list is fixed: services are enabled, disabled, moved and
 * restricted, never added or removed.
 *
 * @field id {string}          internal RouterOS id
 * @field name {string}        service name ("api", "ssh", "winbox", ...)
 * @field port {int}        TCP port it listens on
 * @field address {string}     networks allowed to connect, "" for anywhere
 * @field certificate {string} TLS certificate name (ssl services), "" otherwise
 * @field invalid {bool}     true when misconfigured (e.g. ssl without a
 *                             certificate); the service is not listening
 * @field disabled {bool}    true when the service is switched off
 */
export def struct Service {
    id as string,
    name as string,
    port as int,
    address as string,
    certificate as string,
    invalid as bool,
    disabled as bool
};

/**
 * List the management services and their state.
 *
 * Enabled, unrestricted cleartext services (telnet, ftp, www, api) are
 * the ones to review.
 *
 * @param c {Client} an open client
 * @return {list of Service} all services
 */
export func services(c as Client) {
    def rows as list of map of string to string init getAll($c, SERVICE_PATH);
    def out as list of Service init [];
    for (def row in $rows) {
        $out[] = serviceFromRow($row);
    }
    return $out;
}

/**
 * Look one management service up by its name.
 *
 * @param c {Client}    an open client
 * @param name {string} "api", "api-ssl", "ftp", "ssh", "telnet",
 *                      "winbox", "www", or "www-ssl"
 * @return {Service} the service
 * @throws {Error} kind "routeros" on an unknown service name
 */
export func serviceByName(c as Client, name as string) {
    ensureServiceName($name);
    def row as map of string to string init findByName($c, SERVICE_PATH, $name);
    if (len($row) == 0) {
        raiseError("the service \"" + $name + "\" was not found on the router");
    }
    return serviceFromRow($row);
}

/**
 * Switch a management service on.
 *
 * @param c {Client}    an open client
 * @param name {string} the service name
 * @throws {Error} kind "routeros" on an unknown service name
 */
export func enableService(c as Client, name as string) {
    ensureServiceName($name);
    enable($c, SERVICE_PATH, requiredId($c, SERVICE_PATH, $name, "service"));
}

/**
 * Switch a management service off.
 *
 * Disabling the service this session uses ("api" or "api-ssl")
 * disconnects it and locks the deck out. Turn "api" off from an api-ssl
 * session, and keep one other working way in (winbox or ssh).
 *
 * @param c {Client}    an open client
 * @param name {string} the service name
 * @throws {Error} kind "routeros" on an unknown service name
 */
export func disableService(c as Client, name as string) {
    ensureServiceName($name);
    disable($c, SERVICE_PATH, requiredId($c, SERVICE_PATH, $name, "service"));
}

/**
 * Move a management service to another TCP port.
 *
 * A non-default SSH or WinBox port cuts scanner noise but is not
 * protection; combine it with `restrictService`. A port another service
 * uses is refused, naming that service.
 *
 * @param c {Client}    an open client
 * @param name {string} the service name
 * @param port {int} the new port, 1-65535
 * @throws {Error} kind "routeros" on an unknown service, a bad port,
 *                 or a port another service already uses
 */
export func setServicePort(c as Client, name as string, port as int) {
    ensureServiceName($name);
    ensurePort($port);
    def rows as list of map of string to string init getAll($c, SERVICE_PATH);
    def owner as string init serviceUsingPort($rows, $port, $name);
    if ($owner != "") {
        raiseError("port " + convert.toString($port) + " is already used by the service \"" +
            $owner + "\"");
    }
    set(
        $c,
        SERVICE_PATH,
        requiredId($c, SERVICE_PATH, $name, "service"),
        {"port": convert.toString($port)});
}

/**
 * Limit where a management service accepts connections from.
 *
 * Applies to new connections. Before restricting the API service this
 * session uses, include your own network. Pass "" to lift the
 * restriction.
 *
 * @param c {Client}         an open client
 * @param name {string}      the service name
 * @param addresses {string} allowed sources: IPs and/or CIDR networks,
 *                           comma-separated (e.g. "10.0.9.0/24"); "" = anywhere
 * @throws {Error} kind "routeros" on an unknown service or malformed address
 * @example
 *   mt.restrictService($c, "winbox", "10.0.9.0/24");
 *   mt.restrictService($c, "ssh", "10.0.9.0/24");
 */
export func restrictService(c as Client, name as string, addresses as string) {
    ensureServiceName($name);
    def allowed as string init "";
    if (strings.trim($addresses) != "") {
        $allowed = normalizedUserAddress($addresses);
    }
    set($c, SERVICE_PATH, requiredId($c, SERVICE_PATH, $name, "service"), {"address": $allowed});
}

/**
 * Switch off telnet and ftp.
 *
 * Both send passwords in cleartext and are replaced by ssh and sftp/scp.
 * Neither carries this API session, so the call cannot lock the deck
 * out. Plain "www" and "api" are cleartext too but left alone; use
 * `disableService` for them.
 *
 * @param c {Client} an open client
 * @return {int} how many services were switched off (already-disabled
 *               ones are skipped)
 */
export func disableInsecureServices(c as Client) {
    def rows as list of map of string to string init getAll($c, SERVICE_PATH);
    def count as int init 0;
    for (def row in $rows) {
        def name as string init rowValue($row, "name");
        if (($name == "telnet" or $name == "ftp") and not rowBool($row, "disabled")) {
            disable($c, SERVICE_PATH, rowValue($row, ".id"));
            $count = $count + 1;
        }
    }
    return $count;
}

/**
 * Validate a management service name.
 *
 * @param name {string} the candidate
 * @throws {Error} kind "routeros" on an unknown service
 * @internal
 */
func ensureServiceName(name as string) {
    if (not lists.contains(KNOWN_SERVICES, $name)) {
        raiseError("unknown service \"" + $name + "\" - use one of: " +
            strings.join(KNOWN_SERVICES, ", "));
    }
}

/**
 * Find the service, other than `ownName`, that listens on a port.
 *
 * @param rows {list of map of string to string} "/ip/service/print" rows
 * @param port {int}    the port to check
 * @param ownName {string} service whose own port does not count
 * @return {string} the owning service's name, or "" when the port is free
 * @internal
 */
func serviceUsingPort(rows as list of map of string to string, port as int, ownName as string) {
    for (def row in $rows) {
        if (rowInt($row, "port") == $port and rowValue($row, "name") != $ownName) {
            return rowValue($row, "name");
        }
    }
    return "";
}

/**
 * Fold a reply row into a Service.
 *
 * @param row {map of string to string} an "/ip/service/print" row
 * @return {Service} the typed service
 * @internal
 */
func serviceFromRow(row as map of string to string) {
    return Service{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        port: rowInt($row, "port"),
        address: rowValue($row, "address"),
        certificate: rowValue($row, "certificate"),
        invalid: rowBool($row, "invalid"),
        disabled: rowBool($row, "disabled")
    };
}
