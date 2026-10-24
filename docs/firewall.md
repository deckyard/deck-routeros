# Firewall (filter rules)

File: `src/topics/firewall.j`. Path: `/ip/firewall/filter`
(`FIREWALL_PATH`).

Reference: [cheatsheet](cheatsheet.md#firewall-filter-rules).

## Background

Every filter rule sits in a chain:

- `CHAIN_INPUT` (`"input"`): traffic to the router itself (its SSH, DNS,
  WinBox).
- `CHAIN_FORWARD` (`"forward"`): traffic through the router.
- `CHAIN_OUTPUT` (`"output"`): traffic the router originates.

Rules are evaluated top to bottom and the first match wins. Actions:
`ACTION_ACCEPT`, `ACTION_DROP` (silent), `ACTION_REJECT` (answers the
sender), plus log, jump, return, passthrough, tarpit,
fasttrack-connection and notrack.

## The rule builder

Start with chain and action, refine with `with*` helpers (each returns a
new copy), then create the rule. Fields left unset are omitted, so a bare
rule matches everything in its chain.

```jennifer
def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_FORWARD, mt.ACTION_DROP);
$r = mt.withProtocol($r, "tcp");
$r = mt.withSrcAddress($r, "10.0.0.0/8");
$r = mt.withDstPort($r, "445");
$r = mt.withComment($r, "no smb forwarding");
def id as string init mt.addFirewallRule($c, $r);
```

Port specs are a single port ("80"), a list ("80,443") or a range
("8000-8100"). `withSrcAddressList` / `withDstAddressList` match a named
set ([addresslist.md](addresslist.md)); `withInInterfaceList` /
`withOutInterfaceList` match an [interface list](interfacelist.md).

Checked before anything is sent: unknown actions and protocols (the
error lists the allowed values), empty or spaced names and addresses,
port specs with characters other than digits, `,` and `-`, and a port
match without a protocol (RouterOS's own error for that is less
helpful). Address syntax itself is left to the router.

## Comments as handles

RouterOS ids change when a rule is re-added; comments do not. Give every
rule a distinct comment and manage it by that:

```jennifer
mt.disableFirewallRuleByComment($c, "no smb forwarding");
mt.enableFirewallRuleByComment($c, "no smb forwarding");
mt.removeFirewallRuleByComment($c, "no smb forwarding");
```

## Ordering

`addFirewallRule`, `allowService` and `blockAddress` append, so a rule
added after a broad drop never fires. Move it instead of deleting and
re-adding:

```jennifer
def wg as string init mt.allowService($c, "udp", 13231, "wireguard in");
mt.moveFirewallRule($c, $wg, $dropNonLanId);
mt.moveFirewallRuleByComment($c, "wireguard in", "drop everything else");
```

`""` as the destination sends a rule to the bottom. The generic verbs in
[core.md](core.md) reach the ends of any ordered list:

```jennifer
mt.moveFirewallRuleByComment($c, "log leftovers", "");
mt.moveRuleToTop($c, mt.FIREWALL_PATH, $establishedId);
```

NAT, mangle and raw have the same pair: `moveNatRule` /
`moveNatRuleByComment`, `moveMangleRule` / `moveMangleRuleByComment`,
`moveRawRule` / `moveRawRuleByComment`.

## Shortcuts

```jennifer
mt.allowService($c, "tcp", 22, "ssh management");      # input accept
mt.blockAddress($c, "203.0.113.7", "known scanner");    # input drop
```

## Reading back

```jennifer
def rules as list of mt.FirewallRule init mt.firewallRules($c);
for (def fr in $rules) {
    io.printf("%s %s %s -> %s %s\n",
        $fr.chain, $fr.action, $fr.srcAddress, $fr.dstAddress, $fr.comment);
}
```

## Pitfalls

- A drop rule on `input` that matches your management connection
  disconnects you. Add accept rules such as `allowService` before broad
  drops.
- icmp has no ports; a port match needs tcp or udp.
- `drop` leaves the sender waiting for a timeout; `reject` answers it.
  On internet-facing rules `drop` reveals less.
- Custom chains work (`firewallRule("mychain", ...)`), but
  `FirewallRule` has no jump-target field: set `jump-target` on the
  jump rule with the generic `set`.
- A port forward ([nat.md](nat.md)) also needs the forward chain to let
  the redirected traffic through. Close UDP/TCP 53 on the WAN when the
  router resolves DNS for its clients ([dns.md](dns.md)).
