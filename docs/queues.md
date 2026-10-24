# Simple queues and queue trees

File: `src/topics/queues.j`. Paths: `/queue/simple` (`QUEUE_SIMPLE_PATH`),
`/queue/tree` (`QUEUE_TREE_PATH`). Reference:
[cheatsheet](cheatsheet.md#simple-queues).

## Simple queues

A simple queue caps how fast a target (a device, a network, an
interface, or a comma-separated mix) sends and receives. **Upload** is
traffic from the target, **download** is traffic to it. Interface names
in a target are checked against the router.

Rates are bits per second in RouterOS notation: `"10M"`, `"512k"`,
`"1G"`, plain `"2500000"`, and `"0"` for unlimited. They are validated
and normalized locally: `" 10m "` becomes `"10M"`. `"10M"` is 10 Mbit/s,
about 1.25 MByte/s.

```jennifer
# the guest network
mt.limitBandwidth($c, "guest-wifi", "192.168.90.0/24", "5M", "20M");

# one device: uploads capped at 50M, downloads unlimited
mt.limitBandwidth($c, "backup-nas", "192.168.88.50", "50M", "0");

# change a cap later, e.g. from a scheduled job on your own host
mt.setBandwidthLimit($c, "guest-wifi", "2M", "10M");

def qs as list of mt.SimpleQueue init mt.simpleQueues($c);
for (def q in $qs) {
    io.printf("%s on %s: %s up / %s down disabled=%t\n",
        $q.name, $q.target, $q.maxUpload, $q.maxDownload, $q.disabled);
}
```

## Queue trees: hierarchical QoS

A simple queue limits by address; a queue tree shares a line by kind of
traffic: voice first, backups last, each class with a guaranteed floor.
Classes match mangle packet marks ([mangle.md](mangle.md)). One root
holds the line's budget; one child per class sits under it.

```jennifer
# 1. classify: marks "voip" and "bulk"
def m as mt.FirewallRule init mt.firewallRule(mt.CHAIN_PREROUTING, mt.ACTION_ACCEPT);
$m = mt.withProtocol($m, "udp");
$m = mt.withDstPort($m, "5060-5200");
mt.setupPacketMark($c, "voip", $m);

# 2. the upload tree on a 40M uplink, budget set below the line rate
mt.addQueueTreeRoot($c, "qosup", "pppoewan", "38M");
mt.addQueueTreeChild($c, "qosupvoip", "qosup", "voip", "5M", "38M", 1);
mt.addQueueTreeChild($c, "qosupbulk", "qosup", "bulk", "10M", "38M", 8);
```

On an idle line every class may reach its `maxLimit`; on a full line
each keeps its `limitAt`, and priority (1 first, 8 last) decides the
rest. The root's parent must be an interface or `global`, a child's
parent must exist in the tree, and a packet mark that no mangle rule
sets is refused, since such a class would shape nothing.
`removeTreeQueue` removes a node with its whole subtree.

## Pitfalls

- The first matching simple queue wins. A network queue above a
  per-device queue takes the device's traffic; new queues are appended
  at the bottom.
- Queues only see traffic routed through the router. LAN-to-LAN traffic
  on one bridge is switched and never queued.
- Fasttrack bypasses queues. On the default RouterOS firewall, disable
  or narrow the `fasttrack-connection` rule ([firewall.md](firewall.md)).
- Shaping latency needs a cap slightly below the real line rate; at
  100% the bottleneck, and the queueing, moves back to the modem.
- A tree on an interface shapes its egress only: shape upload on the
  WAN interface and download on the LAN-facing one (two trees), or use
  `global`.
- Keep the children's `limitAt` sum within the root's budget, or the
  guarantees cannot all be met.
