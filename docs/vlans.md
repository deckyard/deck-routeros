# VLANs

File: `src/topics/vlans.j`. Path: `/interface/vlan` (`VLAN_PATH`).

Reference: [cheatsheet](cheatsheet.md#vlans).

## Background

An 802.1Q VLAN lets several networks share one cable: each frame carries
a tag (1-4094), and both ends must use the same tag. In RouterOS a VLAN
interface sits on a parent (an ethernet port or a bridge): traffic sent
through it leaves the parent tagged, and frames arriving with that tag
come in on it. It is an ordinary interface otherwise: address it, serve
DHCP on it, route and firewall it.

`addVlan` rejects tags outside 1-4094 (0 and 4095 are reserved) and a
parent interface that does not exist.

## Examples

An office network on the cable to a managed switch. The switch port must
carry VLAN 20 tagged (a trunk port):

```jennifer
mt.addVlan($c, "vlanoffice", 20, "ether2");
mt.addIpAddress($c, "10.20.0.1/24", "vlanoffice");
mt.setupDhcp($c, "dhcpoffice", "vlanoffice", "10.20.0.0/24",
    "10.20.0.1", "10.20.0.10", "10.20.0.199", "10.20.0.1");
```

Router-on-a-stick, several networks over one uplink:

```jennifer
mt.addVlan($c, "vlanstaff", 10, "ether2");
mt.addVlan($c, "vlanguest", 30, "ether2");
mt.addIpAddress($c, "10.10.0.1/24", "vlanstaff");
mt.addIpAddress($c, "10.30.0.1/24", "vlanguest");
```

Inventory:

```jennifer
def vs as list of mt.Vlan init mt.vlans($c);
for (def v in $vs) {
    io.printf("vlan %s: tag %d on %s\n", $v.name, $v.vlanId, $v.interfaceName);
}
```

## VLAN-aware bridge

The sub-interfaces above suit a few VLANs terminated on the router, each
a routed interface. When the router also switches VLANs between ports,
or drives a managed-switch topology, put the VLANs on a VLAN-aware
bridge instead. It tags, untags and filters per port, and it is what
[hardware offload](switch.md) accelerates. The verbs live in the
[bridges](bridges.md) topic (`BRIDGE_VLAN_PATH`):

```jennifer
# ether1 trunks to a switch (tagged); ether2/3 are access ports for VLAN 10
mt.addBridgeVlan($c, "brlan", 10, "ether1", "ether2,ether3");
mt.setPortPvid($c, "brlan", "ether2", 10);
mt.setPortPvid($c, "brlan", "ether3", 10);
mt.addBridgeVlan($c, "brlan", 20, "ether1", "ether4");
mt.setPortPvid($c, "brlan", "ether4", 20);

mt.enableVlanFiltering($c, "brlan");   # last
```

`tagged` ports keep the tag (trunks to switches, or the bridge itself
for inter-VLAN routing). `untagged` ports strip it (access ports for end
devices), and an access port's PVID assigns untagged incoming frames to
its VLAN. `bridgeVlans` lists the table; `removeBridgeVlan` and
`disableVlanFiltering` undo it.

Enabling VLAN filtering before the table and PVIDs are right drops
untagged traffic, your own management session included if it runs over
that bridge. Build the table and PVIDs first, enable filtering last, and
keep a second way in (a separate management port or a console cable) the
first time.

## Pitfalls

- A VLAN whose far end is untagged or uses another tag drops traffic
  without an error; `running` stays true because the parent link is up.
- VLANs separate traffic at layer 2, but the router routes between VLAN
  interfaces by default. Add [firewall](firewall.md) forward rules if
  the networks must not talk to each other.
