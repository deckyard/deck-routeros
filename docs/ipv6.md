<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# IPv6

File: `src/topics/ipv6.j`. Paths: `/ipv6/settings` (`IPV6_SETTINGS_PATH`),
`/ipv6/address` (`IPV6_ADDRESS_PATH`), `/ipv6/nd` (`IPV6_ND_PATH`).
Reference: [cheatsheet](cheatsheet.md#ipv6).

IPv6 on RouterOS is a separate stack. The `/ip/firewall` rules of
[firewall.md](firewall.md) do not filter it, and there is no NAT: every
host with a global v6 address is reachable from the internet. Either run
IPv6 with `/ipv6/firewall` rules (generic verbs), or switch it off with
`disableIpv6`. Half-configured is worse than both: hosts still
autoconfigure from any router advertisement on the wire and bypass rules
that only match v4.

A LAN prefix is a /64. SLAAC is defined only for /64, so a /72 LAN leaves
clients without addresses. The ISP delegates a /56 or /48; cut one /64
per LAN out of it.

## Examples

Address a LAN and let clients configure themselves:

```jennifer
mt.enableIpv6($c);
mt.setIpv6Forwarding($c, true);
mt.addIpv6Address($c, "2001:db8:1::1/64", "brlan");
mt.advertiseIpv6On($c, "brlan");
mt.setIpv6NdFlags($c, "brlan", false, true);   # SLAAC, DNS from DHCPv6
```

List what you configured; `dynamic` marks what RouterOS built itself
(link-local, SLAAC, a delegated prefix):

```jennifer
for (def a in mt.ipv6Addresses($c)) {
    if (not $a.dynamic) { io.printf("static %s on %s\n", $a.address, $a.interfaceName); }
}
```

## Pitfalls

- `enableIpv6` and `disableIpv6` take full effect after a reboot. The
  setting is stored at once; the running stack may not change until then.
- The prefix of an address is announced only with `advertise` true
  (`addIpv6Address` sets it; `addIpv6AddressWith` lets you choose).
  Without it, clients do not autoconfigure: right for a router-to-router
  link, wrong for a LAN.
- `removeIpv6Address` refuses dynamic addresses; remove what creates them
  (the DHCPv6 client, the received RA).
- `removeIpv6Address` matches the address as text. `2001:db8:1::1/64`
  does not match a row stored as `2001:0db8:1::1/64`; pass the address
  exactly as `ipv6Addresses` reports it, or remove by id with
  `mt.remove($c, mt.IPV6_ADDRESS_PATH, $id)`.
- An IPv4 CIDR passed to these calls is rejected with a message that
  says so.
- `stopAdvertisingIpv6On` does not take addresses away: clients keep
  theirs until the advertised lifetime runs out.

See also: [ip.md](ip.md) (IPv4), [dhcp.md](dhcp.md), [dns.md](dns.md),
[routing.md](routing.md).
