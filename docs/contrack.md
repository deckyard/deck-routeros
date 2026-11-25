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

- `connectionsFor` and `dropConnectionsFor` compare the host part of
  each `address:port` with the address exactly: `"192.168.88.5"` does not
  match 192.168.88.50. IPv4 only; IPv6 connections are under
  `/ipv6/firewall/connection` (generic `getAll`).
- `connections(c)` returns thousands of rows on a busy router. Only the
  `Connection` properties travel, but a table past one reply's cap (about
  30,000 rows) throws kind `"limit"`. `dropConnectionsFor` reads three
  properties per row, so it reaches further.
- `dropConnectionsFor` removes up to 100 connections per command. A
  connection that times out between the read and the remove fails its
  batch with a `mikrotik` error; call it again.
- Dropping connections does not block: the host can reconnect at once.
  To keep it out, add a firewall rule ([firewall.md](firewall.md)) or
  an address-list drop ([addresslist.md](addresslist.md)), then drop
  its connections so the block applies to existing flows.
- When `totalEntries` reaches `maxEntries`, new connections are
  dropped: a scan, a P2P host or a table too small.
- NAT'd flows appear in translated form.

See also: [nat.md](nat.md), [mangle.md](mangle.md) (connection marks
appear in `connectionMark`).
