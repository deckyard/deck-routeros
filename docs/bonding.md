# Bonding (link aggregation)

File: `src/topics/bonding.j`. Path: `/interface/bonding`
(`BONDING_PATH`).

Reference: [cheatsheet](cheatsheet.md#bonding-link-aggregation).

A bond joins several links into one interface, which then takes bridge
ports, addresses and VLANs like any other.

- `addLacpBond`: 802.3ad (`BOND_LACP`) with a switch that has a matching
  LACP group. Adds capacity across many flows; one flow still uses one
  link, so a single transfer over 2x1G peaks at 1G.
- `addFailoverBond`: active-backup (`BOND_ACTIVE_BACKUP`). One link
  carries traffic, the `primary` is preferred. Needs no switch support,
  so it works across two independent switches.
- `addBond`: any of `balance-rr`, `active-backup`, `balance-xor`,
  `broadcast`, `802.3ad`, `balance-tlb`, `balance-alb`.

Slave lists are checked before anything is written: at least two
distinct, space-free names; each interface must exist and belong to no
other bond (for `setBondSlaves`, the bond's own members do not count). A
failover `primary` must be one of the slaves.

```jennifer
mt.addLacpBond($c, "bondtrunk", "ether1,ether2");
mt.addBridgePort($c, "brlan", "bondtrunk");

mt.addFailoverBond($c, "bonduplink", "ether3,ether4", "ether3");
mt.addIpAddress($c, "10.0.0.2/24", "bonduplink");

mt.setBondSlaves($c, "bondtrunk", "ether1,ether2,ether5");

def b as mt.Bond init mt.bondByName($c, "bondtrunk");
io.printf("%s (%s) over %s running=%t\n", $b.name, $b.mode, $b.slaves, $b.running);
```

## Pitfalls

- An 802.3ad bond against a switch without a matching LAG stays down.
- Spread flows with `transmit-hash-policy` (generic `set`, e.g.
  `"layer-3-and-4"`).
- Members must be plain ports: no bridge membership, no addresses. The
  deck checks existence and other bonds only.
- `running` is true while at least one member is up, so a degraded bundle
  still shows running. Check members with `linkStatus`.
- Removing a bond leaves bridge ports and addresses that used it without
  an interface; remove those first.
