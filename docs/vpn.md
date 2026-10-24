<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Remote-access VPN (L2TP, SSTP, OpenVPN, IKEv2)

Files: `src/topics/ppp.j` (the shared user database), `l2tp.j`,
`sstp.j`, `ovpn.j`, and `setupIkev2Server` in `ipsec.j`. Reference:
[L2TP](cheatsheet.md#l2tp), [SSTP](cheatsheet.md#sstp),
[OpenVPN](cheatsheet.md#openvpn), [PPPoE and VPN users](cheatsheet.md#pppoe),
[IPsec](cheatsheet.md#ipsec).

Site-to-site VPNs ([wireguard](wireguard.md), [ipsec](ipsec.md),
[gre](gre.md), [eoip](eoip.md)) join networks; these let people dial
in. The choice depends mostly on the client:

| Server | Client side | Needs |
|---|---|---|
| L2TP/IPsec | built into Windows, macOS, iOS, Android | a pre-shared key |
| SSTP | TLS on 443, passes hotel and captive firewalls | a TLS certificate |
| OpenVPN | a client for every OS, plus a config file per device | a TLS certificate |
| IKEv2 | native in iOS, macOS, Windows | a certificate and RADIUS users |

For "staff reach the office", L2TP/IPsec has the least friction.

## Users: PPP secrets

L2TP, SSTP and OpenVPN (and PPTP) authenticate against `/ppp/secret`.
Enable a server, then add users; a user works on every server its
`service` allows: `"any"`, `"l2tp"`, `"sstp"`, `"ovpn"`, `"pptp"` or
`"pppoe"`.

```jennifer
mt.addVpnUser($c, "alice", "her password", "any", "field laptop");
mt.vpnUsers($c);              # list them
mt.pppActive($c);             # sessions now, any VPN type
mt.kickPppUser($c, "alice");  # drop a session
```

## L2TP/IPsec

```jennifer
mt.enableL2tpServer($c, "a long random ipsec secret");   # also opens the firewall
mt.addVpnUser($c, "alice", "her password", "l2tp", "laptop");
```

Clients enter the router's public address or DNS name (see
[cloud.md](cloud.md) for a name on a dynamic IP), the pre-shared key,
and their username and password. `enableL2tpServer` requires IPsec and
refuses an empty secret; plain L2TP is cleartext.
`disableL2tpServer($c)` turns the server off and removes its firewall
accepts.

## SSTP and OpenVPN

Both need a certificate ([certificates.md](certificates.md)); with a
public Let's Encrypt certificate clients connect without warnings.

```jennifer
mt.enableSstpServer($c, "router-le-cert", 443);   # looks like HTTPS
mt.enableOvpnServer($c, "router-le-cert", 1194);
mt.addVpnUser($c, "bob", "his password", "any", "remote worker");
```

SSTP works where other VPNs are blocked, since to a firewall it is
HTTPS. OpenVPN runs routed (`mode=ip`) over TCP and each device needs a
config profile, exported from the router or written by hand.

## Dialing out

The router can be the client of someone else's server. Each client is
an interface to route or bridge:

```jennifer
mt.addL2tpClient($c, "l2tpto-hq", "vpn.example.org", "branch", "password");
mt.addSstpClient($c, "sstpto-hq", "vpn.example.org", "branch", "password");
mt.addOvpnClient($c, "ovpnto-hq", "vpn.example.org", "branch", "password");
```

`addSstpClient` sets `verify-server-certificate=no`, so it does not
authenticate the server; set it to `yes` with the generic `set` when the
server's certificate chain is trusted on the router.

## IKEv2 road-warrior

`setupIkev2Server` creates an address pool and mode-config (client
addresses and DNS), a passive IKEv2 peer, and an `eap-radius` identity
bound to the router's certificate:

```jennifer
mt.setupIkev2Server($c, "roadwarriors", "router-le-cert",
    "10.200.0.10-10.200.0.200", "1.1.1.1");
```

Users come from RADIUS ([radius.md](radius.md); User Manager is one).
The client must trust the certificate chain. Test with a real device;
between networks you control, WireGuard is simpler.

## Pitfalls

- One user database: disabling or deleting a user (`disableVpnUser`)
  affects every server it could use.
- The `enable*Server` helpers add input accepts and the `disable*Server`
  helpers remove them. On a firewall that drops input early, those
  accepts must sit above the drop.
- L2TP behind NAT relies on NAT-T (udp 4500), which `enableL2tpServer`
  opens.
- The default PPP profile hands out an address but no routes or DNS.
  Push those through the profile: `pppProfiles(c)`, then the generic
  `set` on `PPP_PROFILE_PATH`.
- TLS VPNs fail when the router clock is wrong ([clock.md](clock.md)).
