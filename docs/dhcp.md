# DHCP: server, leases, and the WAN client

File: `src/topics/dhcp.j`. Paths: `/ip/pool` (`IP_POOL_PATH`),
`/ip/dhcp-server` (`DHCP_SERVER_PATH`), `/ip/dhcp-server/network`
(`DHCP_NETWORK_PATH`), `/ip/dhcp-server/lease` (`DHCP_LEASE_PATH`),
`/ip/dhcp-client` (`DHCP_CLIENT_PATH`), `/ip/dhcp-relay`
(`DHCP_RELAY_PATH`). Reference: [cheatsheet](cheatsheet.md#dhcp).

A DHCP server in RouterOS is three objects: an address pool (the range),
the server (bound to an interface) and a network entry (the gateway and
DNS servers clients are told). `setupDhcp` creates all three. The DHCP
client is the WAN side: it asks the ISP for the router's own address.

## Server

The interface needs an address inside the served network first, or
clients get a gateway they cannot reach:

```jennifer
mt.addIpAddress($c, "192.168.77.1/24", "brlan");

mt.setupDhcp($c, "dhcplan", "brlan",
    "192.168.77.0/24",       # network
    "192.168.77.1",          # gateway told to clients
    "192.168.77.10",         # range start
    "192.168.77.199",        # range end
    "192.168.77.1");         # DNS told to clients, comma-separated

mt.teardownDhcp($c, "dhcplan", "192.168.77.0/24");
```

`setupDhcp` checks everything before it creates anything: gateway and both
range ends must lie inside the network, DNS entries must be IP addresses,
the interface must exist. It is not idempotent: it adds three objects on
every call. The pool takes the server's name. `teardownDhcp` removes
whichever of the three pieces exist (the network entry is matched by the
exact CIDR string) and fails only when none does.

## Leases and reservations

```jennifer
def leases as list of mt.DhcpLease init mt.dhcpLeases($c);
for (def l in $leases) {
    io.printf("%s -> %s (%s) %s\n", $l.address, $l.mac, $l.hostName, $l.status);
}

mt.addStaticLease($c, "192.168.77.50", "aa:bb:cc:dd:ee:ff", "printer");
mt.removeLeaseByMac($c, "AA:BB:CC:DD:EE:FF");
```

MACs must be six colon-separated hex pairs, any case; they are sent
uppercased. `DhcpLease.dynamic` is false for a static reservation.

## WAN client

```jennifer
mt.setupWan($c, "ether1");                  # adopts the ISP's route and DNS
mt.addMasquerade($c, "ether1", "lan to internet");

def wan as mt.DhcpClient init mt.wanStatus($c, "ether1");
if ($wan.bound) {
    io.printf("online as %s via %s, lease renews in %s\n",
        $wan.address, $wan.gateway, $wan.expiresAfter);
}
```

`setupWan` and `setupWanWith` are idempotent: an existing client on the
interface is returned untouched, with its old settings. `setupWanWith`
can decline the ISP's DNS servers or default route, e.g. for a backup
uplink routed with `addRouteWithDistance` ([routing.md](routing.md)).
`DhcpClient.addDefaultRoute` is a string because RouterOS has three
values: `yes`, `no`, `special-classless`.

## Relay

`addDhcpRelay` forwards the DHCP broadcasts on an interface to a central
server by unicast. The interface needs an address in the client network,
which tells the server which subnet to serve. Idempotent by name.

```jennifer
mt.addDhcpRelay($c, "vlan20-relay", "vlanoffice", "10.0.0.5");
```

## Pitfalls

- RouterOS allows one DHCP server per interface.
- A static lease for a device with an active dynamic lease applies at
  the next renewal.
- A WAN client stuck with status `searching...` usually means the ISP
  link is down or the modem is not bridging.
- Never run a DHCP server on the WAN interface.
- `removeDhcpClient` takes the WAN address, default route and DNS
  servers with it: the uplink is down until reconfigured.

See also: [ip.md](ip.md), [nat.md](nat.md), [ppp.md](ppp.md) (PPPoE
instead of DHCP on the WAN), [dns.md](dns.md).
