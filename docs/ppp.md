# PPPoE: dial-in WAN

File: `src/topics/ppp.j`. Paths: `/interface/pppoe-client`
(`PPPOE_CLIENT_PATH`), `/interface/pppoe-server/server`
(`PPPOE_SERVER_PATH`), `/ppp/secret` (`PPP_SECRET_PATH`), `/ppp/profile`
(`PPP_PROFILE_PATH`), `/ppp/active` (`PPP_ACTIVE_PATH`).
Reference: [cheatsheet](cheatsheet.md#pppoe).

DSL and many fiber lines hand out no address by DHCP: the router dials in
over PPPoE with credentials from the ISP. The session is its own
interface, which carries the public address and the default route.
Masquerade and port forwards refer to that interface, not to the
physical port. The PPP user database (`addVpnUser` and friends) that
this file also holds is described in [vpn.md](vpn.md).

`setupPppoe` adopts the ISP's default route and DNS servers; change
either afterwards with `set` on `PPPOE_CLIENT_PATH`. It is idempotent by
name: an existing client is returned untouched. The password is written
but never read back, so `PppoeClient` has no password field.

## Examples

```jennifer
mt.setupPppoe($c, "pppoewan", "ether1", "user@provider.example", "secret");
mt.addMasquerade($c, "pppoewan", "lan to internet");   # the PPPoE name, not ether1

def dsl as mt.PppoeClient init mt.pppoeStatus($c, "pppoewan");
if (not $dsl.running) { io.printf("dial-in is down - check credentials and line\n"); }

mt.setPppoeCredentials($c, "pppoewan", "user@provider.example", "newsecret");

# reconnect
mt.disablePppoeClient($c, "pppoewan");
mt.enablePppoeClient($c, "pppoewan");
```

## PPPoE server

The router can also be the concentrator that downstream routers dial.
Sessions authenticate against the PPP user database, so add logins with
service `"pppoe"` or `"any"`. `addPppoeServer` is idempotent by service
name and interface, and sets `one-session-per-host`.

```jennifer
mt.addPppoeServer($c, "office", "ether2");
mt.addVpnUser($c, "branch", "a password", "pppoe", "downstream router");
```

## Pitfalls

- `running` false with correct credentials usually means the modem is
  not in bridge mode, or the ISP runs PPPoE on a VLAN (often VLAN 7).
  Then create the VLAN first, `mt.addVlan($c, "vlanisp", 7, "ether1")`,
  and dial over `"vlanisp"` ([vlans.md](vlans.md)).
- PPPoE lowers the MTU, typically to 1492. The RouterOS default firewall
  clamps the TCP MSS; on a hand-built one, call
  `mt.clampTcpMss($c, "pppoewan")` ([mangle.md](mangle.md)).
- `setPppoeCredentials` makes the session reconnect.

See also: [nat.md](nat.md), [dhcp.md](dhcp.md) (DHCP on the WAN).
