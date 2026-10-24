<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# RADIUS

File: `src/topics/radius.j`. Path: `/radius` (`RADIUS_PATH`).
Reference: [cheatsheet](cheatsheet.md#radius).

A RADIUS server (FreeRADIUS, Windows NPS, an appliance) holds the
credentials that would otherwise live in local `/user` accounts, PPP
secrets or hotspot users on each router. A server entry is bound to the
subsystems that use it: `login`, `ppp`, `hotspot`, `wireless`, `dhcp`,
`ipsec`, `dot1x`. `addRadiusServer` validates the list, requires an IP
address (not a DNS name) and a non-empty secret, and is idempotent by
address: an existing entry is returned unchanged.

## Examples

Admin logins and VPN users from Active Directory (NPS):

```jennifer
mt.addRadiusServer($c, "10.0.9.20", "a shared secret", "login,ppp", "AD/NPS");

def servers as list of mt.RadiusServer init mt.radiusServers($c);
for (def s in $servers) { io.printf("radius %s for %s\n", $s.address, $s.services); }
```

## Pitfalls

- Binding a server does not switch a subsystem to RADIUS. Set
  `/user/aaa use-radius=yes`, `/ppp/aaa use-radius=yes` or the hotspot
  profile's `use-radius` with the generic verbs.
- Keep a local admin. If RADIUS becomes unreachable and local
  authentication is off, you are locked out. Leave a local `full` user
  and put RADIUS in front of it, not in its place.
- The RADIUS protocol hides the shared secret only weakly. Keep the
  server on a trusted segment, or use RadSec.
- IKEv2 with EAP ([vpn.md](vpn.md)) is a common reason to add `ppp` or
  `ipsec` RADIUS.

See also: [users.md](users.md), [hotspot.md](hotspot.md),
[services.md](services.md).
