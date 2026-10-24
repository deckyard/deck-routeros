# Clock & NTP

File: `src/topics/clock.j`. Paths: `/system/clock` (`CLOCK_PATH`),
`/system/ntp/client` (`NTP_CLIENT_PATH`).
Reference: [cheatsheet](cheatsheet.md#clock--ntp).

MikroTik routers have no battery-backed clock: every boot starts at the
firmware's build date until something sets the time. A wrong clock breaks
certificate validation ([certificates.md](certificates.md)), scheduler
times ([scheduler.md](scheduler.md)) and log timestamps ([log.md](log.md)),
so `useNtp` and `setTimezone` belong in every base config, after the WAN
is up.

```jennifer
mt.useNtp($c, "pool.ntp.org");
mt.setTimezone($c, "Europe/Berlin");    # IANA name, or "UTC"; turns autodetect off
```

`synced` is true only when the NTP status is `"synchronized"`, which takes
about a minute after enabling; do not fail a provisioning script on the
first check.

```jennifer
def st as mt.NtpStatus init mt.ntpStatus($c);
if (not $st.synced) {
    io.printf("clock not synced yet (%s)\n", $st.status);
}
def ck as mt.Clock init mt.clock($c);
io.printf("router time: %s %s (%s)\n", $ck.date, $ck.time, $ck.timezone);
```

## Notes

- Servers given by DNS name need a working resolver ([dns.md](dns.md));
  on a fresh router set DNS first, or use IPs.
- The deck writes the v7 NTP client (`servers` list). RouterOS v6 has
  `primary-ntp` / `secondary-ntp` (IPs only); drive it with the generic
  verbs.
- An isolated network needs an internal NTP source. The router can serve
  NTP itself (`/system/ntp/server`, generic verbs).
