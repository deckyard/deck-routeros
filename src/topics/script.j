# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - the script repository: named RouterOS scripts.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the script repository. */
export def const SCRIPT_PATH as string init "/system/script";

/**
 * One stored RouterOS script.
 *
 * @field id {string} RouterOS item id
 * @field name {string} script name, the handle the scheduler and netwatch use
 * @field source {string} RouterOS script source
 * @field policy {string} comma-separated permissions it runs with
 * @field runCount {int} number of runs so far
 * @field lastStarted {string} time of the last run, as RouterOS prints it
 * @field comment {string} free-text comment, "" when unset
 */
export def struct Script {
    id as string,
    name as string,
    source as string,
    policy as string,
    runCount as int,
    lastStarted as string,
    comment as string
};

/**
 * List the stored scripts.
 *
 * @param c {Client} an open client
 * @return {list of Script} every script
 */
export func scripts(c as Client) {
    def rows as list of map of string to string init getAll($c, SCRIPT_PATH);
    def out as list of Script init [];
    for (def row in $rows) {
        $out[] = scriptFromRow($row);
    }
    return $out;
}

/**
 * Look up a script by name.
 *
 * @param c {Client} an open client
 * @param name {string} script name
 * @return {Script} the script
 * @throws {Error} kind "routeros" when no script has that name
 */
export func scriptByName(c as Client, name as string) {
    def row as map of string to string init findByName($c, SCRIPT_PATH, $name);
    if (len($row) == 0) {
        raiseError("the script \"" + $name + "\" was not found on the router");
    }
    return scriptFromRow($row);
}

/**
 * Store a named RouterOS script.
 *
 * The scheduler and netwatch can run it by name (`scheduleScript` takes
 * a stored script's name as its source) and `runScript` runs it on
 * demand. `source` is RouterOS script, not Jennifer.
 *
 * @param c {Client} an open client
 * @param name {string} script name, no spaces
 * @param source {string} RouterOS script source
 * @param comment {string} free-text note, "" for none
 * @return {string} the RouterOS id of the new script
 * @throws {Error} kind "routeros" on a bad name, an empty source, or a
 *         name that is already taken (use `updateScript`)
 * @example
 *   mt.addScript($c, "backup-and-mail",
 *       "/system backup save name=nightly; /tool e-mail send to=noc@example.org subject=backup file=nightly.backup");
 *   mt.runScript($c, "backup-and-mail");
 */
export func addScript(c as Client, name as string, source as string, comment as string) {
    ensureName($name, "script");
    if (strings.trim($source) == "") {
        raiseError("the script source must not be empty");
    }
    if (idByName($c, SCRIPT_PATH, $name) != "") {
        raiseError("the script \"" + $name + "\" already exists - use updateScript to change it");
    }
    def attrs as map of string to string init {"name": $name, "source": $source};
    if ($comment != "") {
        $attrs["comment"] = $comment;
    }
    return add($c, SCRIPT_PATH, $attrs);
}

/**
 * Replace the source of an existing script.
 *
 * @param c {Client} an open client
 * @param name {string} script name
 * @param source {string} new RouterOS script source
 * @throws {Error} kind "routeros" on an empty source or an unknown script
 */
export func updateScript(c as Client, name as string, source as string) {
    if (strings.trim($source) == "") {
        raiseError("the script source must not be empty");
    }
    set($c, SCRIPT_PATH, requiredId($c, SCRIPT_PATH, $name, "script"), {"source": $source});
}

/**
 * Run a stored script now, with the script's own policies.
 *
 * A typo or a missing permission in the script shows up in the router
 * log at run time, not here.
 *
 * @param c {Client} an open client
 * @param name {string} script name
 * @return {string} the script's return value, "" when it returns nothing
 * @throws {Error} kind "routeros" when no script has that name,
 *         kind "mikrotik" when the script itself errors
 */
export func runScript(c as Client, name as string) {
    return apiRun($c, SCRIPT_PATH + "/run", {".id": requiredId($c, SCRIPT_PATH, $name, "script")});
}

/**
 * Delete a stored script.
 *
 * Scheduler entries that run it by name fail afterwards; remove or
 * repoint them too.
 *
 * @param c {Client} an open client
 * @param name {string} script name
 * @throws {Error} kind "routeros" when no script has that name
 */
export func removeScript(c as Client, name as string) {
    remove($c, SCRIPT_PATH, requiredId($c, SCRIPT_PATH, $name, "script"));
}

/**
 * Fold a "/system/script/print" row into a Script.
 *
 * @param row {map of string to string} the reply row
 * @return {Script} the typed script
 * @internal
 */
func scriptFromRow(row as map of string to string) {
    return Script{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        source: rowValue($row, "source"),
        policy: rowValue($row, "policy"),
        runCount: rowInt($row, "run-count"),
        lastStarted: rowValue($row, "last-started"),
        comment: rowValue($row, "comment")
    };
}
