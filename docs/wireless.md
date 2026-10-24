# Wireless (WiFi)

File: `src/topics/wireless.j`. Paths: `/interface/wireless`
(`WIRELESS_PATH`), `/interface/wireless/security-profiles`
(`WIRELESS_SECURITY_PATH`), `/interface/wireless/registration-table`
(`WIRELESS_REGISTRATION_PATH`).

Reference: [cheatsheet](cheatsheet.md#wireless-wifi).

## Background

This topic drives the classic wireless menu (the "wireless" package).
wifiwave2 / ax hardware uses `/interface/wifi`; see [wifi.md](wifi.md).
On such routers the readers here return empty lists.

The WiFi password does not live on the interface but in a security
profile the interface references. Fresh routers put every radio on the
shared `default` profile, so changing its key changes it for all radios.
routeros never touches `default`: it manages one profile per interface,
`routeros-<interface>` (WPA2-PSK, dynamic keys), created or updated
idempotently.

SSIDs must be 1-32 characters (spaces allowed) and passphrases 8-63
characters (the WPA2 rule); both are checked before anything is sent.

## Examples

An access point in one call, joined to the LAN bridge:

```jennifer
mt.setupWifiAccessPoint($c, "wlan1", "My Home WiFi", "correct horse battery");
mt.addBridgePort($c, "brlan", "wlan1");
```

Guest WiFi on the same radio, in its own bridge:

```jennifer
mt.addVirtualAp($c, "wlan1", "wlanguest", "Guest WiFi", "changeme123");
mt.addBridge($c, "brguest");
mt.addBridgePort($c, "brguest", "wlanguest");
```

Connected clients with signal:

```jennifer
def clients as list of mt.WifiClient init mt.wifiClients($c);
for (def cl in $clients) {
    io.printf("%s on %s, signal %s, %s\n",
        $cl.mac, $cl.interfaceName, $cl.signalStrength, $cl.uptime);
}
```

## Pitfalls

- Changing the SSID or password disconnects every client on that
  interface; they must reconnect with the new settings.
- A virtual AP shares the master radio's channel and airtime; a second
  SSID adds no capacity.
- A guest SSID is only separated from the LAN by its own bridge and
  [firewall](firewall.md) rules; consider a [queue](queues.md) cap too.
- `wirelessInterfaces` and `wifiClients` return an empty list on any
  read error, so a dropped session looks like a router without radios.
- Signal strengths are strings as the router reports them. Around
  -50 dBm is excellent, -70 dBm usable, -85 dBm unusable.
