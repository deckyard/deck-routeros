# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - netwatch: the router keeps an eye on hosts for you.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the netwatch host list. */
export def const NETWATCH_PATH as string init "/tool/netwatch";

/**
 * One watched host and its current state.
 *
 * @field id {string} RouterOS item id
 * @field host {string} watched address
 * @field status {string} "up", "down", or "unknown" (not probed yet)
 * @field up {bool} computed: whether status is "up"
 * @field since {string} when the current state began, as RouterOS prints it
 * @field interval {string} time between probes, as RouterOS prints it
 * @field timeout {string} probe timeout, as RouterOS prints it
 * @field upScript {string} RouterOS script run when the host comes up, "" for none
 * @field downScript {string} RouterOS script run when the host goes down, "" for none
 * @field disabled {bool} whether the watch is switched off
 * @field comment {string} free-text comment, "" when unset
 */
export def struct NetwatchHost {
    id as string,
    host as string,
    status as string,
    up as bool,
    since as string,
    interval as string,
    timeout as string,
    upScript as string,
    downScript as string,
    disabled as bool,
    comment as string
};

/**
 * List the watched hosts with their current state.
 *
 * @param c {Client} an open client
 * @return {list of NetwatchHost} every netwatch entry
 */
export func netwatchHosts(c as Client) {
    def rows as list of map of string to string init getAll($c, NETWATCH_PATH);
    def out as list of NetwatchHost init [];
    for (def row in $rows) {
        $out[] = netwatchFromRow($row);
    }
    return $out;
}

/**
 * Start watching a host at the router's default probe interval.
 *
 * Idempotent: when the host is already watched, the existing entry's id
 * is returned and the entry is left unchanged.
 *
 * @param c {Client} an open client
 * @param host {string} address to watch, e.g. "192.168.88.50"
 * @param comment {string} free-text note, "" for none
 * @return {string} the RouterOS id of the new or existing entry
 * @throws {Error} kind "routeros" on an empty host or one containing spaces
 * @example
 *   mt.watchHost($c, "192.168.88.50", "printer");
 */
export func watchHost(c as Client, host as string, comment as string) {
    return netwatchAdd($c, $host, "", "", "", $comment);
}

/**
 * Start watching a host, probing every `interval`.
 *
 * Idempotent like `watchHost`: an existing entry keeps its interval.
 *
 * @param c {Client} an open client
 * @param host {string} address to watch
 * @param interval {string} "10s", "1m", "5m", combined "1m30s", or "HH:MM:SS"
 * @param comment {string} free-text note, "" for none
 * @return {string} the RouterOS id of the new or existing entry
 * @throws {Error} kind "routeros" on a bad host or interval
 */
export func watchHostWith(c as Client, host as string, interval as string, comment as string) {
    def every as string init strings.trim($interval);
    ensureSchedulerInterval($every);
    return netwatchAdd($c, $host, $every, "", "", $comment);
}

/**
 * Watch a host and run RouterOS scripts when its state flips.
 *
 * The scripts run on the router (RouterOS script, not Jennifer), once
 * per transition: log, send mail, change a route, power-cycle a PoE
 * port. At least one must be given. Idempotent like `watchHost`: an
 * existing entry keeps its scripts.
 *
 * @param c {Client} an open client
 * @param host {string} address to watch
 * @param downScript {string} RouterOS script run when the host goes down, "" for none
 * @param upScript {string} RouterOS script run when it comes back, "" for none
 * @param comment {string} free-text note, "" for none
 * @return {string} the RouterOS id of the new or existing entry
 * @throws {Error} kind "routeros" on a bad host or when both scripts are empty
 * @example
 *   mt.watchHostScripted($c, "192.168.88.50",
 *       ":log warning \"printer went down\"",
 *       ":log info \"printer is back\"",
 *       "printer");
 */
export func watchHostScripted(
    c as Client,
    host as string,
    downScript as string,
    upScript as string,
    comment as string) {
    if (strings.trim($downScript) == "" and strings.trim($upScript) == "") {
        raiseError("give at least one of downScript / upScript - otherwise use watchHost");
    }
    return netwatchAdd($c, $host, "", $downScript, $upScript, $comment);
}

/**
 * Read the state of one watched host.
 *
 * @param c {Client} an open client
 * @param host {string} watched address
 * @return {NetwatchHost} the entry; check `up` and `since`
 * @throws {Error} kind "routeros" when the host is not being watched
 */
