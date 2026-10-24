# IPsec: site-to-site tunnels

File: `src/topics/ipsec.j`. Paths: `/ip/ipsec/peer`, `.../identity`,
`.../policy`, `.../active-peers`, `.../mode-config` (`IPSEC_PEER_PATH`,
`IPSEC_IDENTITY_PATH`, `IPSEC_POLICY_PATH`, `IPSEC_ACTIVE_PATH`,
`IPSEC_MODE_CONFIG_PATH`). Reference: [cheatsheet](cheatsheet.md#ipsec).

Use IPsec (IKEv2) when the far end is another vendor: Cisco, pfSense, a
cloud VPN gateway, a partner's router. Between two MikroTiks,
[WireGuard](wireguard.md) is simpler. The IKEv2 remote-access server,
`setupIkev2Server`, is covered in [vpn.md](vpn.md).

RouterOS splits a tunnel across three objects: the **peer** (whom to
negotiate with), the **identity** (how to authenticate, here a
pre-shared key) and the **policy** (which traffic to encrypt, local
subnet to remote subnet, tunnel mode). Two more pieces decide whether
traffic flows:

1. **NAT bypass.** Masquerade rewrites the LAN source address before the
   policy can match, and traffic silently takes the plain internet path.
   A srcnat accept above masquerade prevents it.
2. **Firewall input.** IKE (udp 500), NAT-T (udp 4500) and ESP must be
   accepted from the peer.

`setupIpsecTunnel` creates all five; each end runs the mirror call.
`teardownIpsecTunnel` removes them.

## Example: two offices

Site A (LAN 192.168.10.0/24, public 198.51.100.1) and site B
(LAN 192.168.20.0/24, public 203.0.113.99):

```jennifer
# --- site A ---
mt.setupIpsecTunnel($c, "tobranch", "203.0.113.99",
    "a long random shared secret", "192.168.10.0/24", "192.168.20.0/24");

# --- site B (its own client): same key, subnets swapped ---
# mt.setupIpsecTunnel($cb, "tomain", "198.51.100.1",
#     "a long random shared secret", "192.168.20.0/24", "192.168.10.0/24");
```

Check it:

```jennifer
def live as list of mt.IpsecActivePeer init mt.ipsecActive($c);
for (def a in $live) {
    io.printf("%s: %s (%s, up %s)\n", $a.remoteAddress, $a.state, $a.side, $a.uptime);
}
def pols as list of mt.IpsecPolicy init mt.ipsecPolicies($c);
for (def pol in $pols) {
    io.printf("policy %s -> %s active=%t\n", $pol.srcAddress, $pol.dstAddress, $pol.active);
}
```

Traffic flows when the peer is `established` and the policy is `active`.
Test from a LAN host: the router's own `ping` leaves from its WAN
address, which the policy does not match.

## Pitfalls

- IPsec here is policy-based: there is no tunnel interface to route
  through. The policy captures matching traffic, so identical or
  overlapping subnets on both sides cannot work; renumber one side.
- The pre-shared key is the only authentication. Make it long and
  random and send it out of band. Certificate identities are possible
  through `/ip/ipsec/identity` with the generic verbs and the
  [certificates](certificates.md) topic.
- At least one side needs a reachable public address (or udp 500 and
  4500 forwarded to it). NAT-T handles the rest.
- The NAT bypass must stay above masquerade. Reordering NAT rules later
  breaks it; the symptom is "established, no traffic".
- Debug with `ipsecActive`: no entry means IKE is blocked (firewall or
  reachability); a state stuck negotiating means a key or proposal
  mismatch, which both ends' logs name.

See also: [nat.md](nat.md), [gre.md](gre.md) (GRE with coupled
`ipsec-secret` for routed multicast and OSPF).
