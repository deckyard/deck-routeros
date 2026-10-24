# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - files and backups.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the file list. */
export def const FILE_PATH as string init "/file";

/**
 * One file on the router's storage.
 *
 * @field name {string}         file name (with extension, e.g. "nightly.backup")
 * @field kind {string}         file type as reported ("backup", ".txt file", "directory", ...)
 * @field size {int}         size in bytes
 * @field creationTime {string} when it was created, as reported
 */
export def struct RouterFile {
    name as string,
    kind as string,
    size as int,
    creationTime as string
};

/**
 * List the files on the router.
 *
 * @param c {Client} an open client
 * @return {list of RouterFile} all files and directories
 */
export func files(c as Client) {
    def rows as list of map of string to string init getAll($c, FILE_PATH);
    def out as list of RouterFile init [];
    for (def row in $rows) {
        $out[] = fileFromRow($row);
    }
    return $out;
}

/**
 * Save a full configuration backup (unencrypted).
 *
 * Writes `<name>.backup` to the router's storage and checks that it
 * exists before returning. The backup holds the whole configuration,
 * password hashes and keys included: use `saveBackupWith` for anything
 * that leaves the router. Restoring (`/system backup load`) is not
 * wrapped; it reboots into a possibly different identity.
 *
 * @param c {Client}    an open client
 * @param name {string} backup name without extension (e.g. "nightly")
 * @throws {Error} kind "routeros" on a bad name or when the file did
 *                 not appear (e.g. storage full)
 */
export func saveBackup(c as Client, name as string) {
    ensureName($name, "backup");
    apiRun($c, "/system/backup/save", {"name": $name});
    ensureBackupExists($c, $name);
}

/**
 * Save a configuration backup encrypted with a password.
 *
 * @param c {Client}        an open client
 * @param name {string}     backup name without extension
 * @param password {string} encryption password (needed again to restore)
 * @throws {Error} kind "routeros" on a bad name, an empty password, or
 *                 when the file did not appear
 */
export func saveBackupWith(c as Client, name as string, password as string) {
    ensureName($name, "backup");
    if (strings.trim($password) == "") {
        raiseError("the backup password must not be empty - use saveBackup for an unencrypted backup");
    }
    apiRun($c, "/system/backup/save", {"name": $name, "password": $password});
    ensureBackupExists($c, $name);
}

/**
 * Read a small text file's contents.
 *
 * RouterOS exposes the contents of small files (a few KB) only, enough
 * for scripts, notes and PEMs; it is not a download mechanism.
 *
 * @param c {Client}    an open client
 * @param name {string} the file name (with extension)
 * @return {string} the contents ("" when the file is too large to expose)
 * @throws {Error} kind "routeros" when no such file exists
 */
export func readFileText(c as Client, name as string) {
    def rows as list of map of string to string init getAll($c, FILE_PATH);
    def row as map of string to string init findRowByField($rows, "name", $name);
    if (len($row) == 0) {
        raiseError("the file \"" + $name + "\" was not found on the router");
    }
    return rowValue($row, "contents");
}

/**
 * Create or overwrite a small text file on the router (RouterOS v7).
 *
 * `importCertificatePem` uses it to transfer PEMs.
 *
 * @param c {Client}        an open client
 * @param name {string}     the file name (with extension)
 * @param contents {string} the text to write
 * @throws {Error} kind "routeros" on a bad name
 */
export func writeFileText(c as Client, name as string, contents as string) {
    ensureName($name, "file");
    def rows as list of map of string to string init getAll($c, FILE_PATH);
    def existing as map of string to string init findRowByField($rows, "name", $name);
    if (len($existing) > 0) {
        set($c, FILE_PATH, rowValue($existing, ".id"), {"contents": $contents});
    } else {
        add($c, FILE_PATH, {"name": $name, "contents": $contents});
    }
}

/**
 * Delete a file from the router's storage.
 *
 * @param c {Client}    an open client
 * @param name {string} the file name (with extension)
 * @throws {Error} kind "routeros" when no such file exists
 */
export func removeFile(c as Client, name as string) {
    def rows as list of map of string to string init getAll($c, FILE_PATH);
    def row as map of string to string init findRowByField($rows, "name", $name);
    if (len($row) == 0) {
        raiseError("the file \"" + $name + "\" was not found on the router");
    }
    remove($c, FILE_PATH, rowValue($row, ".id"));
}

/**
 * Verify a named backup file exists, or raise.
 *
 * @param c {Client}    an open client
 * @param name {string} the backup name without extension
 * @throws {Error} kind "routeros" when `<name>.backup` is missing
 * @internal
 */
func ensureBackupExists(c as Client, name as string) {
    def rows as list of map of string to string init getAll($c, FILE_PATH);
    def row as map of string to string init findRowByField($rows, "name", $name + ".backup");
    if (len($row) == 0) {
        raiseError("the backup \"" + $name + ".backup\" did not appear - check free storage");
    }
}

/**
 * Fold a reply row into a RouterFile.
 *
 * @param row {map of string to string} a "/file/print" row
 * @return {RouterFile} the typed file
 * @internal
 */
func fileFromRow(row as map of string to string) {
    return RouterFile{
        name: rowValue($row, "name"),
        kind: rowValue($row, "type"),
        size: rowInt($row, "size"),
        creationTime: rowValue($row, "creation-time")
    };
}
