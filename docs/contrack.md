<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Connection tracking

File: `src/topics/contrack.j`. Paths:
`/ip/firewall/connection/tracking` (`CONNTRACK_SETTINGS_PATH`),
`/ip/firewall/connection` (`CONNECTION_PATH`).
Reference: [cheatsheet](cheatsheet.md#connection-tracking).

Connection tracking is the state behind stateful filtering and NAT:
every flow the router has seen, with addresses, protocol and, for TCP,
state. Reading it shows what a device is talking to and whether the
table is filling up.

## Examples

Table fill:

```jennifer
def s as mt.ConntrackSettings init mt.conntrackSettings($c);
io.printf("%d of %d connections (%d%% full)\n",
    $s.totalEntries, $s.maxEntries, $s.totalEntries * 100 // $s.maxEntries);
```

One device's flows:

```jennifer
def conns as list of mt.Connection init mt.connectionsFor($c, "192.168.88.50");
for (def con in $conns) {
    io.printf("%s %s -> %s %s\n", $con.protocol, $con.srcAddress, $con.dstAddress, $con.tcpState);
}
```

Reset a host's flows, e.g. after a routing change:

```jennifer
def n as int init mt.dropConnectionsFor($c, "192.168.88.55");
io.printf("dropped %d connections\n", $n);
```

## Pitfalls

- `connectionsFor` and `dropConnectionsFor` match by substring on the
  `address:port` strings, not by exact host. `"192.168.88.5"` also
  matches 192.168.88.50-59, so `dropConnectionsFor` can drop other
  hosts' connections.
  For an exact match, filter `connections(c)` on `srcAddress` /
  `dstAddress` and remove by id with the generic `remove`.
- `connections(c)` returns thousands of rows on a busy router.
- Dropping connections does not block: the host can reconnect at once.
  To keep it out, add a firewall rule ([firewall.md](firewall.md)) or
  an address-list drop ([addresslist.md](addresslist.md)), then drop
  its connections so the block applies to existing flows.
- When `totalEntries` reaches `maxEntries`, new connections are
  dropped: a scan, a P2P host or a table too small.
- NAT'd flows appear in translated form.

See also: [nat.md](nat.md), [mangle.md](mangle.md) (connection marks
appear in `connectionMark`).
