# NAT: masquerade and port forwarding

File: `src/topics/nat.j`. Path: `/ip/firewall/nat` (`NAT_PATH`).
Reference: [cheatsheet](cheatsheet.md#nat).

- `CHAIN_SRCNAT` rewrites the source of outgoing traffic. With
  `ACTION_MASQUERADE` the LAN appears as the router's WAN address;
  a private LAN needs it to reach the internet.
- `CHAIN_DSTNAT` rewrites the destination of incoming traffic. With
  `ACTION_DST_NAT` it is a port forward to an inside service.

`addMasquerade` is idempotent: an existing masquerade rule for the same
out-interface is reused, so re-running a setup script never stacks
duplicates. The port-forward verbs are not idempotent. They accept only
`tcp` or `udp`, ports 1-65535 and an IP address as the target.

## Examples

Internet edge with a DHCP WAN ([dhcp.md](dhcp.md)):

```jennifer
mt.setupWan($c, "ether1");
mt.addMasquerade($c, "ether1", "lan to internet");
```

Publish an internal web server on port 8080:

```jennifer
mt.forwardPortOn($c, "ether1", "tcp", 8080, "192.168.88.10", 80, "web server");
```

Close the forward during maintenance without deleting it:

```jennifer
mt.disableNatRuleByComment($c, "web server");
mt.enableNatRuleByComment($c, "web server");
```

List the rules:

```jennifer
def nats as list of mt.NatRule init mt.natRules($c);
for (def n in $nats) {
    io.printf("%s/%s dst-port %s -> %s:%s %s\n",
        $n.chain, $n.action, $n.dstPort, $n.toAddresses, $n.toPorts, $n.comment);
}
```

## Pitfalls

- The firewall `forward` chain must accept the redirected traffic. The
  RouterOS default config does (established/related and dstnat'ed
  connections are accepted); a hardened one needs an accept rule
  ([firewall.md](firewall.md)).
- Use `forwardPortOn` with the WAN interface. `forwardPort` matches any
  incoming interface, so LAN clients connecting to the router on that
  port are redirected too.
- Reaching a forwarded service from inside the LAN through the public
  address needs hairpin NAT (an extra srcnat rule); add it with the
  generic `add` on `NAT_PATH`.
- Order matters in `dstnat`: a catch-all above a forward shadows it.
  Reorder with `moveNatRule` / `moveNatRuleByComment`.
- Masquerade drops long-lived connections when the WAN address changes.

See also: [ppp.md](ppp.md) (masquerade the PPPoE interface on DSL
uplinks), [upnp.md](upnp.md).
