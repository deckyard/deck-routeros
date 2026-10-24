# DNS

File: `src/topics/dns.j`. Paths: `/ip/dns` (`DNS_PATH`), `/ip/dns/static`
(`DNS_STATIC_PATH`), `/ip/dns/cache` (`DNS_CACHE_PATH`), `/ip/dns/adlist`
(`DNS_ADLIST_PATH`). Reference: [cheatsheet](cheatsheet.md#dns).

The router's resolver does two jobs. It resolves for the router itself
(update checks, NTP host names), which needs upstream servers. It can also
resolve for the LAN: clients send queries to the router, which caches and
forwards them; that needs `allow-remote-requests`. Static entries answer
local names (`nas.lan`) without upstream DNS.

`setDnsServers` accepts IP addresses only, comma-separated; spaces are
dropped (`" 1.1.1.1 , 9.9.9.9 "` becomes `"1.1.1.1,9.9.9.9"`).

## Examples

Use public resolvers and serve the LAN. The last argument of `setupDhcp`
is the DNS server handed to clients, here the router itself:

```jennifer
mt.setDnsServers($c, "1.1.1.1,9.9.9.9");
mt.allowRemoteDnsRequests($c, true);
mt.setupDhcp($c, "dhcplan", "brlan", "192.168.88.0/24",
    "192.168.88.1", "192.168.88.10", "192.168.88.199", "192.168.88.1");

mt.addDnsEntry($c, "nas.lan", "192.168.88.50");

def d as mt.DnsSettings init mt.dnsSettings($c);
io.printf("upstreams %s, cache %s of %s used\n", $d.servers, $d.cacheUsed, $d.cacheSize);
```

## The cache

Every answer stays cached until its TTL runs out, so the cache shows what
the router answers right now. Names match case-insensitively.

```jennifer
def records as list of mt.DnsCacheEntry init mt.dnsCacheFor($c, "example.org");
for (def rec in $records) {
    io.printf("%s %s -> %s (ttl %s)\n", $rec.kind, $rec.name, $rec.data, $rec.ttl);
}
def addrs as list of string init mt.resolvedAddresses($c, "example.org");   # A/AAAA only
mt.flushDnsCache($c);
```

`dnsCache(c)` returns the whole cache, which is large on a busy router.
Records with `isStatic` come from static entries; a flush keeps them.

## Adlists (RouterOS 7.15+)

The resolver answers `0.0.0.0` for every name on a hosts-format
blocklist, to every client that uses the router as its DNS server.

```jennifer
mt.allowRemoteDnsRequests($c, true);
mt.addAdlist($c, "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts");

def adlists as list of mt.DnsAdlist init mt.dnsAdlists($c);
for (def a in $adlists) { io.printf("%s blocks %s names\n", $a.url, $a.matchCount); }
```

`addAdlist` is idempotent by URL. The router holds the lists in RAM; a
small router may not fit a list of a million entries.

## Pitfalls

- With remote requests allowed, the router answers on every interface,
  the WAN included. Without a firewall rule it is an open resolver, used
  for amplification attacks. Drop port 53 from the WAN for UDP and TCP:

  ```jennifer
  def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_INPUT, mt.ACTION_DROP);
  $r = mt.withProtocol($r, "udp");
  $r = mt.withDstPort($r, "53");
  $r = mt.withInInterface($r, "ether1");
  $r = mt.withComment($r, "no dns from wan");
  mt.addFirewallRule($c, $r);
  # and again with "tcp"
  ```

- Static entries help only clients that use the router as their DNS
  server. `addDnsEntry` is not idempotent: a second call adds a duplicate.
- A WAN set up with `setupWan` adopts the ISP's DNS servers on every
  lease, replacing what `setDnsServers` set. Use
  `mt.setupWanWith($c, "ether1", false, true)` to keep yours.
- After `setDnsServers`, answers from the old upstreams stay cached until
  their TTL expires; `flushDnsCache` applies the change at once.
- An empty `dnsCacheFor` result means nobody asked for that name
  recently. It is not an error.

See also: [dhcp.md](dhcp.md), [firewall.md](firewall.md).
