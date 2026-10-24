# System: packages, updates, firmware, reboot

File: `src/topics/system.j`. Paths: `/system/package`,
`/system/package/update`, `/system/routerboard`, `/system/resource`,
`/system/identity`, `/system/device-mode`.
Reference: [cheatsheet](cheatsheet.md#system).

## Two update tracks

1. **RouterOS packages**, the operating system. `installUpdates` downloads,
   installs and reboots.
2. **Routerboard firmware**, the boot loader. Every RouterOS update ships a
   matching firmware, flashed only on request (`upgradeRouterboard`) and
   active from the next reboot.

The full sequence is: check, install (reboots), reconnect, upgrade the
routerboard, reboot again. `upgradeRouterboard` flashes the firmware that
shipped with the installed RouterOS, so run it after the package update.

`UpdateStatus.updateAvailable` and `Routerboard.upgradeAvailable` are
computed by the deck: true when both versions are known and differ.

```jennifer
def st as mt.UpdateStatus init mt.checkForUpdates($c);
if ($st.updateAvailable) {
    io.printf("updating %s -> %s\n", $st.installedVersion, $st.latestVersion);
    mt.installUpdates($c);          # router reboots itself; $c is dead now
    # after the router is back:
    # def c2 as mt.Client init mt.connect($host, $user, $password);
    # if (mt.routerboard($c2).upgradeAvailable) {
    #     mt.upgradeRouterboard($c2);
    #     mt.reboot($c2);           # firmware takes effect
    # }
}
```

`checkForUpdates` needs internet access and working DNS on the router
([dns.md](dns.md)); a failure is `kind: "mikrotik"` with the updater's
message.

## Status

```jennifer
def info as mt.SystemInfo init mt.systemInfo($c);
io.printf("%s: RouterOS %s on %s, up %s, cpu %s\n",
    mt.identity($c), $info.version, $info.boardName, $info.uptime, $info.cpuLoad);
```

Values are verbatim strings (`"7.15.2 (stable)"`, `"2w3d4h5m6s"`); the deck
does no version comparison beyond equality.

## Commands that drop the connection

`installUpdates`, `reboot` and `shutdown` succeed by killing the
connection. A router refusal (`!trap`, e.g. the user lacks the `reboot`
policy) is re-thrown as `Error{kind: "mikrotik"}`; any other error from
the dropped connection is swallowed. The `Client` is unusable afterwards;
reconnect with `mt.connect`. `shutdown` needs someone on site to power the
router back on.

## Device mode

RouterOS gates the features that can run code (scheduler, `/tool/fetch`,
e-mail, containers) behind a device mode. In `home` mode those menus are
reported as missing, not refused, so check the mode first when a feature
seems absent:

```jennifer
def d as mt.DeviceMode init mt.deviceMode($c);
io.printf("mode=%s scheduler=%t container=%t\n", $d.mode, $d.scheduler, $d.container);
```

`updateDeviceMode` only makes a change pending:

```jennifer
mt.updateDeviceMode($c, mt.DEVICE_MODE_ADVANCED);
```

The router applies it when someone power-cycles it (a cold boot, not
`reboot`) or presses the reset button within a few minutes. Otherwise the
request is discarded silently. A remote script cannot complete it.

See also [scheduler.md](scheduler.md) for a nightly backup before
updating.
