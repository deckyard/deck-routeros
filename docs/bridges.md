# Bridges

File: `src/topics/bridges.j`. Paths: `/interface/bridge` (`BRIDGE_PATH`),
`/interface/bridge/port` (`BRIDGE_PORT_PATH`), `/interface/bridge/vlan`
(`BRIDGE_VLAN_PATH`).

Reference: [cheatsheet](cheatsheet.md#bridges).

A bridge is a software switch: its ports share one layer-2 network. The
router's LAN address goes on the bridge, not on a member port.
`addBridgePort` checks that the bridge exists first, so a typo fails
instead of creating an orphan port. An interface can be a port of one
bridge only, which is why `removeBridgePort` takes just the interface.

```jennifer
mt.addBridge($c, "brlan");
mt.addBridgePort($c, "brlan", "ether2");
mt.addBridgePort($c, "brlan", "ether3");
mt.addBridgePort($c, "brlan", "wlan1");
mt.addIpAddress($c, "192.168.88.1/24", "brlan");

def ports as list of mt.BridgePort init mt.bridgePorts($c, "brlan");
for (def p in $ports) {
    io.printf("%s is on %s\n", $p.interfaceName, $p.bridge);
}

# move a port to another bridge
mt.removeBridgePort($c, "ether3");
mt.addBridgePort($c, "brguest", "ether3");
```

VLAN filtering (`enableVlanFiltering`, `addBridgeVlan`, `setPortPvid`) is
covered in [vlans.md](vlans.md); hardware offload of ports
(`setBridgePortHardwareOffload`) in [switch.md](switch.md).

## Pitfalls

- Bridging the WAN port into the LAN connects the ISP network to the LAN
  at layer 2.
- An address on `ether2` stops working once `ether2` joins a bridge.
- Removing a bridge does not fail on existing ports; RouterOS drops the
  memberships.
