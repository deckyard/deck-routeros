<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# UPnP

File: `src/topics/upnp.j`. Paths: `/ip/upnp` (`UPNP_PATH`),
`/ip/upnp/interfaces` (`UPNP_INTERFACES_PATH`).
Reference: [cheatsheet](cheatsheet.md#upnp).

UPnP-IGD lets LAN devices (game consoles, P2P apps, VoIP boxes) ask the
router for their own port forwards. Any device on an `internal`
interface can open a hole from the internet to itself, so use it only on
a trusted LAN. The service needs both roles set: the LAN interface
`internal`, the WAN interface `external`. One without the other does
nothing.

```jennifer
mt.enableUpnp($c);
mt.setUpnpInterface($c, "ether1", "external");   # the WAN
mt.setUpnpInterface($c, "brlan", "internal");    # the trusted LAN
```

`setUpnpInterface` is idempotent: calling it again for the same
interface changes the role.

The forwards UPnP opens appear as dynamic rules in `/ip/firewall/nat`;
`natRules(c)` lists them. On a network with devices you do not trust,
leave UPnP off, forward ports explicitly ([nat.md](nat.md)), and never
mark a guest interface `internal`.
