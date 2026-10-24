<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Switch chip (hardware offload)

File: `src/topics/switch.j`. Paths: `/interface/ethernet/switch`
(`ETHERNET_SWITCH_PATH`), `/interface/ethernet/switch/host`
(`ETHERNET_SWITCH_HOST_PATH`). The per-port `hw` flag lives in the
[bridges](bridges.md) topic: `BridgePort.hardwareOffload` and
`setBridgePortHardwareOffload`.

Reference: [cheatsheet](cheatsheet.md#switch-chip-hardware-offload).

## Background

Many MikroTik boards (CRS switches, hEX and other RB models) have a
switch chip that forwards frames between ports at wire speed without the
CPU. On RouterOS v7 you do not configure the chip directly: build a
[VLAN-aware bridge](vlans.md) (`enableVlanFiltering`, `addBridgeVlan`,
`setPortPvid`) and RouterOS pushes an offloadable configuration down to
the chip. The legacy per-chip config (`/interface/ethernet/switch/vlan`,
`.../rule`) is hardware-specific and superseded; this topic does not
wrap it. Reach it with the generic verbs on `/interface/ethernet/switch/*`
(switch rules, port mirroring, the legacy VLAN table) when you need it.

This topic answers three questions: does the board have a chip, is the
`hw` flag on per port, and is the chip forwarding (its MAC table
populated).

## Example: is the VLAN-aware bridge accelerated?

```jennifer
def chips as list of mt.SwitchChip init mt.switchChips($c);
if (len($chips) == 0) { io.printf("pure-CPU board - no hardware offload\n"); }
for (def ch in $chips) { io.printf("switch %s (%s)\n", $ch.name, $ch.kind); }

def ports as list of mt.BridgePort init mt.bridgePorts($c, "brlan");
for (def p in $ports) {
    io.printf("%s: hw=%t\n", $p.interfaceName, $p.hardwareOffload);
}

def hosts as list of mt.SwitchHost init mt.switchHosts($c);
io.printf("%d MACs learned in hardware\n", len($hosts));
```

Force a port to software forwarding, e.g. to use a software-only
feature on it:

```jennifer
mt.setBridgePortHardwareOffload($c, "ether2", false);
```

## Pitfalls

- `hw=yes` is intent, not proof. RouterOS falls back to software
  without telling you when the bridge config is not offloadable (some L3
  features, some VLAN configs, ports on more than one chip). Offload is
  working when the ports have `hardwareOffload == true`, CPU load stays
  low under traffic, and `switchHosts` holds your LAN's MACs.
- `switchChips` and `switchHosts` return an empty list on any read
  error, so a dropped session looks the same as "no chip" or "empty
  table".
- Traffic between ports on different switch chips crosses the CPU.
  `switchChips` shows how many chips there are.
- Turning `hw` off on an accelerated port moves its traffic to the CPU,
  which can saturate it on a busy port.

See also [ethernet.md](ethernet.md) for the ports and
[system.md](system.md) for CPU load.
