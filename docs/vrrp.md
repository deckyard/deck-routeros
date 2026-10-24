# VRRP: gateway redundancy

File: `src/topics/vrrp.j`. Path: `/interface/vrrp` (`VRRP_PATH`).
Reference: [cheatsheet](cheatsheet.md#vrrp).

Two or more routers share one virtual address, which clients use as
their gateway. The **master** (highest priority) answers for it; the
**backups** listen to its advertisements and the best one takes over
within seconds when they stop, keeping the same IP and virtual MAC.
Clients need no change.

The shared parameters:

- **vrid**, 1-255: the redundancy group. Identical on all peers, unique
  per network segment; the same vrid on another interface is allowed.
- **priority**, 1-254 (RFC 5798 reserves 255 for the address owner):
  the highest wins. Give the preferred router a clearly higher number
  (200 vs 100); equal priorities make the election arbitrary.
- **virtual address**: the same on all peers, on the VRRP interface,
  `/32` by convention. Each router keeps its own LAN address as well.

`addVrrp` (and so `setupVrrp`) refuses a taken name and a vrid already
used on the interface, naming the instance that holds it.

## A redundant gateway pair

Each router has its own LAN address (.251, .252); the clients' gateway
is the virtual .254:

```jennifer
# router A (preferred)
mt.setupVrrp($c, "vrrplan", "brlan", 10, 200, "192.168.88.254/32");

# router B (standby), on its own client
# mt.setupVrrp($cb, "vrrplan", "brlan", 10, 100, "192.168.88.254/32");
```

Pass `192.168.88.254` as the `gateway` of `setupDhcp`
([dhcp.md](dhcp.md)) so DHCP clients use the virtual address.

Which router is master:

```jennifer
def v as mt.VrrpInterface init mt.vrrpByName($c, "vrrplan");
if ($v.master) {
    io.printf("this router answers for the gateway\n");
} elseif ($v.backup) {
    io.printf("standing by, priority %d\n", $v.priority);
}
```

Hand the role away before maintenance:

```jennifer
mt.setVrrpPriority($c, "vrrplan", 50);   # the peer takes over within seconds
# ... maintain, reboot, verify ...
mt.setVrrpPriority($c, "vrrplan", 200);  # with preemption on, the role returns
```

## Pitfalls

- A pair behind one switch, uplink or power strip still has a single
  point of failure.
- Only the gateway address fails over. NAT state and DHCP leases are
  per router: run DHCP on both (split scopes, or leases long enough to
  survive) and expect long-lived connections to reset.
- The firewall must accept protocol `vrrp` (multicast 224.0.0.18)
  between the peers. If a strict input chain drops it, both routers
  claim master (split brain). `vrrp` is in the firewall builder's
  protocol list ([firewall.md](firewall.md)).
- Peers must run the same VRRP `version` (v3 is the RouterOS 7
  default); a mismatch also ends with two masters.
