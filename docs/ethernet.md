# Ethernet ports

File: `src/topics/ethernet.j`. Path: `/interface/ethernet`
(`ETHERNET_PATH`).

Reference: [cheatsheet](cheatsheet.md#ethernet-ports).

The physical ports. `ethernetPorts` reads configuration; `linkStatus`
measures the link now (`monitor once`). Enable, disable, rename and
comment go through [interfaces.md](interfaces.md).

Speed and duplex are negotiated by default. Force them only for a link
partner that cannot negotiate, and force both ends to the same values:
forcing one side gives a duplex mismatch, a link that comes up and then
loses packets under load.

```jennifer
def ports as list of mt.EthernetPort init mt.ethernetPorts($c);
for (def p in $ports) {
    if ($p.running) {
        def ls as mt.LinkStatus init mt.linkStatus($c, $p.name);
        io.printf("%s: %s %s duplex=%t\n", $p.name, $ls.status, $ls.rate, $ls.fullDuplex);
    }
}

mt.forceEthernetLink($c, "ether4", "100Mbps", true);   # device set to 100/full too
mt.autoNegotiateEthernet($c, "ether4");                # back to the default

mt.setEthernetMtu($c, "ether3", 9000);   # every device on the path must agree
```

Forced speeds: `10Mbps`, `100Mbps`, `1Gbps`, `2.5Gbps`, `5Gbps`, `10Gbps`.
The MTU must be 68-65535; the port's l2mtu caps it and the router refuses
a larger value with a `mikrotik` error.

## PoE

`setPoe` takes `auto-on` (power a detected device, the default),
`forced-on` (power without detection, for devices that fail detection;
risky for anything else) or `off`. It refuses ports whose `poeOut` is `""`
(no PoE). Off, then auto-on, power-cycles a hung device:

```jennifer
mt.setPoe($c, "ether5", "off");
# wait a few seconds
mt.setPoe($c, "ether5", "auto-on");
```

## Pitfalls

- A duplex mismatch keeps the link up and ruins throughput. Check
  `linkStatus` on both ends.
- A port configured for auto-negotiation may still be down; check `up`.
- A `slave` port belongs to a bridge or bond: speed and duplex still
  apply, addresses and most protocols live on the master.
- `defaultName` keeps the factory name (`ether1`) after a rename.

See also: [bridges.md](bridges.md), [tools.md](tools.md) (bandwidth test).
