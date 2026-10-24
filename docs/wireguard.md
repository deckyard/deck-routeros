# WireGuard VPN tunnels

File: `src/topics/wireguard.j`. Paths: `/interface/wireguard`
(`WIREGUARD_PATH`), `/interface/wireguard/peers` (`WIREGUARD_PEER_PATH`).
Reference: [cheatsheet](cheatsheet.md#wireguard-vpn-tunnels).

Needs RouterOS v7. `wireguardInterfaces` and `wireguardPeers` return an
empty list on any read error: on v6, but also on a dropped connection or
a permission error, so an empty list does not prove there are no tunnels.

The local end is a WireGuard **interface** (keypair, UDP listen port);
each remote party is a **peer** on it.

- The router generates the private key; this deck neither sets nor
  reads it. You handle public keys only: 44 base64 characters ending in
  `=`, checked locally.
- **allowed-address** is a filter and a route: traffic from a peer is
  accepted only for these networks, and traffic to them goes into the
  tunnel. Every entry needs a prefix; a single device is `/32`, and a
  bare IP is rejected with that hint.
- A live tunnel handshakes about every 2 minutes; `lastHandshake` is the
  liveness signal.

## Road-warrior server

```jennifer
# interface, VPN address, firewall opening (idempotent)
mt.setupWireguardServer($c, "wgvpn", 13231, "10.100.0.1/24");

# the router's public key, for the laptop's WireGuard config
io.printf("server public key: %s\n", mt.wireguardPublicKey($c, "wgvpn"));

# the laptop's public key comes from its WireGuard app
mt.addWireguardPeer($c, "wgvpn",
    "hIe5R2FTPjvrIrVXfy41chvUJ4CyOTdBEI3pQGea0R0=",
    "10.100.0.2/32", "laptop");
```

The laptop's config: endpoint = the router's public IP or DNS name, port
13231, address 10.100.0.2/32, allowed IPs at least 10.100.0.0/24. To
reach the LAN as well, add 192.168.88.0/24 to the allowed IPs on the
laptop and permit VPN to LAN in the forward chain.

## Site-to-site, this router dials out

```jennifer
mt.addWireguard($c, "wghome", 13231);
io.printf("our key (for the far end): %s\n", mt.wireguardPublicKey($c, "wghome"));
mt.connectWireguard($c, "wghome",
    "<the far end's public key>", "vpn.example.org", 13231,
    "10.100.0.0/24,192.168.10.0/24",     # what lives behind the far end
    "to headquarters");
mt.addIpAddress($c, "10.100.0.3/24", "wghome");
```

## Monitoring

```jennifer
def peers as list of mt.WireguardPeer init mt.wireguardPeers($c);
for (def p in $peers) {
    io.printf("peer %s: handshake %s, rx %s tx %s\n",
        $p.comment, $p.lastHandshake, $p.rx, $p.tx);
}
```

An empty `lastHandshake`, or one older than 2-3 minutes, means the
tunnel is down: wrong key, wrong endpoint, or UDP blocked. WireGuard
reports a wrong key nowhere else.

## Pitfalls

- Overlapping allowed-addresses between peers on one interface do not
  work; the last one wins.
- The input chain must accept UDP on the listen port.
  `setupWireguardServer` adds that rule (comment `"wireguard: <name>"`);
  `addWireguard` alone does not.
- Behind NAT only the dialing side needs keepalive; `connectWireguard`
  sets 25 seconds.
- Traffic between VPN and LAN passes the `forward` chain; permit it if
  peers should reach LAN devices ([firewall.md](firewall.md)).
- `removeWireguard` removes only the first IP address on the interface.
