# Static routes

File: `src/topics/routing.j`. Paths: `/ip/route` (`ROUTE_PATH`),
`/routing/rule` (`ROUTING_RULE_PATH`), `/routing/table`
(`ROUTING_TABLE_PATH`). Reference: [cheatsheet](cheatsheet.md#static-routes).

Routes are matched most-specific first; the default route
(`DEFAULT_ROUTE`, `"0.0.0.0/0"`) matches everything else. *Connected*
routes come from interface addresses, *dynamic* ones from protocols,
DHCP and PPPoE; this topic manages *static* routes. Static routes live
under `/ip/route`; RouterOS's `/routing` menu holds OSPF, BGP and the
policy rules. Between routes to the same destination the lower
*distance* wins (static default 1).

The gateway may be an IP address or an interface name. A gateway that
is not an IP address must name an interface on the router, so a typo in
either form fails with kind `"routeros"`.

## Examples

A branch office behind another router on the LAN:

```jennifer
mt.addRoute($c, "10.20.0.0/16", "192.168.88.254", "to branch office");
```

Primary and backup uplink. The distance-1 route wins while its gateway
is reachable; the distance-10 route takes over when it is not:

```jennifer
mt.addDefaultRoute($c, "203.0.113.1", "primary isp");
mt.addRouteWithDistance($c, "0.0.0.0/0", "198.51.100.1", 10, "backup isp");
```

The table without dynamic routes:

```jennifer
def rts as list of mt.Route init mt.routes($c);
for (def rt in $rts) {
    if (not $rt.dynamic) {
        io.printf("%s via %s distance %s active=%t\n",
            $rt.dstAddress, $rt.gateway, $rt.distance, $rt.active);
    }
}
```

## Policy routing rules

RouterOS v7 only; v6 keeps rules under `/ip/route/rule`, reachable with
the generic verbs. Distance failover switches the uplink for everyone; a
policy rule picks a routing table per source. It is checked before the
main table and needs no packet marking, so prefer it to `markRoutingFor`
([mangle.md](mangle.md)) when a source match is enough. Marks remain the
tool for matches on ports, protocols or address lists.

```jennifer
# guests use the backup ISP, everything else stays on main
mt.useRoutingTable($c, "10.30.0.0/24", "backupisp", "guests via backup");
# the table is created if missing, but it still needs a default route
mt.add($c, mt.ROUTE_PATH, {"dst-address": "0.0.0.0/0",
    "gateway": "198.51.100.1", "routing-table": "backupisp"});
```

`useRoutingTable` (action `lookup`) falls back to the main table for
destinations the table has no route for. `useRoutingTableOnly` (action
`lookup-only-in-table`) does not: those destinations become unreachable
for the source. Both are idempotent by source and table.

## Pitfalls

- The gateway must be directly reachable (inside a connected network).
  Otherwise the route shows `active == false` and carries nothing.
- `removeRoute`, `enableRoute` and `disableRoute` match the destination
  string exactly as the router lists it, skip dynamic routes, and act on
  the first static match. For the second route of a failover pair, pass
  its id from `routes(c)` to the generic verbs.
- A WAN set up through [dhcp.md](dhcp.md) or [ppp.md](ppp.md) installs
  its own dynamic default route. Either let it, or pass
  `addDefaultRoute = false` to `setupWanWith` and add the route here.
- Distance failover reacts to the gateway becoming unreachable (ARP),
  not to a broken upstream. RouterOS's `check-gateway` and recursive
  routes are reachable through the generic verbs.
- With two uplinks, replies to connections that arrived on the backup
  line must leave through it too: add a rule per uplink source, or use
  connection marks ([mangle.md](mangle.md)).
- WireGuard allowed-address entries create routes as well
  ([wireguard.md](wireguard.md)).
