# Modern WiFi (wifiwave2 / ax)

File: `src/topics/wifi.j`. Paths: `/interface/wifi` (`WIFI_PATH`),
`/interface/wifi/registration-table` (`WIFI_REGISTRATION_PATH`).
RouterOS v7 on ax-generation hardware.

Reference: [cheatsheet](cheatsheet.md#modern-wifi-wifiwave2--ax).

## Background

MikroTik has two WiFi stacks. Older boards use the classic
`/interface/wireless` menu ([wireless.md](wireless.md)); ax hardware uses
`/interface/wifi`, whose properties are dotted keys
(`configuration.ssid`, `security.passphrase`) and which has no separate
security profiles: the passphrase lives on the interface. Each topic's
readers return empty lists on the other kind of router, so a script can
probe both:

```jennifer
def classic as list of mt.WirelessInterface init mt.wirelessInterfaces($c);
def modern as list of mt.WifiInterface init mt.wifiInterfaces($c);
```

WiFi interfaces are interfaces: switch them on and off with
`enableInterface` / `disableInterface`. Validation is shared with the
classic topic: SSIDs 1-32 characters, passphrases 8-63.

## Examples

An access point with WPA2 + WPA3:

```jennifer
mt.setupWifi($c, "wifi1", "My Home WiFi", "correct horse battery");
mt.addBridgePort($c, "brlan", "wifi1");
```

Guest WiFi with its own bridge and a bandwidth cap:

```jennifer
mt.addVirtualWifi($c, "wifi1", "wifiguest", "Guest WiFi", "changeme123");
mt.addBridge($c, "brguest");
mt.addBridgePort($c, "brguest", "wifiguest");
mt.limitBandwidth($c, "qguest", "192.168.90.0/24", "5M", "20M");
```

Connected clients:

```jennifer
def regs as list of mt.WifiRegistration init mt.wifiRegistrations($c);
for (def r in $regs) {
    io.printf("%s on %s (%s), signal %s dBm, %s\n",
        $r.mac, $r.interfaceName, $r.ssid, $r.signal, $r.uptime);
}
```

## Pitfalls

- On a classic-wireless board `setupWifi` fails with "WiFi interface
  not found". Probe with `wifiInterfaces` and `wirelessInterfaces` when
  the hardware is unknown; both also return empty on a read error.
- `setupWifi` enables WPA2/WPA3 mixed mode. For a legacy client that
  fails on WPA3 transition mode, set
  `security.authentication-types=wpa2-psk` with the generic `set`.
- Changing the passphrase disconnects all clients.
- Dual-band boards have `wifi1` and `wifi2` (2.4 and 5 GHz). The same
  SSID and passphrase on both allows roaming; different ones steer
  devices.
- CAPsMAN-managed radios ignore local settings; see
  [capsman.md](capsman.md).