export func hostStatus(c as Client, host as string) {
    def rows as list of map of string to string init getAll($c, NETWATCH_PATH);
    def row as map of string to string init findRowByField($rows, "host", strings.trim($host));
    if (len($row) == 0) {
        raiseError("\"" + $host + "\" is not being watched - start with watchHost");
    }
    return netwatchFromRow($row);
}

/**
 * List the watched hosts that are down right now.
 *
 * Hosts in "unknown" state (added, not probed yet) are not included.
 *
 * @param c {Client} an open client
 * @return {list of NetwatchHost} the down hosts, with their `since`
 */
export func downHosts(c as Client) {
    def all as list of NetwatchHost init netwatchHosts($c);
    def out as list of NetwatchHost init [];
    for (def entry in $all) {
        if ($entry.status == "down") {
            $out[] = $entry;
        }
    }
    return $out;
}

/**
 * Stop watching a host and forget its entry.
 *
 * @param c {Client} an open client
 * @param host {string} watched address
 * @throws {Error} kind "routeros" when the host is not being watched
 */
export func unwatchHost(c as Client, host as string) {
    remove($c, NETWATCH_PATH, requiredNetwatchId($c, $host));
}

/**
 * Pause the watch on a host (entry and scripts kept).
 *
 * @param c {Client} an open client
 * @param host {string} watched address
 * @throws {Error} kind "routeros" when the host is not being watched
 */
export func disableWatch(c as Client, host as string) {
    disable($c, NETWATCH_PATH, requiredNetwatchId($c, $host));
}

/**
 * Resume the watch on a host.
 *
 * @param c {Client} an open client
 * @param host {string} watched address
 * @throws {Error} kind "routeros" when the host is not being watched
 */
export func enableWatch(c as Client, host as string) {
    enable($c, NETWATCH_PATH, requiredNetwatchId($c, $host));
}

/**
 * Validate the host and create a netwatch entry, or reuse an existing one.
 *
 * @param c {Client} an open client
 * @param host {string} address to watch
 * @param interval {string} probe interval, "" for the router default
 * @param downScript {string} on-down script, "" for none
 * @param upScript {string} on-up script, "" for none
 * @param comment {string} free-text note, "" for none
 * @return {string} the RouterOS id of the new or existing entry
 * @throws {Error} kind "routeros" on a bad host
 * @internal
 */
func netwatchAdd(
    c as Client,
    host as string,
    interval as string,
    downScript as string,
    upScript as string,
    comment as string) {
    def target as string init strings.trim($host);
    ensureHost($target);
    def rows as list of map of string to string init getAll($c, NETWATCH_PATH);
    def existing as map of string to string init findRowByField($rows, "host", $target);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    def attrs as map of string to string init {"host": $target};
    if ($interval != "") {
        $attrs["interval"] = $interval;
    }
    if (strings.trim($downScript) != "") {
        $attrs["down-script"] = $downScript;
    }
    if (strings.trim($upScript) != "") {
        $attrs["up-script"] = $upScript;
    }
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, NETWATCH_PATH, $attrs);
}

/**
 * Resolve a watched host to its entry id.
 *
 * @param c {Client} an open client
 * @param host {string} watched address
 * @return {string} the entry id
 * @throws {Error} kind "routeros" when the host is not being watched
 * @internal
 */
func requiredNetwatchId(c as Client, host as string) {
    def rows as list of map of string to string init getAll($c, NETWATCH_PATH);
    def row as map of string to string init findRowByField($rows, "host", strings.trim($host));
    if (len($row) == 0) {
        raiseError("\"" + $host + "\" is not being watched - start with watchHost");
    }
    return rowValue($row, ".id");
}

/**
 * Fold a "/tool/netwatch/print" row into a NetwatchHost; `up` is
 * computed from the status.
 *
 * @param row {map of string to string} the reply row
 * @return {NetwatchHost} the typed entry
 * @internal
 */
func netwatchFromRow(row as map of string to string) {
    def status as string init rowValue($row, "status");
    return NetwatchHost{
        id: rowValue($row, ".id"),
        host: rowValue($row, "host"),
        status: $status,
        up: $status == "up",
        since: rowValue($row, "since"),
        interval: rowValue($row, "interval"),
        timeout: rowValue($row, "timeout"),
        upScript: rowValue($row, "up-script"),
        downScript: rowValue($row, "down-script"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
