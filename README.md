# routeros

[![test](https://github.com/deckyard/deck-routeros/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-routeros/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-routeros/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-routeros)](https://github.com/deckyard/deck-routeros/releases/latest)

`@deckyard/routeros` configures MikroTik routers from
[Jennifer](https://jennifer-lang.dev/). It wraps the bundled `mikrotik` module
(the RouterOS binary API: command paths, `=key=value` words, reply sentences) in
typed verbs and structs for interfaces, bridges, VLANs, the firewall, DHCP, DNS,
VPNs, queues, users, certificates, system maintenance and more. Input is
validated before anything is sent; local validation failures throw
`Error{kind: "routeros"}`, router and transport failures `Error{kind: "mikrotik"}`.

## Install

```sh
jvc add @deckyard/routeros
```

jvc vendors the deck's `src/` to `vendor/deckyard/routeros/`. Without jvc,
unpack the `src/` subtree of a release archive
(`deckyard-routeros-<version>.tar.gz`) there.

Requires Jennifer 0.25.0 or newer, the default `jennifer` binary (the transport
needs `net`; `jennifer-tiny` stubs it) and a router with the `api` (8728) or
`api-ssl` (8729) service enabled. Login works on RouterOS 6.43+ and v7; the
transport falls back to MD5 challenge-response for older routers.

## Example

```jennifer
import "@deckyard/routeros/" as mt;

def c as mt.Client init mt.connect("192.168.88.1", "admin", "secret");
$c = mt.setVerbose($c, true);   # print each command, credentials redacted

mt.addBridge($c, "brlan");
mt.addBridgePort($c, "brlan", "ether2");
mt.allowService($c, "tcp", 22, "ssh management");

def r as mt.FirewallRule init mt.firewallRule(mt.CHAIN_FORWARD, mt.ACTION_DROP);
$r = mt.withProtocol($r, "tcp");
$r = mt.withDstPort($r, "445");
$r = mt.withComment($r, "no smb forwarding");
mt.addFirewallRule($c, $r);

mt.disconnect($c);
```

Every topic has a read-only example in [`examples/`](examples/):
`MT_HOST=... MT_USER=... MT_PASSWORD=... jennifer run examples/firewall.j`.

## Documentation

The [book](https://deckyard.github.io/deck-routeros/) has one guide per topic
and the [cheatsheet](docs/cheatsheet.md) with every function, constant and
struct. MikroTik's [RouterOS documentation](https://help.mikrotik.com/docs/)
covers the menus behind the paths.

## Disclaimer

MikroTik and RouterOS are trademarks of SIA Mikrotikls. This is an independent
library, not affiliated with, endorsed or supported by SIA Mikrotikls. It
changes the configuration of live network equipment: review what a call does
before running it against production hardware. Use at your own risk; no
warranty of any kind.

## License

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.
