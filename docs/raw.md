<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Firewall raw (pre-conntrack)

File: `src/topics/raw.j`. Path: `/ip/firewall/raw` (`RAW_PATH`).
Reference: [cheatsheet](cheatsheet.md#firewall-raw-pre-conntrack).

The raw table runs before connection tracking, earlier and cheaper than
the filter table. Use it to drop garbage (spoofed sources, bogons, the
bulk of a flood) without spending conntrack entries or CPU, and to
`notrack` traffic that must stay out of the connection table.

Raw rules are built with the firewall builder
([firewall.md](firewall.md)): `firewallRule(chain, action)` plus the
`with*` refiners. Raw has the chains `CHAIN_PREROUTING` (incoming, the
usual one) and `CHAIN_OUTPUT`, and the actions `accept`, `drop` and
`ACTION_NOTRACK`. routeros does not enforce these limits; the router
refuses anything else with kind `"mikrotik"`.

## Examples

Drop bogons arriving on the WAN (the list from
[addresslist.md](addresslist.md), `WAN` from
[interfacelist.md](interfacelist.md)):

```jennifer
def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_PREROUTING, mt.ACTION_DROP);
$r = mt.withInInterfaceList($r, "WAN");
$r = mt.withSrcAddressList($r, "bogons");
$r = mt.withComment($r, "drop bogons from WAN");
mt.addRawRule($c, $r);
```

The same without the interface match:

```jennifer
mt.dropRawAddressList($c, "bogons", "drop bogons early");
```

Keep multicast out of the connection table:

```jennifer
def n as mt.FirewallRule init mt.firewallRule(mt.CHAIN_PREROUTING, mt.ACTION_NOTRACK);
$n = mt.withDstAddress($n, "224.0.0.0/4");
$n = mt.withComment($n, "do not track multicast");
mt.addRawRule($c, $n);
```

## Pitfalls

- Raw sees packets before tracking, so `connection-state` cannot be
  matched. Match addresses, ports, interfaces and address lists.
- Rules are appended. A broad drop above a needed accept blocks it: add
  the accept first, or fix the order with `moveRawRule(c, id,
  beforeId)` / `moveRawRuleByComment(c, comment, beforeComment)` (`""`
  moves to the bottom).
- `notrack` traffic gets no NAT and no stateful filtering.
- Raw drops never reach the connection table ([contrack.md](contrack.md));
  debug them from the rule counters.
