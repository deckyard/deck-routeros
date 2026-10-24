# Tools: diagnostics from the router

File: `src/topics/tools.j`. Commands: `/ping` (`PING_COMMAND`),
`/tool/traceroute` (`TRACEROUTE_COMMAND`), `/tool/bandwidth-test`
(`BANDWIDTH_TEST_COMMAND`), `/tool/fetch` (`FETCH_COMMAND`); path
`/tool/e-mail` (`EMAIL_PATH`). Reference:
[cheatsheet](cheatsheet.md#tools).

These run on the router, so they answer whether the router reaches a
host, which is what matters when debugging an uplink, a VPN or a device
the router serves. Ping, traceroute, bandwidth test and fetch are
streaming commands in RouterOS that would run forever unbounded.
routeros always sends a bound (probe count, one probe per hop,
duration), merges the progress rows and returns one typed result.

## Ping and traceroute

```jennifer
def p as mt.PingResult init mt.ping($c, "1.1.1.1");
if ($p.reachable) {
    io.printf("uplink ok: %d/%d, avg %s\n", $p.received, $p.sent, $p.avgRtt);
} else {
    io.printf("uplink down (loss %d percent)\n", $p.packetLoss);
}

# routing works but DNS does not?
if (mt.isReachable($c, "1.1.1.1") and not mt.isReachable($c, "example.org")) {
    io.printf("check the DNS settings\n");
}

def hops as list of mt.TracerouteHop init mt.traceroute($c, "1.1.1.1");
for (def h in $hops) {
    io.printf("%s %s (loss %s) %s\n", $h.address, $h.avgRtt, $h.loss, $h.status);
}
```

RTT strings such as `"1ms52us"` are kept as RouterOS formats them.

## Bandwidth test

The far end must run a btest server: another MikroTik with
`/tool/bandwidth-server` enabled, or MikroTik's btest utility.

```jennifer
def bw as mt.BandwidthResult init mt.bandwidthTest($c, "192.168.88.2", 10, "both");
io.printf("rx %s bps / tx %s bps, lost %d\n", $bw.rxAverage, $bw.txAverage, $bw.lostPackets);
```

## Fetch

The router makes the HTTP(S) request from its own network position.
`fetchUrl` returns the body in `data`; `downloadFile` writes to storage.

```jennifer
def ip as mt.FetchResult init mt.fetchUrl($c, "https://ifconfig.co/ip");
if ($ip.ok) { io.printf("public IP: %s\n", $ip.data); }
mt.downloadFile($c, "https://example.org/config.rsc", "config.rsc");
```

## E-mail

Configure SMTP once; then `sendEmail` and RouterOS scripts can send
mail. Most relays want TLS, so use `configureEmailWith` with an
`EMAIL_TLS_*` mode; `configureEmail` leaves the router's TLS mode
unchanged. The password is write-only and `emailSettings` never
returns it.

```jennifer
mt.configureEmailWith($c, "smtp.example.org", 587,
    "[MikroTik gw1] <router@example.org>", "router", "secret",
    mt.EMAIL_TLS_STARTTLS);
mt.sendEmail($c, "noc@example.org", "WAN down", "the primary uplink just failed");

def e as mt.EmailSettings init mt.emailSettings($c);
if ($e.tls == mt.EMAIL_TLS_NONE) { io.printf("alerts leave in the clear\n"); }
```

RouterOS 7.12 renamed `address` to `server` and `start-tls` to `tls`.
Both configure calls read the settings row and write the spelling the
router uses; before 7.12, `EMAIL_TLS_STARTTLS` becomes `start-tls=yes`
and `EMAIL_TLS_IMPLICIT` becomes `start-tls=tls-only`.

Send from a [scheduler](scheduler.md) task for a nightly report, or from
a [netwatch](netwatch.md) down-script for alerts.

## Pitfalls

- The bandwidth test saturates the link and loads both CPUs. Do not run
  it on a production uplink during business hours. On small routers the
  CPU, not the link, may limit the result.
- Ping or traceroute to a DNS name needs working resolver settings
  ([dns.md](dns.md)); otherwise the router fails with `kind "mikrotik"`.
- 100 percent loss to a host behind a reachable gateway often means a
  firewall drops ICMP, not that the host is down.
