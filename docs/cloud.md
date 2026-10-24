# Cloud DDNS

File: `src/topics/cloud.j`. Path: `/ip/cloud` (`CLOUD_PATH`).
Reference: [cheatsheet](cheatsheet.md#cloud-ddns).

With MikroTik Cloud DDNS the router registers `<serial>.sn.mynetname.net`
with MikroTik and keeps it pointing at its current public address. On a
WAN with a dynamic address, that name is what road-warrior WireGuard,
port forwards and Let's Encrypt use. A CNAME in your own zone can give it
a nicer name.

## Examples

A WireGuard server reachable on a dynamic address:

```jennifer
mt.enableCloudDns($c);
def name as string init mt.routerDnsName($c);
io.printf("road warriors dial: %s:13231\n", $name);
mt.setupWireguardServer($c, "wgvpn", 13231, "10.100.0.1/24");
```

The address MikroTik's servers last saw:

```jennifer
def st as mt.CloudStatus init mt.cloudStatus($c);
io.printf("public address: %s (updated %s)\n", $st.publicAddress, $st.updateTime);
```

## Pitfalls

- `routerDnsName` throws `routeros` until the first update has landed.
  After `enableCloudDns`, allow up to a minute; the router needs working
  internet access and DNS.
- `publicAddress` is the address MikroTik's servers saw. Behind CGNAT
  nobody can reach it and DDNS does not help: get a public address from
  the ISP, or dial out with `connectWireguard`.
- The updates talk to MikroTik's cloud. Where that is not acceptable, use
  a third-party DDNS through scheduler and fetch scripts.
- The name is bound to the device serial. Replacing the hardware changes
  it; a CNAME in your own zone hides that from users.

See also [wireguard.md](wireguard.md) and
[certificates.md](certificates.md) (`enableLetsEncrypt` uses this name).
