# IP addresses

File: `src/topics/ip.j`. Path: `/ip/address` (`IP_ADDRESS_PATH`).
Reference: [cheatsheet](cheatsheet.md#ip-addresses).

An address carries a prefix length: `192.168.88.1/24` puts the
interface in 192.168.88.0-255. `addIpAddress` rejects an address
without one, because RouterOS would make it a /32 with no connected
network. The CIDR is parsed with `ipnet`, and the interface must exist.

Addresses are static (set by you) or dynamic (put there by a DHCP
client or a PPP session; `dynamic` is true and they cannot be removed by
hand).

## Examples

Give the LAN bridge its gateway address:

```jennifer
mt.addIpAddress($c, "192.168.88.1/24", "brlan");
```

List every address with its origin:

```jennifer
def addrs as list of mt.IpAddress init mt.ipAddresses($c);
for (def a in $addrs) {
    io.printf("%s on %s dynamic=%t %s\n",
        $a.address, $a.interfaceName, $a.dynamic, $a.comment);
}
```

Renumber an interface:

```jennifer
mt.removeIpAddress($c, "192.168.88.1/24");
mt.addIpAddress($c, "10.0.10.1/24", "brlan");
```

## Pitfalls

- `removeIpAddress` matches the string exactly as listed:
  `"192.168.88.1/24"`, not `"192.168.88.1"`.
- Renumbering the interface your API session runs over drops the
  session as soon as the old address is gone.
- Dynamic addresses (WAN DHCP in [dhcp.md](dhcp.md), PPPoE in
  [ppp.md](ppp.md)) come and go with their session; do not manage them
  here.
- RouterOS accepts two interfaces in overlapping subnets; routing
  between them then breaks.

See also: [bridges.md](bridges.md) (the LAN address goes on the
bridge, not a member port), [routing.md](routing.md) (each address
creates a connected route).
