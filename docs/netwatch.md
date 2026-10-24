# Netwatch: host monitoring

File: `src/topics/netwatch.j`. Path: `/tool/netwatch`
(`NETWATCH_PATH`). Reference: [cheatsheet](cheatsheet.md#netwatch).

`ping` ([tools.md](tools.md)) asks whether the router reaches a host now.
Netwatch keeps asking: the router probes each watched host on an
interval, records its state (`up`, `down`, `unknown`) and when it last
changed, and can run a RouterOS script on each transition. Scripts fire
once per transition, not once per probe, and keep working while your
management host is off.

Entries have no names; every call is keyed by the watched host address.
The `watchHost*` calls are idempotent: when the host is already watched
they return the existing id and leave that entry's interval and scripts
as they are.

## Examples

Watch some hosts:

```jennifer
mt.watchHost($c, "192.168.88.50", "printer");
mt.watchHostWith($c, "192.168.88.10", "10s", "file server");
mt.watchHost($c, "1.1.1.1", "internet reachability");
```

What is down right now:

```jennifer
def down as list of mt.NetwatchHost init mt.downHosts($c);
for (def d in $down) {
    io.printf("%s (%s) down since %s\n", $d.host, $d.comment, $d.since);
}
```

Alert into the router log (and from there to syslog, see
[log.md](log.md)):

```jennifer
mt.watchHostScripted($c, "192.168.88.10",
    ":log warning \"file server went down\"",
    ":log info \"file server is back\"",
    "file server");
```

Power-cycle a hung PoE camera when it stops answering (PoE in
[ethernet.md](ethernet.md)):

```jennifer
mt.watchHostScripted($c, "192.168.88.60",
    "/interface ethernet set ether5 poe-out=off; :delay 3; /interface ethernet set ether5 poe-out=auto-on",
    "",
    "camera watchdog");
```

## Pitfalls

- routeros validates the host and interval, not the scripts. A typo
  shows up in the router log when the state flips. Try one-liners in the
  RouterOS terminal first.
- Scripts run with netwatch's own policies, restricted on v7. A script
  that needs `reboot` or `write` may do nothing; check the log after a
  test flip.
- The default probe is ICMP ping, so a host that drops ICMP looks down.
  RouterOS v7 has other probe types (`http-get`, `tcp-conn`), settable
  with the generic `set`.
- `status == "unknown"` right after adding is normal (first probe
  pending); `downHosts` leaves those out.
- Many hosts at short intervals load small routers; 10s is enough for
  most uses.

See also [scheduler.md](scheduler.md) for time-based automation.
