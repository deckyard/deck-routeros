# Firewall address lists

File: `src/topics/addresslist.j`. Path:
`/ip/firewall/address-list` (`ADDRESS_LIST_PATH`).
Reference: [cheatsheet](cheatsheet.md#firewall-address-lists).

An address list is a named set of addresses that a firewall rule
matches as a whole. Keep one rule ("drop everything on `blocklist`")
and maintain only the list; adding or removing members never touches
the firewall.

Entries are IPs, CIDR networks or DNS names (RouterOS resolves names
and follows their changes). An entry with a timeout removes itself.
Dynamic entries are created by firewall rules with
`add-src-to-address-list` (an action available through the generic
verbs). The rule-side matchers are the builder's
`withSrcAddressList(rule, listName)` and
`withDstAddressList(rule, listName)` ([firewall.md](firewall.md)).

## Examples

One rule, then list maintenance only:

```jennifer
mt.dropAddressList($c, "blocklist", mt.CHAIN_INPUT, "drop blocklisted");

mt.addToAddressList($c, "blocklist", "203.0.113.7", "ssh scanner");
mt.addToAddressList($c, "blocklist", "198.51.100.0/24", "botnet range");
mt.removeFromAddressList($c, "blocklist", "203.0.113.7");
```

A 24-hour block that expires by itself:

```jennifer
mt.addToAddressListTimed($c, "blocklist", "192.0.2.66", "1d", "brute force");
```

WinBox (TCP 8291) only from the admin network: accept the list, then
drop the port. Rules are appended, so add them in this order:

```jennifer
mt.addToAddressList($c, "admins", "10.0.9.0/24", "management net");

def ok as mt.FirewallRule init mt.firewallRule(mt.CHAIN_INPUT, mt.ACTION_ACCEPT);
$ok = mt.withProtocol($ok, "tcp");
$ok = mt.withDstPort($ok, "8291");
$ok = mt.withSrcAddressList($ok, "admins");
$ok = mt.withComment($ok, "winbox for admins");
mt.addFirewallRule($c, $ok);

def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_INPUT, mt.ACTION_DROP);
$r = mt.withProtocol($r, "tcp");
$r = mt.withDstPort($r, "8291");
$r = mt.withComment($r, "winbox only for admins");
mt.addFirewallRule($c, $r);
```

Audit:

```jennifer
def names as list of string init mt.addressLists($c);
for (def n in $names) {
    def entries as list of mt.AddressListEntry init mt.addressListEntries($c, $n);
    io.printf("list %s: %d entries\n", $n, len($entries));
}
```

## Pitfalls

- A list does nothing until a rule references it (`dropAddressList` or
  the `with*AddressList` matchers).
- An accept-from-list rule must sit above the drop it exempts from;
  see [firewall.md](firewall.md) for ordering and `moveRule`.
- `addToAddressList` is idempotent (RouterOS itself traps on a
  duplicate); `addToAddressListTimed` and `dropAddressList` are not.
- `clearAddressList` leaves dynamic entries alone and throws when the
  list has no static entries.
- DNS-name entries depend on the router's resolver
  ([dns.md](dns.md)) and change at the name's TTL; do not rely on
  them for hard security boundaries.
