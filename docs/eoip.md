# EoIP tunnels

File: `src/topics/eoip.j`. Path: `/interface/eoip` (`EOIP_PATH`).
Reference: [cheatsheet](cheatsheet.md#eoip-tunnels).

EoIP carries ethernet frames inside IP packets between two MikroTik
routers. Bridge the tunnel into the LAN on both ends and the sites share
one layer-2 network: one broadcast domain, one subnet. A routed VPN such
as WireGuard alone does not do that.

- **Both ends** create a tunnel with the other as `remote-address` and
  the **same tunnel id** (0-65535). Mismatched ids fail silently: the
  tunnels never come up.
- **EoIP is not encrypted.** Across the internet, set the coupled IPsec
  secret (`addSecureEoipTunnel`) or run EoIP over WireGuard with the
  peer's VPN address as remote.
- **Everything crosses**: broadcasts, DHCP, mDNS. Run one DHCP server
  for both sites, or separate them deliberately.
- EoIP is MikroTik-proprietary; the far end must be a MikroTik.

`addEoipTunnel` refuses a taken name and a tunnel with the same remote
and id, naming the tunnel that holds it.

## One LAN across two sites, over WireGuard

WireGuard provides the encrypted path, EoIP the layer 2 on top:

```jennifer
# a WireGuard tunnel connects the sites: A = 10.100.0.1, B = 10.100.0.2

# site A
mt.addEoipTunnel($c, "eoipbranch", "10.100.0.2", 7);
mt.addBridgePort($c, "brlan", "eoipbranch");

# site B, on its own client
# mt.addEoipTunnel($cb, "eoipmain", "10.100.0.1", 7);
# mt.addBridgePort($cb, "brlan", "eoipmain");
```

A device at site B then gets its lease from site A's DHCP server.

## Direct, with coupled IPsec

```jennifer
mt.addSecureEoipTunnel($c, "eoipbranch", "203.0.113.99", 7,
    "a long random shared secret");
# the far end mirrors it with the same secret and id
```

## Monitoring

```jennifer
def tunnels as list of mt.EoipTunnel init mt.eoipTunnels($c);
for (def t in $tunnels) {
    io.printf("eoip %s -> %s (id %d) running=%t\n",
        $t.name, $t.remoteAddress, $t.tunnelId, $t.running);
}
```

Keepalive defaults to `10s,10`, so `running` goes false when the far end
stops answering. False on both ends usually means the path is down or the
ids differ; on one end only, check that the remote addresses mirror each
other.

## Pitfalls

- Encapsulation (more with IPsec) shrinks the usable MTU, so full
  1500-byte frames may not fit. The symptom is "ping works, downloads
  hang": lower the tunnel MTU with the generic `set`, or enable
  `clamp-tcp-mss`.
- Two parallel tunnels between the same sites, bridged on both ends,
  form a loop. Use one tunnel per site pair, or run (R)STP on the
  bridges.
- The stretched LAN also carries broadcast storms and rogue DHCP
  servers. For routed site-to-site links, plain WireGuard
  ([wireguard.md](wireguard.md)) is simpler.
