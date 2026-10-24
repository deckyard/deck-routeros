# Hotspot: the guest portal

File: `src/topics/hotspot.j`. Paths: `/ip/hotspot` (`HOTSPOT_PATH`),
`/ip/hotspot/profile` (`HOTSPOT_PROFILE_PATH`), `/ip/hotspot/user`
(`HOTSPOT_USER_PATH`), `/ip/hotspot/active` (`HOTSPOT_ACTIVE_PATH`),
`/ip/hotspot/ip-binding` (`HOTSPOT_BINDING_PATH`),
`/ip/hotspot/walled-garden` (`WALLED_GARDEN_PATH`).
Reference: [cheatsheet](cheatsheet.md#hotspot).

A hotspot turns an interface into a captive portal: guests get an
address, and every web request lands on a login page until they log in.
`setupHotspot` builds what the console wizard builds: the DHCP stack
(`setupDhcp`, with the gateway as the guests' DNS server), a server
profile and the hotspot server on the interface. It returns the
existing server's id when a hotspot of that name exists.

Around it: users and vouchers (logins, optionally with a connect-time
limit), active sessions, IP bindings (devices that bypass the portal)
and the walled garden (destinations reachable before login).

## Examples

A guest network on a dedicated bridge with a day-pass voucher:

```jennifer
mt.addBridge($c, "brguest");
mt.addBridgePort($c, "brguest", "wifiguest");
mt.addIpAddress($c, "10.5.50.1/24", "brguest");

mt.setupHotspot($c, "guests", "brguest", "10.5.50.0/24",
    "10.5.50.1", "10.5.50.10", "10.5.50.254");

mt.addHotspotVoucher($c, "visitor", "day pass 123", "1d", "front desk");
mt.allowBeforeLogin($c, "*.example.org", "our own site");
mt.bypassHotspotMac($c, "AA:BB:CC:DD:EE:FF", "lobby TV");
```

Who is on, and ending a session:

```jennifer
def sessions as list of mt.HotspotSession init mt.hotspotActive($c);
for (def s in $sessions) {
    io.printf("%s from %s (%s): up %s, %d MB down\n",
        $s.user, $s.address, $s.mac, $s.uptime, $s.bytesOut // 1048576);
}
mt.kickHotspotUser($c, "visitor");
```

## Pitfalls

- Never put the portal on the management LAN. It intercepts all traffic
  on its interface, your own session included. Use a dedicated bridge.
- HTTPS requests cannot be redirected to the portal. Modern devices find
  it through their captive-portal probe; an old device that opens only
  HTTPS sites sees timeouts.
- Vouchers limit connect time, not calendar time: a `1d` voucher used one
  hour a day lasts 24 days. Calendar expiry needs a scheduled cleanup or
  RADIUS.
- `addHotspotUser` and `addHotspotVoucher` fail when the login exists.
  The voucher limit uses the scheduler's interval syntax (`"4h"`, `"1d"`,
  `"1d12h"`, `"HH:MM:SS"`).
- `teardownHotspot` removes the server, the profile and the DHCP stack.
  Users, bindings and walled-garden entries stay.
- The login page is HTML on the router's storage (`html-directory` in the
  profile); upload custom pages as in [files.md](files.md).
- Guests share one network. Isolate them from the LAN with forward rules
  ([firewall.md](firewall.md)) and cap their bandwidth
  ([queues.md](queues.md)); [wireless.md](wireless.md) has the full
  guest recipe.
