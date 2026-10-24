# Mangle: packet marking

File: `src/topics/mangle.j`. Path: `/ip/firewall/mangle`
(`MANGLE_PATH`). Chains: `CHAIN_PREROUTING`, `CHAIN_POSTROUTING`, plus
input, forward and output.
Reference: [cheatsheet](cheatsheet.md#mangle).

Mangle rules accept and drop nothing; they label traffic for other
subsystems:

- a packet mark lets a queue select traffic regardless of addresses;
- a routing mark sends traffic to another routing table (policy
  routing);
- `change-mss` repairs TCP over small-MTU links (PPPoE, tunnels).

`setupPacketMark` builds RouterOS's two-rule pattern: mark the
connection once while it is new, then mark every packet of marked
connections, which is cheaper than matching each packet. The matcher is
a firewall-builder `FirewallRule` ([firewall.md](firewall.md)): its
chain is kept, its action and comment are replaced.

The setup verbs are idempotent, keyed by the comments they write:
`"mark: <name> (connections)"` / `"mark: <name> (packets)"`,
`"route mark: <name> for <source>"`, `"mss clamp: <interface> (out)"` /
`"(in)"`. Re-running a provisioning script adds nothing. The remove
verbs find their rules by the same comments.

## Examples

VoIP first: mark SIP/RTP and point a simple queue at the mark:

```jennifer
def m as mt.FirewallRule init mt.firewallRule(mt.CHAIN_PREROUTING, mt.ACTION_ACCEPT);
$m = mt.withProtocol($m, "udp");
$m = mt.withDstPort($m, "5060-5200");
mt.setupPacketMark($c, "voip", $m);

mt.limitBandwidth($c, "qvoip", "192.168.88.0/24", "0", "0");
mt.set($c, mt.QUEUE_SIMPLE_PATH,
    mt.idByName($c, mt.QUEUE_SIMPLE_PATH, "qvoip"),
    {"packet-marks": "voip", "priority": "1/1"});
```

One subnet uses the backup uplink (RouterOS v7):

```jennifer
mt.add($c, mt.ROUTING_TABLE_PATH, {"name": "backupisp", "fib": ""});
mt.add($c, mt.ROUTE_PATH, {"dst-address": "0.0.0.0/0",
    "gateway": "198.51.100.1", "routing-table": "backupisp"});
mt.markRoutingFor($c, "backupisp", "10.30.0.0/24");
```

Pages that half-load over PPPoE:

```jennifer
mt.clampTcpMss($c, "pppoewan");
```

## Pitfalls

- A mark needs a consumer: a queue matching the packet mark, a routing
  table for the routing mark.
- On the default firewall, fasttrack bypasses mangle for established
  connections. If marks have no effect, check fasttrack first
  ([queues.md](queues.md)).
- Queue marks belong in `CHAIN_PREROUTING`; in another chain they miss
  traffic in one direction.
- Marked traffic is looked up only in the marked table. A destination
  that table has no route for is unreachable for the marked source, so
  give the table a default route.
- The packet-mark rule has `passthrough=no`, so later mangle rules do
  not re-mark those packets; the connection rule passes through.

See also: [routing.md](routing.md), [ppp.md](ppp.md) and
[gre.md](gre.md) (where MSS clamping matters).
