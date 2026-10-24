# Files & backups

File: `src/topics/files.j`. Path: `/file` (`FILE_PATH`), plus the
`/system/backup/save` command.
Reference: [cheatsheet](cheatsheet.md#files--backups).

## Backups

A `.backup` file is a binary snapshot of the whole configuration,
password hashes and keys included. Encrypt anything that leaves the
router with `saveBackupWith`, and keep the password: an encrypted backup
cannot be restored without it. Both save verbs check that
`<name>.backup` appeared and throw `kind: "routeros"` if not (usually a
full storage).

```jennifer
mt.saveBackupWith($c, "before-fw-rework", "a strong password");

# a daily encrypted backup run by the router (scheduler topic)
mt.scheduleDaily($c, "nightly-backup", "03:00:00",
    "/system backup save name=nightly password=backupsecret");

# check it from the host
def fs as list of mt.RouterFile init mt.files($c);
for (def f in $fs) {
    if ($f.name == "nightly.backup") {
        io.printf("backup: %d bytes, created %s\n", $f.size, $f.creationTime);
    }
}
```

Restoring (`/system backup load`) is not wrapped: it reboots the router
into the backup's identity (addresses, users, keys). Do it from the
console or WinBox. Backups are bound to the model and a close RouterOS
version; for a portable config use the console `/export`, which the API
cannot reach.

## Small text files

RouterOS v7 exposes a file's `contents` through the API for small files
(a few KB). `readFileText` returns `""` for larger ones; bulk transfer
needs FTP or SFTP. `writeFileText` creates or overwrites a file and is
how `importCertificatePem` moves PEMs to the router.

```jennifer
mt.writeFileText($c, "note.txt", "rack 3, top unit");
io.printf("%s\n", mt.readFileText($c, "note.txt"));
mt.removeFile($c, "note.txt");
```

Flash storage wears; avoid high-frequency writes.
