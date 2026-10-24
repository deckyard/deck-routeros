# Interfaces

File: `src/topics/interfaces.j`. Path: `/interface` (`INTERFACE_PATH`).

Reference: [cheatsheet](cheatsheet.md#interfaces).

`/interface` lists every interface: physical ports and the virtual ones
other topics create (bridges, VLANs, PPPoE, WireGuard). Interfaces are not
created here. `running` means link up; `disabled` means switched off by
configuration. `kind` is RouterOS's `type` (`"ether"`, `"bridge"`,
`"wlan"`, ...); `mac` is `""` for interfaces without one.

```jennifer
def ifaces as list of mt.Interface init mt.interfaces($c);
for (def i in $ifaces) {
    io.printf("%s (%s) running=%t disabled=%t %s\n",
        $i.name, $i.kind, $i.running, $i.disabled, $i.comment);
}

mt.commentInterface($c, "ether1", "uplink to ISP");
mt.disableInterface($c, "ether5");

def wan as mt.Interface init mt.interfaceByName($c, "ether1");
if (not $wan.running) {
    io.printf("ether1 has no link\n");
}
```

## Pitfalls

- Disabling the interface your session uses cuts the session. The deck
  does not check for this.
- `running == false` with `disabled == false` is a physical-layer problem
  (no cable, no link partner).
- A rename updates RouterOS's own references (firewall rules, bridge
  ports), not comments or external scripts.

See also: [bridges.md](bridges.md), [vlans.md](vlans.md), [ip.md](ip.md).
