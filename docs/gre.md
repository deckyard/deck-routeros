# GRE tunnels

File: `src/topics/gre.j`. Path: `/interface/gre` (`GRE_PATH`).
Reference: [cheatsheet](cheatsheet.md#gre-tunnels).

GRE (RFC 2784) is a routed, layer-3 point-to-point link over IP. Unlike
EoIP, which bridges one LAN across sites, GRE joins two networks that
keep their own subnets and DHCP; traffic between them is routed. The far
end can be any vendor that speaks GRE.

Each end takes three steps:

1. create the tunnel, with the other router as the remote;
2. address the tunnel ends in a small shared network (a `/30` holds two
   hosts);
3. route the far site's networks at the far tunnel address.

`addGreTunnel` and `addSecureGreTunnel` require the remote to be an IP
address and the name to be free, and refuse a second tunnel to the same
remote, naming the tunnel that already has it. The IPsec secret is
write-only.

## Example: routed site-to-site

Site A (LAN 192.168.10.0/24, public 198.51.100.1) to site B
(LAN 192.168.20.0/24, public 203.0.113.99):

```jennifer
# --- site A ---
mt.addGreTunnel($c, "grebranch", "203.0.113.99");
mt.addIpAddress($c, "10.99.0.1/30", "grebranch");
mt.addRoute($c, "192.168.20.0/24", "10.99.0.2", "branch LAN via GRE");

# --- site B (its own client) ---
# mt.addGreTunnel($cb, "gremain", "198.51.100.1");
# mt.addIpAddress($cb, "10.99.0.2/30", "gremain");
# mt.addRoute($cb, "192.168.10.0/24", "10.99.0.1", "main LAN via GRE");

if (mt.isReachable($c, "10.99.0.2")) {
    io.printf("tunnel is routing\n");
}
```

With coupled IPsec across an untrusted path:

```jennifer
mt.addSecureGreTunnel($c, "grebranch", "203.0.113.99", "a long random shared secret");
```

## Pitfalls

- GRE is unencrypted. On the open internet use the IPsec-coupled
  variant, or [WireGuard](wireguard.md). GRE's advantages are
  multi-vendor interop and multicast (OSPF adjacencies work across it).
- Keep the route to the remote's public address on the physical uplink.
  Routed through the tunnel itself, the tunnel flaps.
- The tunnel MTU is smaller (1476 typical, less with IPsec). If ping
  works but large transfers hang, lower the MTU or clamp TCP MSS.
- The `forward` chain sees tunneled traffic like any other: on a
  hardened router permit LAN-to-LAN explicitly ([firewall.md](firewall.md)).
- Keepalive (default `10s,10`) is what makes a dead path show
  `running == false`; without it the tunnel always reports up.

See also: [eoip.md](eoip.md), [routing.md](routing.md).
