# routeros cheatsheet

Every exported function, constant and struct, one section per topic. Calls
take an open `Client` as `c`:

```jennifer
import "@deckyard/routeros/" as mt;
def c as mt.Client init mt.connect("192.168.88.1", "admin", "secret");
```

Unless a row says otherwise, invalid input throws `Error{kind: "routeros"}`
before anything is sent, and a router refusal throws `Error{kind: "mikrotik"}`.
The `*_PATH` constants are RouterOS menu paths for the generic verbs in
[Core](#core).

## Core

Guide: [Core](core.md).

| Function | Returns | Notes |
|---|---|---|
| `connect(host, user, password)` | `Client` | plaintext API, port 8728; `MT_VERBOSE` seeds the verbose flag |
| `connectTLS(host, user, password)` | `Client` | api-ssl, port 8729; the certificate is verified |
| `connectWith(host, port, user, password, tls)` | `Client` | explicit port (1-65535, else `routeros` error) and TLS choice |
| `disconnect(c)` | | close the session; the client is unusable afterwards |
| `getAll(c, path)` | `list of map of string to string` | every item under any list path, one property map each |
| `add(c, path, attrs)` | `string` | create an item; returns its id (e.g. `"*3"`) |
| `remove(c, path, id)` | | delete by id (RouterOS has no separate delete) |
| `set(c, path, id, attrs)` | | change properties of an item |
| `update(c, path, id, attrs)` | | synonym of `set` |
| `findByName(c, path, name)` | `map of string to string` | first item whose `name` matches, filtered on the router; empty map on a miss |
| `idByName(c, path, name)` | `string` | id of the item with that `name`, `""` on a miss |
| `removeByName(c, path, name)` | | delete by `name`; `routeros` error when absent |
| `enable(c, path, id)` | | set `disabled=no` |
| `disable(c, path, id)` | | set `disabled=yes`; the item stays but has no effect |
| `moveRule(c, path, id, beforeId)` | | move above `beforeId`; `""` = bottom; a self-move is rejected |
| `moveRuleToTop(c, path, id)` | | reads the list; no-op when already first; `routeros` error on an empty list |
| `moveRuleToBottom(c, path, id)` | | same as `moveRule` with `""` |
| `setVerbose(c, enabled)` | `Client` | returns a copy with command logging on/off: `$c = mt.setVerbose($c, true);` |
| `isVerbose(c)` | `bool` | whether the client logs commands |

### `Client`

An open, authenticated connection to one router.

| Field | Meaning |
|---|---|
| `session as mikrotik.Session` | the underlying API session |
| `user as string` | the logged-in account; the user helpers refuse to remove, disable or regroup it |
| `verbose as bool` | print every command to stdout before sending it (see `setVerbose`) |

## Interfaces

Guide: [Interfaces](interfaces.md).

| Function | Returns | Notes |
|---|---|---|
| `interfaces(c)` | `list of Interface` | every interface, physical and virtual |
| `interfaceByName(c, name)` | `Interface` | `routeros` error when absent |
| `enableInterface(c, name)` | | |
| `disableInterface(c, name)` | | no traffic passes until enabled |
| `renameInterface(c, current, next)` | | new name non-empty, no spaces; RouterOS updates its own references |
| `commentInterface(c, name, comment)` | | `""` clears the comment |

| Constant | Value |
|---|---|
| `INTERFACE_PATH` | `"/interface"` |

### `Interface`

One network interface as reported by the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id (e.g. "*1") |
| `name as string` | interface name (e.g. "ether1") |
| `kind as string` | interface type (e.g. "ether", "bridge", "wlan") |
| `mac as string` | hardware MAC address, "" when the router reports none |
| `running as bool` | link up and passing traffic |
| `disabled as bool` | administratively off |
| `comment as string` | free-text comment, "" when unset |

## Interface lists

Guide: [Interface lists](interfacelist.md).

| Function | Returns | Notes |
|---|---|---|
| `interfaceLists(c)` | `list of InterfaceList` | includes the built-in `all`, `none`, `dynamic` |
| `addInterfaceList(c, name, comment)` | `string` | idempotent by name; returns the new or existing id |
| `removeInterfaceList(c, name)` | | memberships go with it |
| `interfaceListMembers(c, listName)` | `list of string` | member interface names; empty for an unknown list |
| `addToInterfaceList(c, listName, interfaceName)` | `string` | creates a missing list; interface must exist; idempotent |
| `removeFromInterfaceList(c, listName, interfaceName)` | | `routeros` error when not a member |

| Constant | Value |
|---|---|
| `INTERFACE_LIST_PATH` | `"/interface/list"` |
| `INTERFACE_LIST_MEMBER_PATH` | `"/interface/list/member"` |

### `InterfaceList`

One interface list: a named group of interfaces.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | the list name (e.g. "WAN", "LAN") |
| `dynamic as bool` | created by the system, not configured |
| `comment as string` | free-text comment, "" when unset |

## Ethernet ports

Guide: [Ethernet ports](ethernet.md).

| Function | Returns | Notes |
|---|---|---|
| `ethernetPorts(c)` | `list of EthernetPort` | configuration of every port |
| `ethernetPortByName(c, name)` | `EthernetPort` | `routeros` error when absent |
| `linkStatus(c, name)` | `LinkStatus` | measured now (`monitor once`): up, rate, duplex |
| `forceEthernetLink(c, name, speed, fullDuplex)` | | auto-negotiation off; speed `10Mbps` `100Mbps` `1Gbps` `2.5Gbps` `5Gbps` `10Gbps`; force both ends alike |
| `autoNegotiateEthernet(c, name)` | | back to the default |
| `setEthernetMtu(c, name, mtu)` | | 68-65535; the port l2mtu caps it (router error above) |
| `setPoe(c, name, mode)` | | `auto-on`, `forced-on`, `off`; refuses ports without PoE |

| Constant | Value |
|---|---|
| `ETHERNET_PATH` | `"/interface/ethernet"` |

### `EthernetPort`

One physical ethernet port and its configuration.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | current name (e.g. "ether1") |
| `defaultName as string` | factory name, stable across renames |
| `mac as string` | MAC address |
| `mtu as string` | configured MTU as reported |
| `autoNegotiation as bool` | speed and duplex negotiated (the default) |
| `poeOut as string` | PoE mode ("auto-on", "forced-on", "off"), "" on ports without PoE |
| `running as bool` | link up |
| `slave as bool` | member of a bridge or bond, whose settings then mostly apply instead |
| `disabled as bool` | administratively off |
| `comment as string` | free-text comment, "" when unset |

### `LinkStatus`

The measured state of one ethernet link.

| Field | Meaning |
|---|---|
| `name as string` | the port |
| `up as bool` | status is "link-ok" |
| `status as string` | raw status ("link-ok", "no-link", ...) |
| `rate as string` | negotiated speed (e.g. "1Gbps"), "" when down |
| `fullDuplex as bool` | full-duplex link |
| `autoNegotiation as string` | negotiation state ("done", "incomplete", "disabled") |

## LTE / cellular

Guide: [LTE / cellular](lte.md).

| Function | Returns | Notes |
|---|---|---|
| `lteInterfaces(c)` | `list of LteInterface` | empty on any read error: no modem, or a dropped connection |
| `lteStatus(c, name)` | `LteStatus` | measured now (`monitor once`): registration, operator, signal |
| `setLteApn(c, interfaceName, apn)` | | creates/updates APN profile `routeros-<interface>` and binds it; APN must not be empty |
| `enableLte(c, name)` | | |
| `disableLte(c, name)` | | the cellular uplink drops |

| Constant | Value |
|---|---|
| `LTE_PATH` | `"/interface/lte"` |
| `LTE_APN_PATH` | `"/interface/lte/apn"` |

### `LteInterface`

One LTE (cellular) interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | the interface name (e.g. "lte1") |
| `running as bool` | the modem has a data connection |
| `disabled as bool` | administratively off |
| `comment as string` | free-text comment, "" when unset |

### `LteStatus`

The measured state of an LTE modem.

| Field | Meaning |
|---|---|
| `status as string` | registration status ("registered", ...) |
| `registered as bool` | the status contains "registered" |
| `operator as string` | the mobile network operator |
| `accessTechnology as string` | "lte" / "5g" / "hspa" / ... as reported |
| `signalStrength as string` | RSSI as reported (dBm) |
| `rsrp as string` | reference signal received power (LTE) |
| `rsrq as string` | reference signal received quality (LTE) |
| `sinr as string` | signal-to-noise ratio |

## Bonding (link aggregation)

Guide: [Bonding (link aggregation)](bonding.md).

| Function | Returns | Notes |
|---|---|---|
| `bonds(c)` | `list of Bond` | |
| `bondByName(c, name)` | `Bond` | `routeros` error when absent |
| `addBond(c, name, slaves, mode)` | `string` | mode: `balance-rr` `active-backup` `balance-xor` `broadcast` `802.3ad` `balance-tlb` `balance-alb` |
| `addLacpBond(c, name, slaves)` | `string` | 802.3ad; the switch needs a matching LACP group; one flow uses one link |
| `addFailoverBond(c, name, slaves, primary)` | `string` | active-backup, any switch; `primary` must be a slave |
| `setBondSlaves(c, name, slaves)` | | same checks as creation; own members do not count as in use |
| `removeBond(c, name)` | | members become plain ports; remove bridge ports/addresses on the bond first |
| `enableBond(c, name)` | | |
| `disableBond(c, name)` | | no member carries traffic |

| Constant | Value |
|---|---|
| `BONDING_PATH` | `"/interface/bonding"` |
| `BOND_LACP` | `"802.3ad"` |
| `BOND_ACTIVE_BACKUP` | `"active-backup"` |

### `Bond`

One bonding interface: several physical links acting as one.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | bond name (e.g. "bondtrunk") |
| `slaves as string` | member interfaces, comma-separated |
| `mode as string` | bonding mode ("802.3ad", "active-backup", ...) |
| `primary as string` | preferred link in active-backup mode, "" otherwise |
| `transmitHashPolicy as string` | how 802.3ad spreads flows, "" when default |
| `mac as string` | MAC address |
| `mtu as string` | MTU as reported |
| `running as bool` | at least one member link is up |
| `disabled as bool` | administratively off |
| `comment as string` | free-text comment, "" when unset |

## Bridges

Guide: [Bridges](bridges.md).

| Function | Returns | Notes |
|---|---|---|
| `bridges(c)` | `list of Bridge` | |
| `addBridge(c, name)` | `string` | name non-empty, no spaces |
| `removeBridge(c, name)` | | RouterOS drops the memberships |
| `bridgePorts(c, bridgeName)` | `list of BridgePort` | ports of one bridge; empty for an unknown bridge |
| `addBridgePort(c, bridgeName, interfaceName)` | `string` | the bridge must exist |
| `removeBridgePort(c, interfaceName)` | | detach from whichever bridge holds it |
| `setBridgePortHardwareOffload(c, interfaceName, on)` | | the port `hw` flag; on only permits offload, check with `switchHosts` |
| `bridgeVlans(c)` | `list of BridgeVlan` | the bridge VLAN table |
| `enableVlanFiltering(c, bridge)` | | enable last: with an incomplete VLAN table it drops untagged traffic, your own session included |
| `disableVlanFiltering(c, bridge)` | | |
| `addBridgeVlan(c, bridge, vlanId, tagged, untagged)` | `string` | VLAN 1-4094; port lists comma-separated, `""` for none; idempotent by bridge and VLAN, an existing entry is not changed |
| `setPortPvid(c, bridge, port, pvid)` | | access-port VLAN, 1-4094; the port must be on the bridge |
| `removeBridgeVlan(c, bridge, vlanId)` | | `routeros` error when no such entry |

| Constant | Value |
|---|---|
| `BRIDGE_PATH` | `"/interface/bridge"` |
| `BRIDGE_PORT_PATH` | `"/interface/bridge/port"` |
| `BRIDGE_VLAN_PATH` | `"/interface/bridge/vlan"` |

### `BridgeVlan`

One bridge VLAN-table entry: which ports carry a VLAN, tagged or not.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `bridge as string` | the bridge this applies to |
| `vlanIds as string` | VLAN ids as reported (list or range) |
| `tagged as string` | trunk ports, carrying the VLAN tagged |
| `untagged as string` | access ports, carrying it untagged |
| `dynamic as bool` | added by RouterOS, not configured |

### `Bridge`

One bridge: a software switch joining its ports into one LAN.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | bridge name (e.g. "bridge1") |
| `mac as string` | MAC address |
| `running as bool` | bridge is up |
| `disabled as bool` | administratively off |
| `comment as string` | free-text comment, "" when unset |

### `BridgePort`

One bridge membership: an interface attached to a bridge.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `bridge as string` | name of the bridge |
| `interfaceName as string` | name of the member interface |
| `hardwareOffload as bool` | the `hw` flag: the port may forward in the switch chip; whether it does depends on the bridge config (see `switchHosts`) |
| `disabled as bool` | membership is off |

## Switch chip (hardware offload)

Guide: [Switch chip (hardware offload)](switch.md).

| Function | Returns | Notes |
|---|---|---|
| `switchChips(c)` | `list of SwitchChip` | Empty on a board without a switch chip, and on any read error. |
| `switchHosts(c)` | `list of SwitchHost` | The whole hardware MAC table. LAN MACs here mean the chip forwards their traffic. Empty on any read error. |

| Constant | Value |
|---|---|
| `ETHERNET_SWITCH_PATH` | `"/interface/ethernet/switch"` |
| `ETHERNET_SWITCH_HOST_PATH` | `"/interface/ethernet/switch/host"` |

### `SwitchChip`

One switch chip on the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | chip name, e.g. "switch1" |
| `kind as string` | chip model as reported (the `type` property), e.g. "Atheros-8327" |

### `SwitchHost`

One entry in the switch chip's hardware MAC table.

| Field | Meaning |
|---|---|
| `mac as string` | learned MAC address |
| `ports as string` | switch port(s) it was learned on |
| `vlanId as int` | VLAN id, 0 when untagged or not reported |
| `dynamic as bool` | true when learned, false for a static entry |

## VLANs

Guide: [VLANs](vlans.md).

| Function | Returns | Notes |
|---|---|---|
| `vlans(c)` | `list of Vlan` | All VLAN interfaces. |
| `vlanByName(c, name)` | `Vlan` | Throws when absent. |
| `addVlan(c, name, vlanId, interfaceName)` | `string` | Tag 1-4094; parent must exist. Returns the id. |
| `removeVlan(c, name)` |  | Throws when absent. |
| `enableVlan(c, name)` |  | Throws when absent. |
| `disableVlan(c, name)` |  | Throws when absent. |

| Constant | Value |
|---|---|
| `VLAN_PATH` | `"/interface/vlan"` |

### `Vlan`

One VLAN interface: an 802.1Q-tagged virtual interface on a parent.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | interface name, e.g. "vlanoffice" |
| `vlanId as int` | 802.1Q tag, 1-4094 |
| `interfaceName as string` | parent interface |
| `mtu as string` | MTU as reported |
| `running as bool` | true when the parent is up |
| `disabled as bool` | true when the VLAN is switched off |
| `comment as string` | comment, "" when unset |

## Wireless (WiFi)

Guide: [Wireless (WiFi)](wireless.md).

| Function | Returns | Notes |
|---|---|---|
| `wirelessInterfaces(c)` | `list of WirelessInterface` | Radios and virtual APs. Empty without the classic menu (wifiwave2 hardware) and on any read error. |
| `setupWifiAccessPoint(c, interfaceName, ssid, password)` |  | SSID, mode ap-bridge, WPA2-PSK key in profile `routeros-<interface>` (never `default`), enable. Idempotent. |
| `setWifiSsid(c, interfaceName, ssid)` |  | SSID 1-32 characters. Disconnects clients. |
| `setWifiPassword(c, interfaceName, password)` |  | Passphrase 8-63 characters. Moves the interface off `default` to its own profile first. Disconnects clients. |
| `addVirtualAp(c, masterInterface, name, ssid, password)` | `string` | Second SSID with its own profile on the same radio (guest WiFi). Returns the id. |
| `removeVirtualAp(c, name)` |  | Refuses a physical radio. Keeps the security profile. |
| `enableWifi(c, interfaceName)` |  | Throws when the interface is unknown. |
| `disableWifi(c, interfaceName)` |  | The network disappears from the air. |
| `wifiClients(c)` | `list of WifiClient` | Connected clients with signal and rates. Empty without the classic menu and on any read error. |

| Constant | Value |
|---|---|
| `WIRELESS_PATH` | `"/interface/wireless"` |
| `WIRELESS_SECURITY_PATH` | `"/interface/wireless/security-profiles"` |
| `WIRELESS_REGISTRATION_PATH` | `"/interface/wireless/registration-table"` |

### `WirelessInterface`

One wireless interface: a radio, or a virtual AP on top of one.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | interface name, e.g. "wlan1" |
| `ssid as string` | broadcast network name |
| `mode as string` | "ap-bridge" (access point), "station" (client), ... |
| `band as string` | radio band, e.g. "2ghz-b/g/n", "5ghz-a/n/ac" |
| `frequency as string` | channel frequency in MHz, or "auto" |
| `securityProfile as string` | security profile holding the password |
| `masterInterface as string` | parent radio of a virtual AP, "" for a physical radio |
| `running as bool` | true when the radio is up and serving |
| `disabled as bool` | true when the interface is switched off |
| `comment as string` | comment, "" when unset |

### `WifiClient`

One connected wireless client (a registration-table entry).

| Field | Meaning |
|---|---|
| `interfaceName as string` | wireless interface the client is on |
| `mac as string` | client MAC address |
| `signalStrength as string` | signal as reported, e.g. "-52dBm" |
| `txRate as string` | current transmit rate as reported |
| `rxRate as string` | current receive rate as reported |
| `uptime as string` | time connected, as reported |

## Modern WiFi (wifiwave2 / ax)

Guide: [Modern WiFi (wifiwave2 / ax)](wifi.md).

| Function | Returns | Notes |
|---|---|---|
| `wifiInterfaces(c)` | `list of WifiInterface` | Radios and virtual APs. Empty without `/interface/wifi` and on any read error. |
| `setupWifi(c, interfaceName, ssid, password)` |  | Mode ap, SSID, WPA2-PSK + WPA3-PSK passphrase on the interface, enable. Idempotent. |
| `setWifiPassphrase(c, interfaceName, password)` |  | 8-63 characters. Disconnects clients. |
| `addVirtualWifi(c, masterInterface, name, ssid, password)` | `string` | Guest SSID on the same radio, WPA2/WPA3. Returns the id. |
| `removeVirtualWifi(c, name)` |  | Refuses a physical radio. |
| `wifiRegistrations(c)` | `list of WifiRegistration` | Connected clients. Empty without `/interface/wifi` and on any read error. |

| Constant | Value |
|---|---|
| `WIFI_PATH` | `"/interface/wifi"` |
| `WIFI_REGISTRATION_PATH` | `"/interface/wifi/registration-table"` |

### `WifiInterface`

One modern (wifiwave2/ax) WiFi interface: a radio or a virtual AP.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | interface name, e.g. "wifi1" |
| `ssid as string` | configured network name (`configuration.ssid`) |
| `band as string` | configured band (`channel.band`), e.g. "5ghz-ax" |
| `masterInterface as string` | parent radio of a virtual AP, "" for a radio |
| `running as bool` | true when up and serving |
| `disabled as bool` | true when switched off |
| `comment as string` | comment, "" when unset |

### `WifiRegistration`

One connected client on a modern WiFi interface.

| Field | Meaning |
|---|---|
| `interfaceName as string` | WiFi interface the client is on |
| `ssid as string` | network it joined |
| `mac as string` | client MAC address |
| `signal as string` | signal in dBm, as reported |
| `uptime as string` | time connected, as reported |

## CAPsMAN

Guide: [CAPsMAN](capsman.md).

| Function | Returns | Notes |
|---|---|---|
| `capsmanStatus(c)` | `CapsmanStatus` | Tries CAPsMANv2, then legacy. `version` 0 when neither answers (read errors included). |
| `enableCapsman(c)` |  | Manager switch only; configuration and provisioning stay with the generic verbs. Throws without a CAPsMAN menu. |
| `disableCapsman(c)` |  | Throws without a CAPsMAN menu. |
| `managedAps(c)` | `list of ManagedAp` | Registered APs; empty when none or no CAPsMAN. |

| Constant | Value |
|---|---|
| `CAPSMAN_PATH` | `"/caps-man/manager"` |
| `CAPSMAN_REGISTRATION_PATH` | `"/caps-man/registration-table"` |
| `CAPSMAN_REMOTE_PATH` | `"/caps-man/remote-cap"` |
| `WIFI_CAPSMAN_PATH` | `"/interface/wifi/capsman"` |
| `WIFI_CAP_PATH` | `"/interface/wifi/cap"` |

### `CapsmanStatus`

The state of a CAPsMAN controller (either generation).

| Field | Meaning |
|---|---|
| `enabled as bool` | true when the controller is running |
| `version as int` | 1 (legacy /caps-man), 2 (/interface/wifi), 0 when neither exists |
| `managedAps as int` | number of access points it manages now |

### `ManagedAp`

One access point registered with the controller.

| Field | Meaning |
|---|---|
| `identity as string` | AP identity (name) |
| `address as string` | address the AP connected from |
| `interfaceName as string` | managed radio interface |
| `state as string` | provisioning state |

## Firewall (filter rules)

Guide: [Firewall (filter rules)](firewall.md).

| Function | Returns | Notes |
|---|---|---|
| `firewallRule(chain, action)` | `FirewallRule` | New builder matching everything in `chain`. Chain non-empty, no spaces; action one of accept, drop, reject, log, jump, return, passthrough, tarpit, fasttrack-connection, notrack. |
| `withSrcAddressList(rule, listName)` | `FirewallRule` | Copy matching an address list as source. |
| `withDstAddressList(rule, listName)` | `FirewallRule` | Copy matching an address list as destination. |
| `withProtocol(rule, protocol)` | `FirewallRule` | tcp, udp, icmp, gre, ipip, ospf, igmp, ipsec-esp, ipsec-ah, l2tp, sctp, vrrp. |
| `withSrcAddress(rule, address)` | `FirewallRule` | Address or CIDR; only empty or spaced values are rejected locally. |
| `withDstAddress(rule, address)` | `FirewallRule` | Address or CIDR; only empty or spaced values are rejected locally. |
| `withSrcPort(rule, spec)` | `FirewallRule` | "80", "80,443" or "8000-8100". Needs a protocol by `addFirewallRule`. |
| `withDstPort(rule, spec)` | `FirewallRule` | "80", "80,443" or "8000-8100". Needs a protocol by `addFirewallRule`. |
| `withInInterface(rule, name)` | `FirewallRule` | Copy matching the incoming interface. |
| `withOutInterface(rule, name)` | `FirewallRule` | Copy matching the outgoing interface. |
| `withInInterfaceList(rule, listName)` | `FirewallRule` | Copy matching an interface list, e.g. "WAN". |
| `withOutInterfaceList(rule, listName)` | `FirewallRule` | Copy matching an interface list as outgoing. |
| `withComment(rule, comment)` | `FirewallRule` | The handle the *ByComment verbs use; keep it distinct. |
| `withDisabled(rule, disabled)` | `FirewallRule` | Create the rule switched off. |
| `firewallRules(c)` | `list of FirewallRule` | All filter rules, ids set. |
| `addFirewallRule(c, rule)` | `string` | Appends to the chain. Rejects a port match without a protocol. Returns the id. |
| `removeFirewallRule(c, id)` |  | By id. |
| `removeFirewallRuleByComment(c, comment)` |  | Throws when no rule carries the comment. |
| `enableFirewallRuleByComment(c, comment)` |  | Throws when no rule carries the comment. |
| `disableFirewallRuleByComment(c, comment)` |  | Keeps the rule; throws when no rule carries the comment. |
| `moveFirewallRule(c, id, beforeId)` |  | Place `id` directly above `beforeId`; "" for the bottom. Rejects a self-move. |
| `moveFirewallRuleByComment(c, comment, beforeComment)` |  | `moveFirewallRule` by comments; "" for the bottom. |
| `allowService(c, protocol, port, comment)` | `string` | Input-chain accept for one port (1-65535), appended. Returns the id. |
| `blockAddress(c, address, comment)` | `string` | Input-chain drop for a source, appended; forwarded traffic unaffected. Returns the id. |

| Constant | Value |
|---|---|
| `FIREWALL_PATH` | `"/ip/firewall/filter"` |
| `CHAIN_INPUT` | `"input"` |
| `CHAIN_FORWARD` | `"forward"` |
| `CHAIN_OUTPUT` | `"output"` |
| `ACTION_ACCEPT` | `"accept"` |
| `ACTION_DROP` | `"drop"` |
| `ACTION_REJECT` | `"reject"` |
| `ACTION_NOTRACK` | `"notrack"` |

### `FirewallRule`

One firewall filter rule, both as a builder and as a query result.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id, "" on a rule you build |
| `chain as string` | chain: input, forward, output, or a custom chain |
| `action as string` | action on a match: accept, drop, reject, ... |
| `protocol as string` | IP protocol to match, "" for any |
| `srcAddress as string` | source address or CIDR network, "" for any |
| `dstAddress as string` | destination address or CIDR network, "" for any |
| `srcAddressList as string` | source address list, "" for none |
| `dstAddressList as string` | destination address list, "" for none |
| `srcPort as string` | source port, list, or range, "" for any |
| `dstPort as string` | destination port, list, or range, "" for any |
| `inInterface as string` | interface the packet arrived on, "" for any |
| `outInterface as string` | interface the packet would leave on, "" for any |
| `inInterfaceList as string` | interface list the packet arrived on, "" for any |
| `outInterfaceList as string` | interface list the packet would leave on, "" for any |
| `comment as string` | comment, also the handle for the *ByComment verbs |
| `disabled as bool` | true when the rule is (or is created) switched off |

## NAT

Guide: [NAT](nat.md).

| Function | Returns | Notes |
|---|---|---|
| `natRules(c)` | `list of NatRule` | all NAT rules, table order |
| `addMasquerade(c, outInterface, comment)` | `string` | srcnat masquerade out of `outInterface`; idempotent per interface (existing id returned, `comment` ignored); unknown interface rejected |
| `forwardPort(c, protocol, publicPort, toAddress, toPort, comment)` | `string` | dst-nat from any interface; `protocol` tcp or udp only, ports 1-65535, `toAddress` an IP; not idempotent; the forward chain must also accept the traffic |
| `forwardPortOn(c, inInterface, protocol, publicPort, toAddress, toPort, comment)` | `string` | as `forwardPort`, matching only `inInterface` (use the WAN); the interface is looked up first |
| `removeNatRule(c, id)` |  | delete by id |
| `removeNatRuleByComment(c, comment)` |  | delete by comment |
| `enableNatRuleByComment(c, comment)` |  | enable by comment |
| `disableNatRuleByComment(c, comment)` |  | disable by comment; the rule is kept |
| `moveNatRule(c, id, beforeId)` |  | place above `beforeId`; `""` = bottom; a self-move is rejected |
| `moveNatRuleByComment(c, comment, beforeComment)` |  | same, by comment handles; `""` = bottom |

| Constant | Value |
|---|---|
| `NAT_PATH` | `"/ip/firewall/nat"` |
| `CHAIN_SRCNAT` | `"srcnat"` |
| `CHAIN_DSTNAT` | `"dstnat"` |
| `ACTION_MASQUERADE` | `"masquerade"` |
| `ACTION_DST_NAT` | `"dst-nat"` |

### `NatRule`

One firewall NAT rule as read back from the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `chain as string` | "srcnat" (outgoing) or "dstnat" (incoming) |
| `action as string` | "masquerade", "dst-nat", ... |
| `protocol as string` | matched IP protocol, "" for any |
| `srcAddress as string` | matched source address or network, "" for any |
| `dstAddress as string` | matched destination address or network, "" for any |
| `dstPort as string` | matched destination port(s), "" for any |
| `toAddresses as string` | dst-nat target address |
| `toPorts as string` | dst-nat target port |
| `inInterface as string` | incoming interface match, "" for any |
| `outInterface as string` | outgoing interface match, "" for any |
| `comment as string` | comment; the *ByComment handle |
| `disabled as bool` | true when the rule is switched off |

## Mangle

Guide: [Mangle](mangle.md).

| Function | Returns | Notes |
|---|---|---|
| `mangleRules(c)` | `list of MangleRule` | all mangle rules, table order |
| `setupPacketMark(c, markName, matcher)` | `string` | connection mark `<markName>-conn` on new connections, then packet mark `markName`; the matcher keeps its chain (use `CHAIN_PREROUTING`), loses action and comment; idempotent by mark |
| `removePacketMark(c, markName)` |  | removes both rules of the mark; throws when none exists |
| `markRoutingFor(c, markName, srcAddress)` | `string` | mark-routing in prerouting for an IP or CIDR source; the table must exist (v7) and have a default route; idempotent by mark and source |
| `removeRoutingMark(c, markName, srcAddress)` |  | undo `markRoutingFor`; throws when absent |
| `clampTcpMss(c, interfaceName)` |  | `change-mss` to `clamp-to-pmtu` for SYNs in forward, in and out of the interface; idempotent; for PPPoE and tunnels |
| `removeTcpMssClamp(c, interfaceName)` |  | removes both clamp rules; throws when none exists |
| `moveMangleRule(c, id, beforeId)` |  | place above `beforeId`; `""` = bottom |
| `moveMangleRuleByComment(c, comment, beforeComment)` |  | same, by comment handles |

| Constant | Value |
|---|---|
| `MANGLE_PATH` | `"/ip/firewall/mangle"` |
| `CHAIN_PREROUTING` | `"prerouting"` |
| `CHAIN_POSTROUTING` | `"postrouting"` |

### `MangleRule`

One mangle rule as read back from the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `chain as string` | "prerouting", "forward", "postrouting", ... |
| `action as string` | "mark-connection", "mark-packet", "mark-routing", "change-mss", ... |
| `newConnectionMark as string` | connection mark set, "" when none |
| `newPacketMark as string` | packet mark set, "" when none |
| `newRoutingMark as string` | routing mark (table name) set, "" when none |
| `newMss as string` | MSS set by change-mss, "" when none |
| `connectionMark as string` | matched connection mark, "" for any |
| `packetMark as string` | matched packet mark, "" for any |
| `protocol as string` | matched protocol, "" for any |
| `srcAddress as string` | matched source, "" for any |
| `dstAddress as string` | matched destination, "" for any |
| `dstPort as string` | matched destination port(s), "" for any |
| `inInterface as string` | matched incoming interface, "" for any |
| `outInterface as string` | matched outgoing interface, "" for any |
| `passthrough as bool` | true when later rules still see the packet |
| `disabled as bool` | true when the rule is switched off |
| `comment as string` | comment; the handle the setup verbs use |

## Firewall raw (pre-conntrack)

Guide: [Firewall raw (pre-conntrack)](raw.md).

| Function | Returns | Notes |
|---|---|---|
| `rawRules(c)` | `list of RawRule` | all raw rules, table order |
| `addRawRule(c, rule)` | `string` | append a firewall-builder rule; raw takes chains prerouting/output and actions accept/drop/notrack, checked by the router (kind "mikrotik") |
| `dropRawAddressList(c, listName, comment)` | `string` | drop a source address list in prerouting |
| `removeRawRule(c, id)` |  | delete by id |
| `removeRawRuleByComment(c, comment)` |  | delete by comment |
| `moveRawRule(c, id, beforeId)` |  | place above `beforeId`; `""` = bottom |
| `moveRawRuleByComment(c, comment, beforeComment)` |  | same, by comment handles |

| Constant | Value |
|---|---|
| `RAW_PATH` | `"/ip/firewall/raw"` |

### `RawRule`

One raw-table rule as read back from the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `chain as string` | "prerouting" or "output" |
| `action as string` | "accept", "drop", "notrack", ... |
| `protocol as string` | matched protocol, "" for any |
| `srcAddress as string` | matched source, "" for any |
| `dstAddress as string` | matched destination, "" for any |
| `srcAddressList as string` | source address list, "" for none |
| `inInterfaceList as string` | incoming interface list, "" for none |
| `comment as string` | comment; the *ByComment handle |
| `disabled as bool` | true when switched off |

## Connection tracking

Guide: [Connection tracking](contrack.md).

| Function | Returns | Notes |
|---|---|---|
| `conntrackSettings(c)` | `ConntrackSettings` | tracking switch, table fill and capacity |
| `connections(c)` | `list of Connection` | whole table; thousands of rows on a busy router |
| `connectionsFor(c, address)` | `list of Connection` | connections whose src or dst contains `address` as a substring (`10.0.0.1` also matches `10.0.0.10`-`19` and `.100`-`.199`) |
| `dropConnectionsFor(c, address)` | `int` | removes the same substring matches, so it can hit other hosts; returns the count; does not block reconnects |

| Constant | Value |
|---|---|
| `CONNTRACK_SETTINGS_PATH` | `"/ip/firewall/connection/tracking"` |
| `CONNECTION_PATH` | `"/ip/firewall/connection"` |

### `ConntrackSettings`

The connection-tracking settings and table fill.

| Field | Meaning |
|---|---|
| `enabled as string` | "auto", "yes" or "no", as reported |
| `totalEntries as int` | connections tracked now |
| `maxEntries as int` | table capacity; new connections are dropped when it is full |

### `Connection`

One tracked connection.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `protocol as string` | protocol, e.g. "tcp" or "udp" |
| `srcAddress as string` | source address:port |
| `dstAddress as string` | destination address:port |
| `tcpState as string` | TCP state such as "established", "" for non-TCP |
| `timeout as string` | time until the entry expires |
| `connectionMark as string` | connection mark, "" when none |

## Firewall address lists

Guide: [Firewall address lists](addresslist.md).

| Function | Returns | Notes |
|---|---|---|
| `addressLists(c)` | `list of string` | distinct list names, first-seen order |
| `addressListEntries(c, listName)` | `list of AddressListEntry` | one list's entries; empty for an unknown list |
| `addToAddressList(c, listName, address, comment)` | `string` | IP, CIDR or DNS name; creates the list; idempotent per list and address |
| `addToAddressListTimed(c, listName, address, timeout, comment)` | `string` | entry that expires after `timeout` (`"30m"`, `"1d"`, `"1d12h"`, `"HH:MM:SS"`); not idempotent |
| `removeFromAddressList(c, listName, address)` |  | address exactly as listed; throws when absent |
| `clearAddressList(c, listName)` |  | removes static entries only; throws when there are none |
| `dropAddressList(c, listName, chain, comment)` | `string` | appends one filter rule dropping the list's sources in `chain`; not idempotent |

| Constant | Value |
|---|---|
| `ADDRESS_LIST_PATH` | `"/ip/firewall/address-list"` |

### `AddressListEntry`

One entry of a firewall address list.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `listName as string` | list the entry belongs to, e.g. "blocklist" |
| `address as string` | IP, CIDR network or DNS name; RouterOS resolves names and follows their changes |
| `timeout as string` | remaining lifetime, "" for a permanent entry |
| `dynamic as bool` | true when something else created it, e.g. a firewall rule with add-src-to-address-list |
| `disabled as bool` | true when the entry is switched off |
| `comment as string` | comment, "" when unset |

## IP addresses

Guide: [IP addresses](ip.md).

| Function | Returns | Notes |
|---|---|---|
| `ipAddresses(c)` | `list of IpAddress` | static and dynamic addresses |
| `addIpAddress(c, address, interfaceName)` | `string` | prefix required (`"192.168.88.1/24"`); the interface must exist |
| `removeIpAddress(c, address)` |  | matches the address string with its prefix exactly; throws when absent |

| Constant | Value |
|---|---|
| `IP_ADDRESS_PATH` | `"/ip/address"` |

### `IpAddress`

One IP address assigned to an interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `address as string` | address with prefix, e.g. "192.168.88.1/24" |
| `network as string` | network address the prefix implies, e.g. "192.168.88.0" |
| `interfaceName as string` | interface the address sits on |
| `dynamic as bool` | true when a DHCP client or PPP session assigned it; such addresses cannot be removed by hand |
| `disabled as bool` | true when the address is switched off |
| `comment as string` | comment, "" when unset |

## The ARP table

Guide: [The ARP table](arp.md).

| Function | Returns | Notes |
|---|---|---|
| `arpTable(c)` | `list of ArpEntry` | whole table, dynamic and static |
| `arpTableOn(c, interfaceName)` | `list of ArpEntry` | one interface's entries |
| `macForAddress(c, address)` | `string` | MAC for an IP; `""` on a miss |
| `addressesForMac(c, mac)` | `list of string` | IPs a MAC holds, case-insensitive; possibly empty |
| `addStaticArp(c, address, mac, interfaceName)` | `string` | pin a binding; MAC stored upper-case; refuses an existing static entry for the address on that interface |
| `removeArpEntry(c, address)` |  | static or dynamic; clears a stale binding; throws when absent |
| `flushArp(c, interfaceName)` | `int` | removes dynamic entries on the interface; returns the count |

| Constant | Value |
|---|---|
| `ARP_PATH` | `"/ip/arp"` |

### `ArpEntry`

One ARP entry: an IP-to-MAC binding on an interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `address as string` | IP address |
| `mac as string` | MAC address it resolves to, "" while unresolved |
| `interfaceName as string` | interface the binding lives on |
| `dynamic as bool` | true when learned, false for a static (pinned) entry |
| `complete as bool` | true when the MAC is known; false means the router asked and got no answer, typically an offline device |
| `published as bool` | true when the router answers ARP for this address itself (proxy ARP) |
| `disabled as bool` | true when the entry is switched off |
| `comment as string` | comment, "" when unset |

## DHCP

Guide: [DHCP](dhcp.md).

| Function | Returns | Notes |
|---|---|---|
| `dhcpServers(c)` | `list of DhcpServer` | All server instances. |
| `setupDhcp(c, name, interfaceName, network, gateway, rangeFrom, rangeTo, dns)` | `string` | Creates pool, server and network entry; gateway and range must lie inside the network, DNS entries must be IPs, the interface must exist. Not idempotent. Returns the server id. |
| `teardownDhcp(c, name, network)` | | Removes whichever of the three pieces exist; network matched by exact CIDR string. Throws when none exists. |
| `dhcpLeases(c)` | `list of DhcpLease` | Dynamic leases and static reservations. |
| `addStaticLease(c, address, mac, comment)` | `string` | Reserve an address for a MAC (any case, sent uppercased). Not idempotent. |
| `removeLeaseByMac(c, mac)` | | Throws on a malformed MAC or when no lease has it. |
| `dhcpClients(c)` | `list of DhcpClient` | All DHCP clients with lease state. |
| `setupWan(c, interfaceName)` | `string` | DHCP client on the WAN; adopts the ISP's route and DNS. Idempotent by interface: an existing client is returned untouched. |
| `setupWanWith(c, interfaceName, usePeerDns, addDefaultRoute)` | `string` | Same, choosing whether to adopt the ISP's DNS and default route. |
| `wanStatus(c, interfaceName)` | `DhcpClient` | Check `bound`. Throws when no DHCP client runs there. |
| `renewWan(c, interfaceName)` | | DHCP renew now. |
| `removeDhcpClient(c, interfaceName)` | | The uplink loses its address, route and DNS. |
| `enableDhcpClient(c, interfaceName)` | | By interface name. |
| `disableDhcpClient(c, interfaceName)` | | By interface name. |
| `dhcpRelays(c)` | `list of DhcpRelay` | All relays. |
| `addDhcpRelay(c, name, interfaceName, serverAddress)` | `string` | Forward DHCP to a central server (IP address). Idempotent by name. |
| `removeDhcpRelay(c, name)` | | Throws when no relay has that name. |

| Constant | Value |
|---|---|
| `IP_POOL_PATH` | `"/ip/pool"` |
| `DHCP_SERVER_PATH` | `"/ip/dhcp-server"` |
| `DHCP_NETWORK_PATH` | `"/ip/dhcp-server/network"` |
| `DHCP_LEASE_PATH` | `"/ip/dhcp-server/lease"` |
| `DHCP_CLIENT_PATH` | `"/ip/dhcp-client"` |
| `DHCP_RELAY_PATH` | `"/ip/dhcp-relay"` |

### `DhcpServer`

One DHCP server instance.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | server name |
| `interfaceName as string` | interface the server listens on |
| `addressPool as string` | pool it hands addresses out of |
| `leaseTime as string` | lease duration as RouterOS prints it (e.g. "30m") |
| `disabled as bool` | true when switched off |

### `DhcpLease`

One DHCP lease: an address handed out to, or reserved for, a device.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `address as string` | leased address |
| `mac as string` | device MAC address |
| `hostName as string` | host name the device sent, "" when none |
| `server as string` | DHCP server that owns the lease |
| `status as string` | lease state ("bound", "waiting", ...) |
| `dynamic as bool` | true for an automatic lease, false for a reservation |
| `expiresAfter as string` | time until the lease runs out, "" for static |
| `comment as string` | free-text comment, "" when unset |

### `DhcpClient`

One DHCP client: an interface that gets its address from another network, usually the ISP.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `interfaceName as string` | interface the client runs on |
| `status as string` | "bound" when an address was obtained; "searching..." while still asking |
| `bound as bool` | true when the status is "bound" |
| `address as string` | address obtained, with prefix |
| `gateway as string` | gateway obtained |
| `primaryDns as string` | first DNS server announced, "" when none |
| `secondaryDns as string` | second DNS server, "" when none |
| `expiresAfter as string` | time until the lease must be renewed |
| `usePeerDns as bool` | true when the router adopts the announced DNS servers |
| `addDefaultRoute as string` | default-route mode: "yes", "no" or "special-classless" |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `DhcpRelay`

One DHCP relay: forwards a local network's DHCP requests to a remote server.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | relay name |
| `interfaceName as string` | interface whose clients are relayed |
| `dhcpServer as string` | remote DHCP server address |
| `disabled as bool` | true when switched off |

## DNS

Guide: [DNS](dns.md).

| Function | Returns | Notes |
|---|---|---|
| `dnsSettings(c)` | `DnsSettings` | Upstreams, remote requests, cache fill. |
| `setDnsServers(c, servers)` | | Comma-separated IP addresses; spaces dropped; DNS names rejected. |
| `allowRemoteDnsRequests(c, allow)` | | Answers on every interface: close port 53 on the WAN. |
| `dnsStaticEntries(c)` | `list of DnsEntry` | Local names. |
| `addDnsEntry(c, name, address)` | `string` | Not idempotent. Returns the id. |
| `removeDnsEntry(c, name)` | | Throws when no entry has that name. |
| `dnsCache(c)` | `list of DnsCacheEntry` | Whole cache; large on a busy router. |
| `dnsCacheFor(c, name)` | `list of DnsCacheEntry` | Case-insensitive; empty when not resolved recently. |
| `resolvedAddresses(c, name)` | `list of string` | Data of the A and AAAA records only; CNAMEs not followed. |
| `flushDnsCache(c)` | | Static entries survive. |
| `dnsAdlists(c)` | `list of DnsAdlist` | RouterOS 7.15+. |
| `addAdlist(c, url)` | `string` | Hosts-format list; URL must start with "http". Idempotent by URL. RouterOS 7.15+; costs RAM. |
| `removeAdlist(c, url)` | | Throws when no adlist has that URL. |

| Constant | Value |
|---|---|
| `DNS_PATH` | `"/ip/dns"` |
| `DNS_STATIC_PATH` | `"/ip/dns/static"` |
| `DNS_ADLIST_PATH` | `"/ip/dns/adlist"` |
| `DNS_CACHE_PATH` | `"/ip/dns/cache"` |

### `DnsCacheEntry`

One DNS cache record.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | DNS name the record answers for |
| `kind as string` | record type ("A", "AAAA", "CNAME", ...) |
| `data as string` | answer: an address for A/AAAA, a name for CNAME |
| `ttl as string` | time until the record expires from the cache |
| `isStatic as bool` | true for a static entry, which never expires |

### `DnsSettings`

The router's DNS resolver configuration.

| Field | Meaning |
|---|---|
| `servers as string` | upstream servers, comma-separated |
| `allowRemoteRequests as bool` | true when the router answers its clients' queries |
| `cacheSize as string` | cache size as RouterOS prints it (e.g. "2048KiB") |
| `cacheUsed as string` | cache usage as RouterOS prints it |

### `DnsEntry`

One static DNS entry: a local name with a fixed address.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | DNS name (e.g. "nas.lan") |
| `address as string` | address it resolves to |
| `ttl as string` | time-to-live as RouterOS prints it (e.g. "1d") |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `DnsAdlist`

One DNS adlist: a hosts-format blocklist the resolver applies (v7.15+).

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `url as string` | blocklist URL, "" for a local-file list |
| `matchCount as string` | number of names it blocks, as RouterOS prints it |
| `disabled as bool` | true when switched off |

## IPv6

Guide: [IPv6](ipv6.md).

| Function | Returns | Notes |
|---|---|---|
| `ipv6Settings(c)` | `Ipv6Settings` | The global stack settings. |
| `disableIpv6(c)` | | Full effect after a reboot. |
| `enableIpv6(c)` | | Full effect after a reboot. Add `/ipv6/firewall` rules: the v4 firewall does not filter IPv6. |
| `setIpv6Forwarding(c, enabled)` | | Route IPv6 between interfaces. |
| `setIpv6AcceptRouterAdvertisements(c, enabled)` | | Router configures itself from received RAs. |
| `ipv6Addresses(c)` | `list of Ipv6Address` | Static and dynamic; check `dynamic`. |
| `ipv6AddressesOn(c, interfaceName)` | `list of Ipv6Address` | Filtered by exact interface name. |
| `addIpv6Address(c, cidr, interfaceName)` | `string` | Advertised, no EUI-64. A LAN wants a /64. IPv4 CIDR rejected. |
| `addIpv6AddressWith(c, cidr, interfaceName, advertise, eui64)` | `string` | Choose `advertise` (SLAAC on the LAN) and `eui64` (host part from the MAC). |
| `removeIpv6Address(c, cidr)` | | Matched as text, as `ipv6Addresses` reports it; refuses dynamic addresses. |
| `ipv6Nd(c)` | `list of Ipv6Nd` | Neighbor-discovery (RA) entries. |
| `advertiseIpv6On(c, interfaceName)` | `string` | Enables or creates the interface's RA entry. Idempotent. |
| `stopAdvertisingIpv6On(c, interfaceName)` | `string` | Disables the entry; clients keep addresses until the lifetime runs out. |
| `setIpv6NdFlags(c, interfaceName, managed, otherConfig)` | `string` | M: addresses from DHCPv6. O: DNS from DHCPv6. Both false: pure SLAAC. |

| Constant | Value |
|---|---|
| `IPV6_SETTINGS_PATH` | `"/ipv6/settings"` |
| `IPV6_ADDRESS_PATH` | `"/ipv6/address"` |
| `IPV6_ND_PATH` | `"/ipv6/nd"` |

### `Ipv6Settings`

The router's global IPv6 settings.

| Field | Meaning |
|---|---|
| `disabled as bool` | true when the IPv6 stack is switched off |
| `forward as bool` | true when the router routes IPv6 between interfaces |
| `acceptRouterAdvertisements as bool` | true when the router configures itself from RAs it receives |
| `acceptRedirects as bool` | true when ICMPv6 redirects are honored |
| `maxNeighborEntries as int` | neighbor-cache size limit, 0 when absent |

### `Ipv6Address`

One IPv6 address on an interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `address as string` | address in CIDR form |
| `interfaceName as string` | interface it sits on |
| `advertise as bool` | true when the prefix is announced in RAs |
| `eui64 as bool` | true when the host part is derived from the MAC |
| `linkLocal as bool` | true for a fe80::/10 address |
| `dynamic as bool` | true when RouterOS created it (SLAAC, DHCPv6-PD) |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `Ipv6Nd`

One neighbor-discovery entry: how the router advertises itself on an interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `interfaceName as string` | interface, "all" for the default entry |
| `raInterval as string` | advertisement interval as RouterOS prints it |
| `raLifetime as string` | how long clients keep this router as default gateway |
| `managed as bool` | M flag: clients get addresses from DHCPv6 |
| `otherConfig as bool` | O flag: clients get DNS and other options from DHCPv6 |
| `advertiseDns as bool` | true when RAs carry the router's DNS servers |
| `disabled as bool` | true when switched off |

## Neighbor discovery

Guide: [Neighbor discovery](neighbor.md).

| Function | Returns | Notes |
|---|---|---|
| `neighbors(c)` | `list of Neighbor` | Heard via LLDP, CDP, MNDP; directly connected segments only. |
| `neighborsOn(c, interfaceName)` | `list of Neighbor` | Same, filtered by exact interface name. |

| Constant | Value |
|---|---|
| `NEIGHBOR_PATH` | `"/ip/neighbor"` |

### `Neighbor`

One discovered neighbor on a directly-connected segment.

| Field | Meaning |
|---|---|
| `interfaceName as string` | the interface it was seen on |
| `address as string` | its IP address, "" when only layer 2 |
| `mac as string` | its MAC address |
| `identity as string` | its system identity (host name) |
| `platform as string` | the vendor platform (e.g. "MikroTik", "Cisco") |
| `board as string` | the hardware model as reported |
| `version as string` | the software version as reported |

## Hotspot

Guide: [Hotspot](hotspot.md).

| Function | Returns | Notes |
|---|---|---|
| `hotspotServers(c)` | `list of HotspotServer` | All portals. |
| `setupHotspot(c, name, interfaceName, network, gateway, rangeFrom, rangeTo)` | `string` | DHCP stack (DNS = gateway), profile and server on a dedicated guest interface. Returns the existing id when a server of that name exists. |
| `teardownHotspot(c, name, network)` | | Removes server, profile and DHCP stack; users, bindings and walled garden stay. Throws when nothing exists. |
| `hotspotUsers(c)` | `list of HotspotUser` | All portal logins. |
| `addHotspotUser(c, name, password, comment)` | `string` | Throws when the login exists or the password is empty. |
| `addHotspotVoucher(c, name, password, uptimeLimit, comment)` | `string` | Connect-time limit: "4h", "1d", "1d12h" or "HH:MM:SS". Throws when the login exists. |
| `removeHotspotUser(c, name)` | | Throws when no such login exists. |
| `hotspotActive(c)` | `list of HotspotSession` | Logged-in guests with byte counters. |
| `kickHotspotUser(c, user)` | | Throws when the login has no session. |
| `bypassHotspotMac(c, mac, comment)` | `string` | Device skips the portal. Idempotent by MAC. |
| `removeHotspotBypass(c, mac)` | | Throws when no bypass exists for the MAC. |
| `allowBeforeLogin(c, dstHost, comment)` | `string` | Walled-garden host; wildcards like "*.example.org" work. Idempotent by host. |
| `removeWalledGardenEntry(c, dstHost)` | | Throws when no entry exists for the host. |

| Constant | Value |
|---|---|
| `HOTSPOT_PATH` | `"/ip/hotspot"` |
| `HOTSPOT_PROFILE_PATH` | `"/ip/hotspot/profile"` |
| `HOTSPOT_USER_PATH` | `"/ip/hotspot/user"` |
| `HOTSPOT_ACTIVE_PATH` | `"/ip/hotspot/active"` |
| `HOTSPOT_BINDING_PATH` | `"/ip/hotspot/ip-binding"` |
| `WALLED_GARDEN_PATH` | `"/ip/hotspot/walled-garden"` |

### `HotspotServer`

One hotspot server: a captive portal guarding an interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | server name |
| `interfaceName as string` | guarded interface, usually the guest bridge |
| `addressPool as string` | pool guests get addresses from |
| `profile as string` | server profile: portal address, login method |
| `disabled as bool` | true when switched off |

### `HotspotUser`

One hotspot user: a portal login.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | login name |
| `profile as string` | user profile ("default" unless customized) |
| `limitUptime as string` | total connect time allowed, "" for unlimited |
| `uptime as string` | time used so far |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `HotspotSession`

One active hotspot session.

| Field | Meaning |
|---|---|
| `user as string` | login used |
| `address as string` | guest IP address |
| `mac as string` | guest MAC address |
| `uptime as string` | session duration so far |
| `idleTime as string` | time since the guest last sent traffic |
| `bytesIn as int` | bytes received from the guest |
| `bytesOut as int` | bytes sent to the guest |

## PPPoE

Guide: [PPPoE](ppp.md).

| Function | Returns | Notes |
|---|---|---|
| `vpnUsers(c)` | `list of PppUser` | The PPP user database shared by L2TP, SSTP, OpenVPN, PPTP and PPPoE servers. See vpn.md. |
| `addVpnUser(c, name, password, service, comment)` | `string` | Service "any", "l2tp", "sstp", "ovpn", "pptp" or "pppoe". Throws when the login exists. |
| `removeVpnUser(c, name)` | | Throws when no such login exists. |
| `enableVpnUser(c, name)` | | Throws when no such login exists. |
| `disableVpnUser(c, name)` | | Parks the login without deleting it. |
| `pppProfiles(c)` | `list of PppProfile` | Address and DNS templates for sessions. |
| `pppActive(c)` | `list of PppSession` | Sessions on every PPP server. |
| `kickPppUser(c, name)` | | Throws when the login has no session. |
| `pppoeClients(c)` | `list of PppoeClient` | All PPPoE clients with session state. |
| `setupPppoe(c, name, interfaceName, user, password)` | `string` | Adopts the ISP's route and DNS. Idempotent by name. Masquerade `name`, not the port. |
| `pppoeStatus(c, name)` | `PppoeClient` | Check `running`. Throws when no client has that name. |
| `setPppoeCredentials(c, name, user, password)` | | The session reconnects. |
| `removePppoeClient(c, name)` | | The dial-in uplink goes away. |
| `enablePppoeClient(c, name)` | | Starts dialing at once. |
| `disablePppoeClient(c, name)` | | The session disconnects. |
| `pppoeServers(c)` | `list of PppoeServer` | All PPPoE server services. |
| `addPppoeServer(c, serviceName, interfaceName)` | `string` | Clients authenticate against the PPP user database. Sets one-session-per-host. Idempotent by service name and interface. |
| `removePppoeServer(c, serviceName)` | | Throws when no such service exists. |

| Constant | Value |
|---|---|
| `PPP_SECRET_PATH` | `"/ppp/secret"` |
| `PPP_PROFILE_PATH` | `"/ppp/profile"` |
| `PPP_ACTIVE_PATH` | `"/ppp/active"` |
| `PPPOE_CLIENT_PATH` | `"/interface/pppoe-client"` |
| `PPPOE_SERVER_PATH` | `"/interface/pppoe-server/server"` |

### `PppUser`

One PPP secret: a login shared by the PPP-based servers.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | login name |
| `service as string` | servers that accept it: "any", "l2tp", "sstp", "ovpn", "pptp" or "pppoe" |
| `profile as string` | PPP profile applied ("default" unless set) |
| `localAddress as string` | router's tunnel address, "" when the profile decides |
| `remoteAddress as string` | client's tunnel address, "" when the profile decides |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `PppProfile`

One PPP profile: the addresses, DNS and limits applied to a login.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | profile name |
| `localAddress as string` | router's tunnel address, or a pool name |
| `remoteAddress as string` | client address, or a pool name |
| `dnsServer as string` | DNS handed to clients, "" when unset |
| `disabled as bool` | true when switched off |

### `PppSession`

One active PPP session: a connected VPN or dial-in client.

| Field | Meaning |
|---|---|
| `name as string` | login used |
| `service as string` | server type ("l2tp", "sstp", "ovpn", "pppoe", ...) |
| `address as string` | client tunnel address |
| `uptime as string` | session duration so far |
| `callerId as string` | where the client connected from (address or MAC) |

### `PppoeClient`

One PPPoE client: a dial-in uplink over user name and password.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | PPPoE interface name (e.g. "pppoewan") |
| `interfaceName as string` | physical interface the session dials over |
| `user as string` | ISP dial-in user name |
| `usePeerDns as bool` | true when the router adopts the ISP's DNS servers |
| `addDefaultRoute as bool` | true when the session installs the default route |
| `running as bool` | true when the session is up |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `PppoeServer`

One PPPoE server service: the router accepting PPPoE dial-ins on an interface.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `serviceName as string` | PPPoE service name clients may ask for |
| `interfaceName as string` | interface it serves on |
| `defaultProfile as string` | PPP profile applied to sessions |
| `disabled as bool` | true when switched off |

## RADIUS

Guide: [RADIUS](radius.md).

| Function | Returns | Notes |
|---|---|---|
| `radiusServers(c)` | `list of RadiusServer` | All configured servers. |
| `addRadiusServer(c, address, secret, services, comment)` | `string` | IP address only; non-empty secret; services from login, ppp, hotspot, wireless, dhcp, ipsec, dot1x. Idempotent by address: an existing entry is returned unchanged. |
| `removeRadiusServer(c, address)` | | Throws when no server has that address. |

| Constant | Value |
|---|---|
| `RADIUS_PATH` | `"/radius"` |

### `RadiusServer`

One RADIUS server the router authenticates against.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `address as string` | server address |
| `services as string` | subsystems that use it, comma-separated |
| `timeout as string` | request timeout as RouterOS prints it |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

## UPnP

Guide: [UPnP](upnp.md).

| Function | Returns | Notes |
|---|---|---|
| `upnpStatus(c)` | `UpnpSettings` | Service on or off. |
| `upnpInterfaces(c)` | `list of UpnpInterface` | Interfaces that have a UPnP role. |
| `enableUpnp(c)` | - | Any device on an `internal` interface can then open forwards to itself; needs one `internal` and one `external` interface. Not for guest networks. |
| `disableUpnp(c)` | - | Turn UPnP off. |
| `setUpnpInterface(c, interfaceName, role)` | `string` | Role `"internal"` (LAN) or `"external"` (WAN); other roles and unknown interfaces are rejected. Idempotent: an existing entry gets the new role. |
| `removeUpnpInterface(c, interfaceName)` | - | Throws when the interface has no role. |

| Constant | Value |
|---|---|
| `UPNP_PATH` | `"/ip/upnp"` |
| `UPNP_INTERFACES_PATH` | `"/ip/upnp/interfaces"` |

### `UpnpSettings`

The UPnP service settings.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when UPnP is running |

### `UpnpInterface`

One interface's UPnP role.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `interfaceName as string` | the interface |
| `role as string` | "internal" (LAN side) or "external" (WAN side) |
| `disabled as bool` | true when switched off |

## Management services

Guide: [Management services](services.md).

| Function | Returns | Notes |
|---|---|---|
| `services(c)` | `list of Service` | the fixed list: api, api-ssl, ftp, ssh, telnet, winbox, www, www-ssl |
| `serviceByName(c, name)` | `Service` | unknown name rejected with the valid names |
| `enableService(c, name)` |  | unknown name rejected |
| `disableService(c, name)` |  | disabling the API service this session uses disconnects it |
| `setServicePort(c, name, port)` |  | port 1-65535; a port another service uses is refused, naming it |
| `restrictService(c, name, addresses)` |  | IPs and/or CIDRs; "" lifts; applies to new connections |
| `disableInsecureServices(c)` | `int` | switches off telnet and ftp; returns how many were on |

| Constant | Value |
|---|---|
| `SERVICE_PATH` | `"/ip/service"` |

### `Service`

One management service: a way to log into the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | service name ("api", "ssh", "winbox", ...) |
| `port as int` | TCP port it listens on |
| `address as string` | networks allowed to connect, "" for anywhere |
| `certificate as string` | TLS certificate name (ssl services), "" otherwise |
| `invalid as bool` | true when misconfigured (e.g. ssl without a certificate); the service is not listening |
| `disabled as bool` | true when the service is switched off |

## SNMP

Guide: [SNMP](snmp.md).

| Function | Returns | Notes |
|---|---|---|
| `snmpSettings(c)` | `SnmpSettings` | Agent state, contact and location. |
| `snmpCommunities(c)` | `list of SnmpCommunity` | All communities, including a default `public`. |
| `enableSnmp(c, community, addresses)` | `string` | Creates or updates a read-only community (write always off) and switches the agent on. `addresses`: comma-separated IPs or CIDRs, `""` = any source. Idempotent. v2c is cleartext: treat the community as a password. |
| `setSnmpInfo(c, contact, location)` | - | Strings shown by monitoring systems. |
| `disableSnmp(c)` | - | Agent off. |

| Constant | Value |
|---|---|
| `SNMP_PATH` | `"/snmp"` |
| `SNMP_COMMUNITY_PATH` | `"/snmp/community"` |

### `SnmpSettings`

The SNMP agent settings.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when the agent answers queries |
| `contact as string` | contact string shown by monitoring systems |
| `location as string` | location string shown by monitoring systems |

### `SnmpCommunity`

One SNMP community: a shared string that grants access.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | community string; works as a password |
| `addresses as string` | networks allowed to query, "" for anywhere |
| `readAccess as bool` | true when reading is allowed |
| `writeAccess as bool` | true when writing is allowed |
| `disabled as bool` | true when switched off |

## Static routes

Guide: [Static routes](routing.md).

| Function | Returns | Notes |
|---|---|---|
| `routes(c)` | `list of Route` | Static, connected and dynamic routes; filter on `dynamic`. |
| `addRoute(c, dstAddress, gateway, comment)` | `string` | Destination must be CIDR. Gateway: IP address, or the name of an interface on the router. |
| `addRouteWithDistance(c, dstAddress, gateway, distance, comment)` | `string` | Distance 1-255, lower wins (static default 1); a higher-distance twin is a backup. |
| `addDefaultRoute(c, gateway, comment)` | `string` | Route to `DEFAULT_ROUTE`. |
| `removeRoute(c, dstAddress)` | - | First static route whose destination matches exactly; dynamic routes are skipped. |
| `enableRoute(c, dstAddress)` | - | First static route to the destination. |
| `disableRoute(c, dstAddress)` | - | First static route to the destination; kept but unused. |
| `routingRules(c)` | `list of RoutingRule` | Policy rules in evaluation order (RouterOS v7). |
| `useRoutingTable(c, srcAddress, table, comment)` | `string` | Rule with action `lookup`: unmatched destinations fall back to main. Source: IP or CIDR. Creates the table if missing (it still needs its own default route). Idempotent by source and table. |
| `useRoutingTableOnly(c, srcAddress, table, comment)` | `string` | As `useRoutingTable`, action `lookup-only-in-table`: no fallback. |
| `removeRoutingRule(c, srcAddress, table)` | - | Throws when no rule matches source and table. |

| Constant | Value |
|---|---|
| `ROUTE_PATH` | `"/ip/route"` |
| `DEFAULT_ROUTE` | `"0.0.0.0/0"` |
| `ROUTING_RULE_PATH` | `"/routing/rule"` |
| `ROUTING_TABLE_PATH` | `"/routing/table"` |

### `RoutingRule`

One policy routing rule: which traffic looks routes up in which table.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `srcAddress as string` | matched source, "" for any |
| `dstAddress as string` | matched destination, "" for any |
| `interfaceName as string` | matched incoming interface, "" for any |
| `action as string` | e.g. "lookup" (falls back to main) or "lookup-only-in-table" (no fallback) |
| `table as string` | the routing table consulted |
| `disabled as bool` | true when switched off |
| `comment as string` | free-text comment, "" when unset |

### `Route`

One route: the next hop for a destination network.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `dstAddress as string` | destination network in CIDR; "0.0.0.0/0" is the default route |
| `gateway as string` | next hop, an IP address or an interface name |
| `distance as string` | preference, lower wins (RouterOS default "1") |
| `routingTable as string` | routing table holding the route, normally "main" |
| `active as bool` | true when the route is currently usable |
| `dynamic as bool` | true when a protocol or service created it; such routes cannot be removed by hand |
| `disabled as bool` | true when the route is switched off |
| `comment as string` | free-text comment, "" when unset |

## VRRP

Guide: [VRRP](vrrp.md).

| Function | Returns | Notes |
|---|---|---|
| `vrrpInterfaces(c)` | `list of VrrpInterface` | All instances with master/backup state. |
| `vrrpByName(c, name)` | `VrrpInterface` | Check `.master`. |
| `setupVrrp(c, name, interfaceName, vrid, priority, virtualAddress)` | `string` | Instance plus the shared address (CIDR, `/32` by convention). Run on each peer with the same vrid and address and different priorities. Not idempotent. |
| `addVrrp(c, name, interfaceName, vrid, priority)` | `string` | Instance only. vrid 1-255, priority 1-254 (255 is reserved by RFC 5798). Rejects a taken name and a vrid already used on that interface. |
| `setVrrpPriority(c, name, priority)` | - | Priority 1-254. Lower it to hand the master role away before maintenance. |
| `removeVrrp(c, name)` | - | Also removes the static addresses on the instance. |
| `enableVrrp(c, name)` | - | Join the group. |
| `disableVrrp(c, name)` | - | Leave the group; the peer takes over. |

| Constant | Value |
|---|---|
| `VRRP_PATH` | `"/interface/vrrp"` |

### `VrrpInterface`

One VRRP instance: this router's share of a redundant gateway.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | VRRP interface name (e.g. "vrrplan") |
| `interfaceName as string` | underlying interface (the shared network) |
| `vrid as int` | virtual router id, 1-255, the same on all peers |
| `priority as int` | priority, 1-254; the highest becomes master |
| `interval as string` | advertisement interval as reported |
| `version as int` | VRRP protocol version (2 or 3) |
| `preemption as bool` | true when a returning higher-priority peer takes over |
| `running as bool` | true when the instance is active |
| `backup as bool` | true while standing by |
| `master as bool` | computed as running and not backup: this router answers for the address now |
| `disabled as bool` | true when the instance is switched off |
| `comment as string` | free-text comment, "" when unset |

## WireGuard VPN tunnels

Guide: [WireGuard VPN tunnels](wireguard.md).

| Function | Returns | Notes |
|---|---|---|
| `wireguardInterfaces(c)` | `list of WireguardInterface` | RouterOS v7. Any read error gives an empty list (v6, but also a dead connection). |
| `addWireguard(c, name, listenPort)` | `string` | Router generates the keypair. Idempotent by name: an existing interface is returned unchanged. |
| `wireguardPublicKey(c, name)` | `string` | Base64 public key for the other side. The private key is never read. |
| `setupWireguardServer(c, name, listenPort, address)` | `string` | Interface, VPN address (CIDR) and an input accept rule for the UDP port, comment `"wireguard: <name>"`. Idempotent piece by piece. |
| `wireguardPeers(c)` | `list of WireguardPeer` | Peers of all interfaces. A handshake within about 2 minutes means alive. Any read error gives an empty list. |
| `addWireguardPeer(c, interfaceName, publicKey, allowedAddress, comment)` | `string` | Peer that dials in. Key: 44 base64 characters ending in `=`. Every allowed-address entry needs a prefix (`/32` for one device). |
| `connectWireguard(c, interfaceName, publicKey, endpointHost, endpointPort, allowedAddress, comment)` | `string` | Peer the router dials, with 25 s persistent keepalive. Host: IP or DNS name; port 1-65535. |
| `removeWireguardPeerByComment(c, comment)` | - | Throws when no peer carries the comment. |
| `removeWireguard(c, name)` | - | Removes the first IP address on the interface, the `"wireguard: <name>"` firewall rule, and the interface with its peers. |
| `enableWireguard(c, name)` | - | All tunnels of the interface up. |
| `disableWireguard(c, name)` | - | All tunnels of the interface down. |

| Constant | Value |
|---|---|
| `WIREGUARD_PATH` | `"/interface/wireguard"` |
| `WIREGUARD_PEER_PATH` | `"/interface/wireguard/peers"` |

### `WireguardInterface`

One WireGuard interface: the local end of one or more tunnels.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | interface name (e.g. "wgvpn") |
| `publicKey as string` | router's public key, to hand to peers |
| `listenPort as int` | UDP port the router listens on |
| `mtu as string` | MTU as reported |
| `running as bool` | true when the interface is up |
| `disabled as bool` | true when the interface is switched off |
| `comment as string` | free-text comment, "" when unset |

### `WireguardPeer`

One WireGuard peer: a remote party allowed through a tunnel.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `interfaceName as string` | WireGuard interface the peer belongs to |
| `publicKey as string` | the peer's public key |
| `endpointAddress as string` | address the router dials, "" when the peer dials in |
| `endpointPort as string` | peer's UDP port, "" or "0" when it dials in |
| `allowedAddress as string` | comma-separated CIDRs accepted from and routed to this peer |
| `keepalive as string` | persistent keepalive as reported, "" when off |
| `lastHandshake as string` | time since the last handshake |
| `rx as string` | bytes received from the peer |
| `tx as string` | bytes sent to the peer |
| `disabled as bool` | true when the peer is switched off |
| `comment as string` | free-text comment, the handle for removal |

## EoIP tunnels

Guide: [EoIP tunnels](eoip.md).

| Function | Returns | Notes |
|---|---|---|
| `eoipTunnels(c)` | `list of EoipTunnel` | All EoIP tunnels. |
| `eoipTunnelByName(c, name)` | `EoipTunnel` | Throws when absent. |
| `addEoipTunnel(c, name, remoteAddress, tunnelId)` | `string` | Unencrypted layer-2 tunnel. Remote must be an IP address; tunnel id 0-65535, equal on both ends. Rejects a taken name and an existing tunnel with the same remote and id. |
| `addSecureEoipTunnel(c, name, remoteAddress, tunnelId, ipsecSecret)` | `string` | Same, wrapped in RouterOS coupled IPsec; non-empty secret, same on both ends, never read back. |
| `removeEoipTunnel(c, name)` | - | Detach bridge ports first. |
| `enableEoipTunnel(c, name)` | - | Tunnel up. |
| `disableEoipTunnel(c, name)` | - | Tunnel down; the layer-2 link drops. |

| Constant | Value |
|---|---|
| `EOIP_PATH` | `"/interface/eoip"` |

### `EoipTunnel`

One EoIP tunnel: an ethernet link carried over any IP path.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | tunnel interface name (e.g. "eoipbranch") |
| `remoteAddress as string` | other MikroTik's IP address |
| `localAddress as string` | source address, "" for automatic |
| `tunnelId as int` | tunnel id, the same on both ends |
| `mac as string` | tunnel MAC address |
| `mtu as string` | MTU as reported |
| `keepalive as string` | keepalive setting as reported |
| `running as bool` | true when the tunnel is up |
| `disabled as bool` | true when the tunnel is switched off |
| `comment as string` | free-text comment, "" when unset |

## GRE tunnels

Guide: [GRE tunnels](gre.md).

| Function | Returns | Notes |
|---|---|---|
| `greTunnels(c)` | `list of GreTunnel` | All GRE tunnels. |
| `greTunnelByName(c, name)` | `GreTunnel` | Throws when no tunnel has that name. |
| `addGreTunnel(c, name, remoteAddress)` | `string` | Unencrypted. Remote must be an IP; refuses a taken name or a second tunnel to the same remote (names the owner). Mirror it on the far end. |
| `addSecureGreTunnel(c, name, remoteAddress, ipsecSecret)` | `string` | Same, with RouterOS coupled IPsec (`ipsec-secret`, write-only, same on both ends). Refuses an empty secret. |
| `removeGreTunnel(c, name)` |  | Addresses on it go with it; routes through it become unreachable. |
| `enableGreTunnel(c, name)` |  | Throws when no tunnel has that name (as do remove/disable). |
| `disableGreTunnel(c, name)` |  | Routes through it lose their link. |

| Constant | Value |
|---|---|
| `GRE_PATH` | `"/interface/gre"` |

### `GreTunnel`

One GRE tunnel: a routed (layer-3) point-to-point link over IP.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | tunnel interface name (e.g. "grebranch") |
| `remoteAddress as string` | the other router's IP address |
| `localAddress as string` | our source address, "" for automatic |
| `mtu as string` | MTU as reported |
| `keepalive as string` | keepalive setting as reported |
| `running as bool` | true when the tunnel is up |
| `disabled as bool` | true when the tunnel is switched off |
| `comment as string` | comment, "" when unset |

## IPsec

Guide: [IPsec](ipsec.md).

| Function | Returns | Notes |
|---|---|---|
| `ipsecPeers(c)` | `list of IpsecPeer` | Configured peers. |
| `ipsecPolicies(c)` | `list of IpsecPolicy` | Per-policy `active` flag (live SA). |
| `ipsecActive(c)` | `list of IpsecActivePeer` | Live negotiations; check `established`. |
| `setupIpsecTunnel(c, name, peerAddress, psk, localSubnet, remoteSubnet)` | `string` | IKEv2 peer, PSK identity, tunnel policy, srcnat bypass above masquerade, input accepts for udp 500/4500 and ESP. Far end mirrors it (same PSK, subnets swapped). Existing peer name: returns its id, changes nothing. |
| `teardownIpsecTunnel(c, name)` |  | Removes all of the above; throws when none of it exists. |
| `setupIkev2Server(c, name, certificate, poolRange, dns)` | `string` | Road-warrior server: pool, mode-config, passive IKEv2 peer, `eap-radius` identity with the router certificate, input accepts. Users come from RADIUS. Throws on an existing peer name or missing certificate. See [vpn.md](vpn.md). |

| Constant | Value |
|---|---|
| `IPSEC_PEER_PATH` | `"/ip/ipsec/peer"` |
| `IPSEC_IDENTITY_PATH` | `"/ip/ipsec/identity"` |
| `IPSEC_POLICY_PATH` | `"/ip/ipsec/policy"` |
| `IPSEC_ACTIVE_PATH` | `"/ip/ipsec/active-peers"` |
| `IPSEC_MODE_CONFIG_PATH` | `"/ip/ipsec/mode-config"` |

### `IpsecPeer`

One configured IPsec peer (the remote router).

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | peer name, the handle identity and policy refer to |
| `address as string` | remote router's address or DNS name |
| `exchangeMode as string` | "ike2" for peers this deck creates |
| `disabled as bool` | true when switched off |

### `IpsecPolicy`

One IPsec policy: which traffic is encrypted to which peer.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `peer as string` | peer name |
| `srcAddress as string` | local subnet |
| `dstAddress as string` | remote subnet |
| `tunnel as bool` | true for tunnel mode (site-to-site) |
| `active as bool` | true when the policy has a live SA |
| `disabled as bool` | true when switched off |

### `IpsecActivePeer`

One live IPsec negotiation with a remote router.

| Field | Meaning |
|---|---|
| `remoteAddress as string` | the other end |
| `state as string` | negotiation state as reported |
| `established as bool` | computed: state equals "established" |
| `uptime as string` | time since the tunnel came up |
| `side as string` | "initiator" or "responder" |

## L2TP

Guide: [Remote-access VPN](vpn.md).

| Function | Returns | Notes |
|---|---|---|
| `l2tpServerStatus(c)` | `L2tpServer` | `useIpsec` is false for `use-ipsec=no` or unset. |
| `enableL2tpServer(c, ipsecSecret)` |  | Requires IPsec with this PSK (refuses an empty one); opens udp 1701, 500, 4500 and ESP. Idempotent. |
| `disableL2tpServer(c)` |  | Also removes its firewall accepts. |
| `l2tpClients(c)` | `list of L2tpClient` | Dial-out tunnels. |
| `addL2tpClient(c, name, serverAddress, user, password)` | `string` | Throws on an empty or spaced name or user, empty password, or empty or spaced server. Existing name: returns its id. |
| `removeL2tpClient(c, name)` |  | Throws when no client has that name. |

| Constant | Value |
|---|---|
| `L2TP_SERVER_PATH` | `"/interface/l2tp-server/server"` |
| `L2TP_CLIENT_PATH` | `"/interface/l2tp-client"` |

### `L2tpServer`

The L2TP server settings.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when the server accepts connections |
| `useIpsec as bool` | true when `use-ipsec` is anything but "no" (or unset) |
| `defaultProfile as string` | PPP profile applied to logins |

### `L2tpClient`

One L2TP client: this router dialing out to an L2TP server.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | client interface name |
| `connectTo as string` | server address |
| `user as string` | login on the server |
| `running as bool` | true when the tunnel is up |
| `disabled as bool` | true when switched off |
| `comment as string` | comment, "" when unset |

## SSTP

Guide: [Remote-access VPN](vpn.md).

| Function | Returns | Notes |
|---|---|---|
| `sstpServerStatus(c)` | `SstpServer` | Port, certificate, profile. |
| `enableSstpServer(c, certificate, port)` |  | TLS over TCP; 443 looks like HTTPS. Certificate must exist. Opens the port. Idempotent. |
| `disableSstpServer(c)` |  | Also removes its firewall accept. |
| `sstpClients(c)` | `list of SstpClient` | Dial-out tunnels. |
| `addSstpClient(c, name, serverAddress, user, password)` | `string` | Throws on an empty or spaced name or user, empty password, or empty or spaced server. Existing name: returns its id. Sets `verify-server-certificate=no`. |
| `removeSstpClient(c, name)` |  | Throws when no client has that name. |

| Constant | Value |
|---|---|
| `SSTP_SERVER_PATH` | `"/interface/sstp-server/server"` |
| `SSTP_CLIENT_PATH` | `"/interface/sstp-client"` |

### `SstpServer`

The SSTP server settings.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when the server accepts connections |
| `port as int` | TCP port it listens on (443 by default) |
| `certificate as string` | TLS certificate it serves |
| `defaultProfile as string` | PPP profile applied to logins |

### `SstpClient`

One SSTP client: this router dialing out to an SSTP server.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | client interface name |
| `connectTo as string` | server address |
| `user as string` | login on the server |
| `running as bool` | true when the tunnel is up |
| `disabled as bool` | true when switched off |
| `comment as string` | comment, "" when unset |

## OpenVPN

Guide: [Remote-access VPN](vpn.md).

| Function | Returns | Notes |
|---|---|---|
| `ovpnServerStatus(c)` | `OvpnServer` | Port, mode, certificate, profile. |
| `enableOvpnServer(c, certificate, port)` |  | Routed (`mode=ip`), TCP; 1194 is the usual port. Certificate must exist. Opens the port. Idempotent. |
| `disableOvpnServer(c)` |  | Also removes its firewall accept. |
| `ovpnClients(c)` | `list of OvpnClient` | Dial-out tunnels. |
| `addOvpnClient(c, name, serverAddress, user, password)` | `string` | Throws on an empty or spaced name or user, empty password, or empty or spaced server. Existing name: returns its id. |
| `removeOvpnClient(c, name)` |  | Throws when no client has that name. |

| Constant | Value |
|---|---|
| `OVPN_SERVER_PATH` | `"/interface/ovpn-server/server"` |
| `OVPN_CLIENT_PATH` | `"/interface/ovpn-client"` |

### `OvpnServer`

The OpenVPN server settings.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when the server accepts connections |
| `port as int` | TCP port it listens on (1194 by default) |
| `mode as string` | "ip" (routed, tun) or "ethernet" (bridged, tap) |
| `certificate as string` | TLS certificate it serves |
| `defaultProfile as string` | PPP profile applied to logins |

### `OvpnClient`

One OpenVPN client: this router dialing out to an OpenVPN server.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | client interface name |
| `connectTo as string` | server address |
| `user as string` | login on the server |
| `running as bool` | true when the tunnel is up |
| `disabled as bool` | true when switched off |
| `comment as string` | comment, "" when unset |

## Simple queues

Guide: [Simple queues](queues.md).

| Function | Returns | Notes |
|---|---|---|
| `simpleQueues(c)` | `list of SimpleQueue` | `max-limit` already split into `maxUpload` / `maxDownload`. |
| `limitBandwidth(c, name, target, upload, download)` | `string` | Target: address, CIDR, interface (checked on the router) or a comma-separated mix. Upload = from the target. Rates `"10M"`, `"512k"`, `"1G"`, bits/s, `"0"` = unlimited; normalized locally. |
| `setBandwidthLimit(c, name, upload, download)` |  | Same rate rules. |
| `removeSimpleQueue(c, name)` |  | Throws when no queue has that name (as do enable/disable). |
| `enableSimpleQueue(c, name)` |  |  |
| `disableSimpleQueue(c, name)` |  | The limit pauses until enabled. |
| `treeQueues(c)` | `list of TreeQueue` | All tree nodes. |
| `addQueueTreeRoot(c, name, parent, maxLimit)` | `string` | Parent: an interface (its egress) or `"global"`. Set the budget slightly below the line rate. Existing name: returns its id. |
| `addQueueTreeChild(c, name, parentName, packetMark, limitAt, maxLimit, priority)` | `string` | Priority 1-8 (1 first). Refuses an unknown parent or a packet mark no mangle rule sets. Existing name: returns its id. |
| `removeTreeQueue(c, name)` |  | Removes the whole subtree, children first. |
| `enableTreeQueue(c, name)` |  |  |
| `disableTreeQueue(c, name)` |  | Its subtree stops shaping. |

| Constant | Value |
|---|---|
| `QUEUE_SIMPLE_PATH` | `"/queue/simple"` |
| `QUEUE_TREE_PATH` | `"/queue/tree"` |

### `SimpleQueue`

One simple queue: a bandwidth limit on a target.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | queue name |
| `target as string` | limited address, network or interface, comma-separated |
| `maxUpload as string` | upload ceiling (e.g. "10M", "0" = unlimited) |
| `maxDownload as string` | download ceiling (e.g. "20M", "0" = unlimited) |
| `dynamic as bool` | true when created by something else (e.g. PPPoE) |
| `disabled as bool` | true when the queue is switched off |
| `comment as string` | comment, "" when unset |

### `TreeQueue`

One queue-tree node: a branch of the QoS hierarchy.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | node name |
| `parent as string` | an interface, "global", or another node's name |
| `packetMark as string` | mangle packet mark(s) served, "" on inner nodes |
| `limitAt as string` | guaranteed rate ("" = none) |
| `maxLimit as string` | ceiling rate ("" = unlimited) |
| `priority as int` | 1 (first served) to 8 (last), 0 when unset |
| `disabled as bool` | true when switched off |
| `comment as string` | comment, "" when unset |

## Traffic flow (NetFlow / IPFIX)

Guide: [Traffic flow (NetFlow / IPFIX)](trafficflow.md).

| Function | Returns | Notes |
|---|---|---|
| `trafficFlowStatus(c)` | `TrafficFlowSettings` | Enabled flag and accounted interfaces. |
| `flowTargets(c)` | `list of FlowTarget` | The collectors. |
| `enableTrafficFlow(c)` |  | All interfaces. Exports nothing until a target exists. |
| `disableTrafficFlow(c)` |  | Targets are kept. |
| `addFlowTarget(c, address, port, version)` | `string` | Collector must be an IP; version `"1"`, `"5"`, `"9"` or `"ipfix"`. Existing address and port: returns its id. |
| `removeFlowTarget(c, address)` |  | First target with that address; throws when none. |

| Constant | Value |
|---|---|
| `TRAFFIC_FLOW_PATH` | `"/ip/traffic-flow"` |
| `TRAFFIC_FLOW_TARGET_PATH` | `"/ip/traffic-flow/target"` |

### `TrafficFlowSettings`

The traffic-flow (NetFlow/IPFIX) settings.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when flow accounting is running |
| `interfaces as string` | accounted interfaces, "all" for every one |

### `FlowTarget`

One traffic-flow export target (a collector).

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `address as string` | collector address |
| `port as string` | collector UDP port |
| `version as string` | export protocol version ("1", "5", "9", "ipfix") |
| `disabled as bool` | true when switched off |

## Netwatch

Guide: [Netwatch](netwatch.md).

| Function | Returns | Notes |
|---|---|---|
| `netwatchHosts(c)` | `list of NetwatchHost` | Every watched host with state. |
| `watchHost(c, host, comment)` | `string` | Returns the id. Router default interval. Idempotent per host: an existing entry is returned unchanged. |
| `watchHostWith(c, host, interval, comment)` | `string` | As `watchHost` with a probe interval ("10s", "1m", "HH:MM:SS"). |
| `watchHostScripted(c, host, downScript, upScript, comment)` | `string` | RouterOS scripts run on each down / up transition; at least one required. Idempotent like `watchHost`. |
| `hostStatus(c, host)` | `NetwatchHost` | Throws `routeros` when the host is not watched. |
| `downHosts(c)` | `list of NetwatchHost` | Hosts with status "down"; "unknown" (not probed yet) is excluded. |
| `unwatchHost(c, host)` |  | Removes the entry. |
| `disableWatch(c, host)` |  | Pauses; entry and scripts kept. |
| `enableWatch(c, host)` |  | Resumes a paused watch. |

| Constant | Value |
|---|---|
| `NETWATCH_PATH` | `"/tool/netwatch"` |

### `NetwatchHost`

One watched host and its current state.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `host as string` | watched address |
| `status as string` | "up", "down", or "unknown" (not probed yet) |
| `up as bool` | computed: whether status is "up" |
| `since as string` | when the current state began, as RouterOS prints it |
| `interval as string` | time between probes, as RouterOS prints it |
| `timeout as string` | probe timeout, as RouterOS prints it |
| `upScript as string` | RouterOS script run when the host comes up, "" for none |
| `downScript as string` | RouterOS script run when the host goes down, "" for none |
| `disabled as bool` | whether the watch is switched off |
| `comment as string` | free-text comment, "" when unset |

## System

Guide: [System](system.md).

| Function | Returns | Notes |
|---|---|---|
| `systemInfo(c)` | `SystemInfo` | version, board, architecture, uptime, CPU load, memory; strings as reported |
| `identity(c)` | `string` | the router name |
| `setIdentity(c, name)` |  | rejects an empty name |
| `packages(c)` | `list of Package` | installed packages |
| `checkForUpdates(c)` | `UpdateStatus` | read-only; needs internet and DNS on the router; check `updateAvailable` |
| `downloadUpdates(c)` | `UpdateStatus` | downloads now, installs on the next reboot; blocks until done |
| `installUpdates(c)` |  | downloads, installs and reboots; the client is dead afterwards |
| `routerboard(c)` | `Routerboard` | model and boot firmware; check `upgradeAvailable` |
| `upgradeRouterboard(c)` |  | stages the firmware flash; takes effect on the next `reboot` |
| `reboot(c)` |  | connection drop swallowed, router refusal re-thrown (kind "mikrotik") |
| `shutdown(c)` |  | as `reboot`; powering on again needs physical access |
| `deviceMode(c)` | `DeviceMode` | mode and the features it gates (scheduler, fetch, e-mail, container) |
| `updateDeviceMode(c, mode)` |  | only pending: applied on a power cycle or reset-button press within minutes, not on `reboot`; DEVICE_MODE_* only |

| Constant | Value |
|---|---|
| `SYSTEM_PACKAGE_PATH` | `"/system/package"` |
| `SYSTEM_UPDATE_PATH` | `"/system/package/update"` |
| `SYSTEM_ROUTERBOARD_PATH` | `"/system/routerboard"` |
| `SYSTEM_RESOURCE_PATH` | `"/system/resource"` |
| `SYSTEM_IDENTITY_PATH` | `"/system/identity"` |
| `DEVICE_MODE_PATH` | `"/system/device-mode"` |
| `DEVICE_MODE_UPDATE_COMMAND` | `"/system/device-mode/update"` |
| `DEVICE_MODE_HOME` | `"home"` |
| `DEVICE_MODE_ADVANCED` | `"advanced"` |
| `DEVICE_MODE_ENTERPRISE` | `"enterprise"` |

### `Package`

One installed RouterOS software package.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | package name (e.g. "routeros", "wireless") |
| `version as string` | installed version (e.g. "7.15.2") |
| `disabled as bool` | true when the package is disabled |

### `UpdateStatus`

The state of the RouterOS package updater.

| Field | Meaning |
|---|---|
| `channel as string` | release channel ("stable", "testing", ...) |
| `installedVersion as string` | the RouterOS version running now |
| `latestVersion as string` | the newest version the channel offers, "" when unknown |
| `status as string` | the updater's own status text |
| `updateAvailable as bool` | true when a newer version can be installed |

### `Routerboard`

The routerboard: the hardware and its boot firmware.

| Field | Meaning |
|---|---|
| `model as string` | hardware model (e.g. "RB4011iGS+") |
| `serialNumber as string` | hardware serial number |
| `firmwareType as string` | firmware family (e.g. "al2") |
| `currentFirmware as string` | firmware version running now |
| `upgradeFirmware as string` | firmware version available to flash |
| `upgradeAvailable as bool` | true when `upgradeRouterboard` would change anything |

### `SystemInfo`

The router's software version, hardware and load.

| Field | Meaning |
|---|---|
| `version as string` | RouterOS version (e.g. "7.15.2 (stable)") |
| `boardName as string` | board name (e.g. "RB4011iGS+") |
| `architecture as string` | CPU architecture (e.g. "arm64") |
| `uptime as string` | time since the last boot (e.g. "2w3d4h5m6s") |
| `cpuLoad as string` | current CPU load in percent |
| `freeMemory as string` | free RAM in bytes |
| `totalMemory as string` | total RAM in bytes |

### `DeviceMode`

The router's device mode and the features it gates.

| Field | Meaning |
|---|---|
| `mode as string` | the active mode ("home" / "advanced" / "enterprise") |
| `flaggingEnabled as bool` | true when tamper flagging is on |
| `container as bool` | true when containers may run |
| `scheduler as bool` | true when the scheduler may run scripts |
| `fetch as bool` | true when /tool/fetch is allowed |
| `email as bool` | true when the router may send e-mail |
| `socks as bool` | true when the SOCKS proxy is allowed |
| `installAnyVersion as bool` | true when downgrades are permitted |

## Clock & NTP

Guide: [Clock & NTP](clock.md).

| Function | Returns | Notes |
|---|---|---|
| `clock(c)` | `Clock` | time, date, timezone, UTC offset |
| `setTimezone(c, timezone)` |  | IANA name or "UTC"; turns timezone autodetect off |
| `useNtp(c, servers)` |  | comma-separated DNS names or IPs; empty or spaced entries rejected |
| `disableNtp(c)` |  | the clock free-runs and resets at boot |
| `ntpStatus(c)` | `NtpStatus` | `synced` is true when the status is "synchronized" |

| Constant | Value |
|---|---|
| `CLOCK_PATH` | `"/system/clock"` |
| `NTP_CLIENT_PATH` | `"/system/ntp/client"` |

### `Clock`

The router's clock state.

| Field | Meaning |
|---|---|
| `time as string` | current time as reported |
| `date as string` | current date as reported |
| `timezone as string` | timezone name (e.g. "Europe/Berlin") |
| `autodetect as bool` | true when the router guesses the timezone |
| `gmtOffset as string` | the resulting UTC offset as reported |

### `NtpStatus`

The NTP client state.

| Field | Meaning |
|---|---|
| `enabled as bool` | true when the router syncs its clock |
| `servers as string` | the configured NTP servers, comma-separated |
| `status as string` | the sync state as reported |
| `synced as bool` | computed: the status equals "synchronized" |

## Router users

Guide: [Router users](users.md).

| Function | Returns | Notes |
|---|---|---|
| `users(c)` | `list of User` | all accounts; passwords are never returned |
| `userGroups(c)` | `list of UserGroup` | built-in and custom groups with their policies |
| `activeUsers(c)` | `list of UserSession` | live sessions: who, from where, via what |
| `addUser(c, name, password, group)` | `string` | group must exist, name must not; password non-empty and write-only |
| `setUserPassword(c, name, password)` |  | existing sessions stay alive; empty password rejected |
| `setUserGroup(c, name, group)` |  | refuses the session's own account; group must exist |
| `restrictUser(c, name, addresses)` |  | IPs and/or CIDRs, comma-separated; "" lifts; applies to new logins |
| `removeUser(c, name)` |  | refuses the session's own account |
| `enableUser(c, name)` |  | unknown user rejected |
| `disableUser(c, name)` |  | refuses the session's own account |

| Constant | Value |
|---|---|
| `USER_PATH` | `"/user"` |
| `USER_GROUP_PATH` | `"/user/group"` |
| `USER_ACTIVE_PATH` | `"/user/active"` |
| `GROUP_FULL` | `"full"` |
| `GROUP_READ` | `"read"` |
| `GROUP_WRITE` | `"write"` |

### `User`

One router user account.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | login name |
| `group as string` | permission group ("full", "read", "write", or custom) |
| `address as string` | networks the user may log in from, "" for anywhere |
| `lastLoggedIn as string` | last login time as reported, "" for never |
| `disabled as bool` | true when the account is switched off |
| `comment as string` | free-text comment, "" when unset |

### `UserGroup`

One user group: a named bundle of permissions (policies).

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | group name |
| `policy as string` | comma-separated policies ("read,write,api,...") |

### `UserSession`

One active login session on the router.

| Field | Meaning |
|---|---|
| `name as string` | the logged-in user |
| `address as string` | where the login came from, "" for console |
| `via as string` | how ("api", "ssh", "winbox", "console", ...) |
| `when as string` | when the session started, as reported |

## Certificates

Guide: [Certificates](certificates.md).

| Function | Returns | Notes |
|---|---|---|
| `certificates(c)` | `list of Certificate` | the whole store |
| `certificateByName(c, name)` | `Certificate` | unknown name rejected |
| `expiringCertificates(c, withinDays)` | `list of Certificate` | expiry within `withinDays`; durations like "51w6d" parsed to whole days, unparseable ones skipped |
| `generateSelfSigned(c, name, commonName, days)` | `string` | signed on the router (a few seconds); days 1-7300; name must be free |
| `enableLetsEncrypt(c, dnsName)` |  | RouterOS v7 built-in ACME (http-01); port 80 must be reachable under the name; blocks |
| `importCertificatePem(c, name, certPem, keyPem)` |  | via temporary `<name>.crt` / `<name>.key` files, removed afterwards; PEMs checked for BEGIN CERTIFICATE / PRIVATE KEY |
| `assignServiceCertificate(c, serviceName, certName)` |  | "api-ssl" or "www-ssl" only; clears the `invalid` flag |
| `removeCertificate(c, name)` |  | services using it go `invalid` |

| Constant | Value |
|---|---|
| `CERTIFICATE_PATH` | `"/certificate"` |

### `Certificate`

One certificate in the router's store.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | store name (the handle everything binds to) |
| `commonName as string` | the subject CN (usually the DNS name) |
| `issuer as string` | who signed it, "" for a template not yet signed |
| `expiresAfter as string` | time until expiry as reported (e.g. "51w6d") |
| `invalidAfter as string` | the absolute expiry date as reported |
| `hasPrivateKey as bool` | true when the router holds the key (usable for serving) |
| `trusted as bool` | true when marked trusted |
| `isCa as bool` | true for a CA certificate |

## Files & backups

Guide: [Files & backups](files.md).

| Function | Returns | Notes |
|---|---|---|
| `files(c)` | `list of RouterFile` | files and directories on the router's storage |
| `saveBackup(c, name)` |  | writes `<name>.backup`, checks it appeared; unencrypted, holds secrets |
| `saveBackupWith(c, name, password)` |  | encrypted; empty password rejected; checks the file appeared |
| `readFileText(c, name)` | `string` | small files only (a few KB); "" when too large to expose |
| `writeFileText(c, name, contents)` |  | creates or overwrites; RouterOS v7 |
| `removeFile(c, name)` |  | unknown file rejected |

| Constant | Value |
|---|---|
| `FILE_PATH` | `"/file"` |

### `RouterFile`

One file on the router's storage.

| Field | Meaning |
|---|---|
| `name as string` | file name (with extension, e.g. "nightly.backup") |
| `kind as string` | file type as reported ("backup", ".txt file", "directory", ...) |
| `size as int` | size in bytes |
| `creationTime as string` | when it was created, as reported |

## Disks

Guide: [Disks](disk.md).

| Function | Returns | Notes |
|---|---|---|
| `disks(c)` | `list of Disk` | empty when there is no storage or the read fails |
| `diskByName(c, name)` | `Disk` | matches `name`, then `slot` |
| `formatDisk(c, name, filesystem, label)` |  | erases the whole disk, no undo; ext4, fat32, exfat, btrfs, vfat; tries `/disk/format`, falls back to `/disk/format-drive` |
| `ejectDisk(c, name)` |  | matches `name`, then `slot` |

| Constant | Value |
|---|---|
| `DISK_PATH` | `"/disk"` |

### `Disk`

One storage device attached to the router.

| Field | Meaning |
|---|---|
| `id as string` | internal RouterOS id |
| `name as string` | the device name (e.g. "usb1", "nvme1"), from `slot` when unnamed |
| `model as string` | the disk model / label as reported |
| `kind as string` | the device type as reported ("hardware", "partition", "raid", ...) |
| `fs as string` | the filesystem ("ext4", "fat32", "", ...) |
| `sizeBytes as int` | total capacity in bytes (0 when not reported) |
| `freeBytes as int` | free space in bytes (0 when not reported) |
| `slot as string` | the physical slot / interface as reported |

## System health

Guide: [System health](health.md).

| Function | Returns | Notes |
|---|---|---|
| `healthSensors(c)` | `list of HealthSensor` | model-dependent; an empty list is normal |
| `healthValue(c, name)` | `string` | the reading, "" when the router does not report it |

| Constant | Value |
|---|---|
| `SYSTEM_HEALTH_PATH` | `"/system/health"` |

### `HealthSensor`

One hardware health sensor reading.

| Field | Meaning |
|---|---|
| `name as string` | what is measured ("cpu-temperature", "voltage", "fan1-speed", "temperature", ...) |
| `value as string` | the reading as reported (units vary by sensor) |
| `kind as string` | the reading type ("C", "V", "RPM", ...) when reported |

## The router log

Guide: [The router log](log.md).

| Function | Returns | Notes |
|---|---|---|
| `logEntries(c)` | `list of LogEntry` | The memory buffer, oldest first; 1000 entries by default, cleared on reboot. |
| `recentLogEntries(c, count)` | `list of LogEntry` | Newest `count` (at least 1), oldest of them first. |
| `logEntriesWithTopic(c, topic)` | `list of LogEntry` | Exact topic word: "fire" does not match "firewall". |
| `logErrors(c)` | `list of LogEntry` | Topic "error" or "critical". |
| `loggingRules(c)` | `list of LoggingRule` | Which topics go to which action. |
| `addLoggingRule(c, topics, action)` | `string` | Returns the id. Topics comma-separated, "!" negates; the action must exist. Idempotent. |
| `removeLoggingRule(c, topics, action)` |  | Topics compared in order after normalization. |
| `setupRemoteLogging(c, address, port, topics)` | `string` | Returns the rule id. Repoints the built-in "remote" action (UDP syslog, 514 standard). Idempotent. |

| Constant | Value |
|---|---|
| `LOG_PATH` | `"/log"` |
| `LOGGING_PATH` | `"/system/logging"` |
| `LOGGING_ACTION_PATH` | `"/system/logging/action"` |

### `LogEntry`

One log entry.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `time as string` | time as RouterOS prints it, e.g. "15:33:02"; older entries carry a date prefix |
| `topics as string` | comma-separated topics, e.g. "system,info" |
| `message as string` | the log line |

### `LoggingRule`

One logging rule: which topics go to which action.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `topics as string` | comma-separated topics matched, e.g. "info,!dns" |
| `action as string` | "memory", "disk", "echo", "remote", or a custom action |
| `prefix as string` | text prepended to each entry, "" when unset |
| `disabled as bool` | whether the rule is switched off |

## Scripts (the repository)

Guide: [Scripts (the repository)](script.md).

| Function | Returns | Notes |
|---|---|---|
| `scripts(c)` | `list of Script` | Every stored script. |
| `scriptByName(c, name)` | `Script` | Throws `routeros` when absent. |
| `addScript(c, name, source, comment)` | `string` | Returns the id. Source is RouterOS script, must not be blank; name must be free (else use `updateScript`). |
| `updateScript(c, name, source)` |  | Replaces the source of an existing script. |
| `runScript(c, name)` | `string` | Runs with the script's own policies; returns its return value or "". Script errors are `mikrotik`. |
| `removeScript(c, name)` |  | Scheduler entries that call it by name then fail. |

| Constant | Value |
|---|---|
| `SCRIPT_PATH` | `"/system/script"` |

### `Script`

One stored RouterOS script.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `name as string` | script name, the handle the scheduler and netwatch use |
| `source as string` | RouterOS script source |
| `policy as string` | comma-separated permissions it runs with |
| `runCount as int` | number of runs so far |
| `lastStarted as string` | time of the last run, as RouterOS prints it |
| `comment as string` | free-text comment, "" when unset |

## Scheduler

Guide: [Scheduler](scheduler.md).

| Function | Returns | Notes |
|---|---|---|
| `scheduledTasks(c)` | `list of ScheduledTask` | Every task, with `nextRun` and `runCount`. |
| `scheduleScript(c, name, interval, source)` | `string` | Returns the id. Interval "30s", "10m", "2h", "1d", "1w", "1d12h", bare seconds, or "HH:MM:SS". Runs with the policies of the client user. |
| `scheduleDaily(c, name, startTime, source)` | `string` | Returns the id. Router-local "HH:MM:SS", interval 1d. |
| `scheduleAtStartup(c, name, source)` | `string` | Returns the id. Runs once per boot. |
| `removeScheduledTask(c, name)` |  | By task name. |
| `enableScheduledTask(c, name)` |  | By task name. |
| `disableScheduledTask(c, name)` |  | Kept configured, stops firing. |

| Constant | Value |
|---|---|
| `SCHEDULER_PATH` | `"/system/scheduler"` |

### `ScheduledTask`

One scheduler entry: a script the router runs on a timer.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `name as string` | task name |
| `startTime as string` | "HH:MM:SS" or "startup" |
| `startDate as string` | first day the timer is armed, as RouterOS prints it |
| `interval as string` | time between runs ("1d", "00:30:00"; "0" runs once) |
| `onEvent as string` | RouterOS script source, or the name of a "/system/script" |
| `nextRun as string` | next firing time, as RouterOS prints it |
| `runCount as int` | number of runs so far |
| `disabled as bool` | whether the task is switched off |
| `comment as string` | free-text comment, "" when unset |

## Tools

Guide: [Tools](tools.md).

| Function | Returns | Notes |
|---|---|---|
| `ping(c, host)` | `PingResult` | 4 probes. Host is an IP or DNS name. |
| `pingWith(c, host, count)` | `PingResult` | 1-100 probes; a count is always sent because an unbounded RouterOS ping never returns. |
| `isReachable(c, host)` | `bool` | `ping(...).reachable`. |
| `bandwidthTest(c, host, seconds, direction)` | `BandwidthResult` | Against a btest server; 1-300 s; "receive", "transmit" or "both". Saturates the link. |
| `bandwidthTestWith(c, host, seconds, direction, user, password)` | `BandwidthResult` | As `bandwidthTest`, with btest credentials ("" omits). |
| `traceroute(c, host)` | `list of TracerouteHop` | One probe per hop. |
| `fetchUrl(c, url)` | `FetchResult` | URL must start with "http"; body in `data`. |
| `downloadFile(c, url, fileName)` | `FetchResult` | Saves to router storage; file name without spaces. |
| `configureEmail(c, server, port, from, user, password)` |  | Leaves the TLS mode unchanged; empty user / password are not sent. |
| `configureEmailWith(c, server, port, from, user, password, tls)` |  | `tls` is an `EMAIL_TLS_*` value or "" to keep it. Writes the pre-7.12 or 7.12+ property names, whichever the router has. |
| `emailSettings(c)` | `EmailSettings` | No password: RouterOS stores it write-only. |
| `sendEmail(c, recipient, subject, body)` |  | Needs `configureEmail` first. SMTP failure is `mikrotik`. |

| Constant | Value |
|---|---|
| `PING_COMMAND` | `"/ping"` |
| `TRACEROUTE_COMMAND` | `"/tool/traceroute"` |
| `FETCH_COMMAND` | `"/tool/fetch"` |
| `EMAIL_PATH` | `"/tool/e-mail"` |
| `EMAIL_TLS_NONE` | `"no"` |
| `EMAIL_TLS_STARTTLS` | `"starttls"` |
| `EMAIL_TLS_IMPLICIT` | `"yes"` |
| `BANDWIDTH_TEST_COMMAND` | `"/tool/bandwidth-test"` |

### `EmailSettings`

The router's outgoing e-mail (SMTP) settings.

| Field | Meaning |
|---|---|
| `server as string` | SMTP server, DNS name or IP, "" when unset |
| `port as int` | SMTP port, 0 when unset |
| `from as string` | From: address |
| `user as string` | SMTP login, "" when the relay needs none |
| `tls as string` | one of the EMAIL_TLS_* values |

### `PingResult`

The outcome of a ping from the router.

| Field | Meaning |
|---|---|
| `host as string` | host that answered, usually the target |
| `sent as int` | probes sent |
| `received as int` | replies received |
| `packetLoss as int` | loss in percent, 0 when every reply arrived |
| `minRtt as string` | fastest round trip as RouterOS prints it, e.g. "1ms52us" |
| `avgRtt as string` | average round trip as RouterOS prints it |
| `maxRtt as string` | slowest round trip as RouterOS prints it |
| `reachable as bool` | computed: whether at least one reply arrived |

### `BandwidthResult`

The outcome of a bandwidth test.

| Field | Meaning |
|---|---|
| `status as string` | final tester status, "done testing" on success |
| `direction as string` | "receive", "transmit" or "both" |
| `txCurrent as string` | transmit rate at the end of the test |
| `txAverage as string` | average transmit rate over the test |
| `rxCurrent as string` | receive rate at the end of the test |
| `rxAverage as string` | average receive rate over the test |
| `lostPackets as int` | packets lost during the test |

### `TracerouteHop`

One hop on a traceroute path.

| Field | Meaning |
|---|---|
| `address as string` | hop address, "" when it did not answer |
| `loss as string` | packet loss at this hop, as RouterOS prints it |
| `avgRtt as string` | average round trip to this hop, "" when no reply |
| `status as string` | hop status, as RouterOS prints it |

### `FetchResult`

The outcome of a router-side fetch.

| Field | Meaning |
|---|---|
| `status as string` | "finished" on success, else the failure text |
| `ok as bool` | computed: whether status is "finished" |
| `downloaded as string` | amount downloaded, as RouterOS prints it |
| `data as string` | response body; only `fetchUrl` fills it |

## Containers

Guide: [Containers](container.md).

| Function | Returns | Notes |
|---|---|---|
| `containers(c)` | `list of Container` | Every container; `name` is the comment `addContainer` set. |
| `addContainer(c, name, remoteImage, interfaceName, rootDir)` | `string` | Returns the id. Needs the container package, device-mode enable, an existing veth and storage. `name` is stored as the comment. |
| `startContainer(c, name)` |  | By comment or image tag. |
| `stopContainer(c, name)` |  | By comment or image tag. |
| `removeContainer(c, name)` |  | Also deletes its extracted filesystem. |
| `containerEnvs(c)` | `list of ContainerEnv` | Variables of every env list. |
| `addContainerEnv(c, listName, key, value)` | `string` | Returns the id. Always adds; clear the list first on a re-run. |
| `removeContainerEnvList(c, listName)` | `int` | Deletes every variable in the list; returns the count. |
| `containerMounts(c)` | `list of ContainerMount` | Mounts of every mount list. |
| `addContainerMount(c, listName, src, dst)` | `string` | Returns the id. `src` on the router (created if missing), `dst` in the container. |
| `removeContainerMountList(c, listName)` | `int` | Deletes every mount in the list; returns the count. |
| `setContainerEnvLists(c, name, listNames)` |  | Replaces the attached lists; `[]` detaches all. Takes effect at the next start. |
| `setContainerMountLists(c, name, listNames)` |  | Replaces the attached lists; `[]` detaches all. Set before the first start. |

| Constant | Value |
|---|---|
| `CONTAINER_PATH` | `"/container"` |
| `CONTAINER_ENVS_PATH` | `"/container/envs"` |
| `CONTAINER_MOUNTS_PATH` | `"/container/mounts"` |
| `CONTAINER_CONFIG_PATH` | `"/container/config"` |

### `Container`

One container on the router.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `name as string` | the comment `addContainer` set, else the image tag |
| `tag as string` | image tag it runs |
| `status as string` | "running", "stopped", "extracting", "error", ...; derived from `running` when the router sends no status |
| `running as bool` | whether the container is up |
| `interfaceName as string` | veth interface it attaches to |
| `rootDir as string` | path of its filesystem on the router |
| `envLists as string` | comma-separated env lists, "" for none |
| `mountLists as string` | comma-separated mount lists, "" for none |

### `ContainerEnv`

One environment variable belonging to a named env list.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `listName as string` | env list it belongs to |
| `key as string` | variable name, e.g. "TZ" |
| `value as string` | variable value |

### `ContainerMount`

One mount belonging to a named mount list.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `listName as string` | mount list it belongs to |
| `src as string` | path on the router's storage |
| `dst as string` | path inside the container |

## Cloud DDNS

Guide: [Cloud DDNS](cloud.md).

| Function | Returns | Notes |
|---|---|---|
| `cloudStatus(c)` | `CloudStatus` | DDNS flag, name, last seen public address, update time. |
| `enableCloudDns(c)` |  | Turns DDNS on and forces an update; the name resolves within about a minute. |
| `disableCloudDns(c)` |  | The name stops following the public address. |
| `routerDnsName(c)` | `string` | `<serial>.sn.mynetname.net`; throws `routeros` until assigned. |

| Constant | Value |
|---|---|
| `CLOUD_PATH` | `"/ip/cloud"` |

### `CloudStatus`

MikroTik Cloud DDNS state.

| Field | Meaning |
|---|---|
| `ddnsEnabled as bool` | whether the router keeps its cloud name updated |
| `dnsName as string` | `<serial>.sn.mynetname.net`, "" until the first update completes |
| `publicAddress as string` | the public address MikroTik's servers last saw |
| `updateTime as string` | time of the last update, as RouterOS prints it |

## SMS

Guide: [SMS](sms.md).

| Function | Returns | Notes |
|---|---|---|
| `smsSettings(c)` | `SmsSettings` | Current SMS settings. |
| `enableSmsReceive(c, port)` |  | Reception is off by default; `port` is the modem port, e.g. "lte1". |
| `disableSmsReceive(c)` |  | Stops reception; the inbox is kept. |
| `restrictSms(c, allowedNumber, keepMaxSms)` |  | Sender accepted for SMS commands ("" = anyone) and inbox cap 1-100. Set it: unrestricted SMS commands are unauthenticated. |
| `sendSms(c, port, phoneNumber, message)` |  | Leaves over the modem when the wired uplink is down. Number: digits, `+ - ( )`, spaces. Modem refusal is `mikrotik`. |
| `smsInbox(c)` | `list of SmsMessage` | Received messages; empty until reception is enabled. |
| `removeSmsMessage(c, id)` |  | Deletes one message by id. |
| `clearSmsInbox(c)` | `int` | Deletes every message; returns the count. |

| Constant | Value |
|---|---|
| `SMS_PATH` | `"/tool/sms"` |
| `SMS_INBOX_PATH` | `"/tool/sms/inbox"` |
| `SMS_SEND_COMMAND` | `"/tool/sms/send"` |

### `SmsSettings`

The router's SMS settings.

| Field | Meaning |
|---|---|
| `receiveEnabled as bool` | whether incoming messages are stored |
| `port as string` | modem port, e.g. "lte1" |
| `channel as string` | modem channel, "" for the default |
| `allowedNumber as string` | the only sender accepted for remote commands, "" when unrestricted |
| `keepMaxSms as int` | cap on stored received messages |
| `autoErase as bool` | whether the oldest message is dropped at the cap |

### `SmsMessage`

One received text message.

| Field | Meaning |
|---|---|
| `id as string` | RouterOS item id |
| `phone as string` | sender's number |
| `message as string` | message text |
| `timestamp as string` | receive time, as RouterOS prints it |
| `kind as string` | RouterOS `type` value, "" when absent |

## Layout and tests

```
src/routeros.j        the module: use/import lines and one include per topic
src/routeros_test.j   the test overlay: use testing and one include per topic
src/topics/           T.j and T_test.j for each topic
docs/                 one guide per topic
examples/             one read-only example per topic
```

`include` is a textual splice: `src/routeros.j` is the only module and holds
every export, so consumers import `@deckyard/routeros/` and never a topic file.

```sh
jennifer test src/routeros_test.j
```

The tests need no router: they cover validators, reply-row folding, builders
and redaction, and call each verb that validates input on a never-connected
client to check it rejects bad input before any I/O.
