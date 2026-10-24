<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Interface lists

File: `src/topics/interfacelist.j`. Paths: `/interface/list`
(`INTERFACE_LIST_PATH`), `/interface/list/member`
(`INTERFACE_LIST_MEMBER_PATH`).

Reference: [cheatsheet](cheatsheet.md#interface-lists).

An interface list is a named group (`WAN`, `LAN`, `MGMT`) that rules match
as a whole, as in the RouterOS v7 default configuration. Adding an uplink
or moving a port changes the list, not the rules. The built-in lists
`all`, `none` and `dynamic` always exist.

`addInterfaceList` and `addToInterfaceList` are idempotent and return the
existing id on a repeat; `addToInterfaceList` creates a missing list and
requires the interface to exist. Firewall rules match lists with
`withInInterfaceList` / `withOutInterfaceList` ([firewall.md](firewall.md));
raw rules too ([raw.md](raw.md)).

```jennifer
mt.addToInterfaceList($c, "WAN", "ether1");
mt.addToInterfaceList($c, "LAN", "brlan");

def drop as mt.FirewallRule init mt.firewallRule(mt.CHAIN_INPUT, mt.ACTION_DROP);
$drop = mt.withInInterfaceList($drop, "WAN");
$drop = mt.withComment($drop, "drop unsolicited from WAN");
mt.addFirewallRule($c, $drop);

def lists as list of mt.InterfaceList init mt.interfaceLists($c);
for (def il in $lists) {
    def members as list of string init mt.interfaceListMembers($c, $il.name);
    io.printf("%s: %d members\n", $il.name, len($members));
}
```

## Pitfalls

- A list does nothing until a rule references it.
- Put a new uplink into `WAN` before it carries traffic, so the WAN rules
  apply from the first packet.
- The built-in `dynamic` list holds interfaces other features add (e.g. a
  running VPN); do not manage it by hand.
