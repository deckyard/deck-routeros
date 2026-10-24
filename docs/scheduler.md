# Scheduler: scripts on a timer

File: `src/topics/scheduler.j`. Path: `/system/scheduler`
(`SCHEDULER_PATH`). Reference: [cheatsheet](cheatsheet.md#scheduler).

The scheduler runs RouterOS script on the router itself, so a nightly
backup or a watchdog keeps working while your management host is down.
A task's `on-event` is either script source or the name of a stored
`/system/script` (see [script.md](script.md)). routeros has one call per
shape: every interval (`scheduleScript`), daily at a time
(`scheduleDaily`), once per boot (`scheduleAtStartup`).

Intervals are validated locally: `"30s"`, `"10m"`, `"2h"`, `"1d"`, `"1w"`,
combinations such as `"1d12h"`, bare seconds (`"90"`), or `"HH:MM:SS"`.
Daily times must be `"HH:MM:SS"` (hours 0-23, minutes and seconds 0-59).

## Examples

Nightly configuration backup at 03:00:

```jennifer
mt.scheduleDaily($c, "nightly-backup", "03:00:00", "/system backup save name=nightly");
```

Reboot when the uplink has been gone for good:

```jennifer
mt.scheduleScript($c, "uplink-watchdog", "10m",
    ":if ([/ping 1.1.1.1 count=5] = 0) do={/system reboot}");
```

Log a marker at every boot:

```jennifer
mt.scheduleAtStartup($c, "boot-marker", ":log info \"booted\"");
```

Check that tasks run:

```jennifer
def tasks as list of mt.ScheduledTask init mt.scheduledTasks($c);
for (def t in $tasks) {
    io.printf("%s: every %s, next %s, ran %d times\n",
        $t.name, $t.interval, $t.nextRun, $t.runCount);
}
```

## Pitfalls

- routeros validates the timing, not the script. A typo shows up in the
  router log when the task fires. Try one-liners in the RouterOS
  terminal first.
- A task runs with the policies of the user who created it (the user
  this client logged in as). A user without the `reboot` policy creates
  a reboot task that fails silently every night.
- `runCount == 0` long after `nextRun` has passed means the task errored;
  check the router log ([log.md](log.md)).
- Times are router-local. Set the clock, timezone or NTP
  ([clock.md](clock.md)) before relying on a 03:00 backup.
- RouterOS quotes inside the source need `\"` in a Jennifer string.
