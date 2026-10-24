<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Neighbor discovery

File: `src/topics/neighbor.j`. Path: `/ip/neighbor` (`NEIGHBOR_PATH`).
Reference: [cheatsheet](cheatsheet.md#neighbor-discovery).

The router collects the discovery announcements of directly connected
devices: MNDP (MikroTik), CDP (Cisco) and LLDP (most vendors). The list
shows the switch on ether2 or the upstream router without a scan. Devices
behind another router never appear.

## Examples

```jennifer
def ns as list of mt.Neighbor init mt.neighbors($c);
for (def n in $ns) {
    io.printf("%s: %s %s (%s) at %s on %s\n",
        $n.identity, $n.platform, $n.board, $n.version, $n.address, $n.interfaceName);
}

def up as list of mt.Neighbor init mt.neighborsOn($c, "ether1");
for (def n in $up) { io.printf("upstream: %s (%s)\n", $n.identity, $n.address); }
```

## Pitfalls

- A neighbor with an empty `address` was heard at layer 2 but has no IP
  on this segment. That is normal.
- The router hears (and is heard) only on interfaces where discovery is
  enabled. It is on by default; a hardened config may restrict it under
  `/ip/neighbor/discovery-settings` (generic verbs). Turn it off on
  untrusted and WAN interfaces: it announces your model and version.
- Devices that do not announce themselves (most PCs and servers) never
  appear. For IP-to-MAC presence use [the ARP table](arp.md).

See also: [services.md](services.md) for locking down the WAN side.
