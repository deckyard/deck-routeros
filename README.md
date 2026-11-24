# routeros

[![test](https://github.com/deckyard/deck-routeros/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-routeros/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-routeros/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-routeros)](https://github.com/deckyard/deck-routeros/releases/latest)

`@deckyard/routeros` configures MikroTik™ routers from
[Jennifer](https://jennifer-lang.dev/). It wraps the bundled `mikrotik` module
(the RouterOS™ binary API: command paths, `=key=value` words, reply sentences) in
typed verbs and structs for interfaces, bridges, VLANs, the firewall, DHCP, DNS,
VPNs, queues, users, certificates, system maintenance and more. Input is
validated before anything is sent; local validation failures throw
`Error{kind: "routeros"}`, router refusals and failed logins
`mikrotik.MikrotikError` (kind `"mikrotik"`), and a router that cannot be
reached `net.NetError` (kind `"net"`).

**Infrastructure as Code (IaC).** A router's configuration becomes a Jennifer
program: kept in version control, reviewed, and re-run like any other code.
Many `add*` and `setup*` helpers are idempotent (by name, interface or
comment; the [cheatsheet](docs/cheatsheet.md) says which), so a script can be
applied again to bring a router back to the configuration it describes; the
others add a new item on every run. There is no plan or diff step: the deck
applies what the script says and does not detect drift.

## Install

```sh
jvc add @deckyard/routeros
```

jvc vendors the deck's `src/` to `vendor/deckyard/routeros/`. Without jvc,
unpack the `src/` subtree of a release archive
(`deckyard-routeros-<version>.tar.gz`) there.

Requires Jennifer 0.27.0 or newer, the default `jennifer` binary (the transport
needs `net`; `jennifer-tiny` stubs it) and a router with the `api-ssl` (8729)
or `api` (8728) service enabled. Login works on RouterOS 6.43+ and v7; the
transport falls back to MD5 challenge-response for older routers.

`connectTLS` (api-ssl) is the way in; a router with a self-signed or
private-CA certificate takes `connectTLSWithCA` and the PEM to trust. The plain `api` service, which many
home-lab routers run, sends the password in clear text, so the deck uses it
only when asked: `mt.connectWith(host, 8728, user, password, false, true)`,
the last argument being `allowInsecureAuth`. See [docs/core.md](docs/core.md).

## Example

```jennifer
import "@deckyard/routeros/" as mt;

def c as mt.Client init mt.connectTLS("192.168.88.1", "admin", "secret");
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

The deck changes the configuration of live network equipment: review what a
call does before running it against production hardware. Use at your own
risk; no warranty of any kind.

## License

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

## Trademarks

MikroTik™, RouterOS™, RouterBOARD™, WinBox™ and WebFig™ are trademarks of
SIA "Mikrotīkls". WireGuard™ is a trademark of Jason A. Donenfeld. OpenVPN™
is a trademark of OpenVPN, Inc. Cisco™ is a trademark of Cisco Systems, Inc.
CAPsMAN™, NetFlow™ and other product and company names may be trademarks of
their respective owners. They are used only to identify the products this
deck works with. This deck is an independent project, not affiliated with,
sponsored, endorsed or supported by SIA "Mikrotīkls".
