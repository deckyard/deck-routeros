# The ARP table

File: `src/topics/arp.j`. Path: `/ip/arp` (`ARP_PATH`).
Reference: [cheatsheet](cheatsheet.md#the-arp-table).

The ARP table maps IP addresses to MAC addresses on the router's
connected networks. It serves two purposes:

- an inventory: every device the router recently exchanged packets with
  is listed, so it answers "who is on this LAN right now";
- an access control: static (pinned) entries, combined with the
  interface property `arp=reply-only`, let only pinned devices talk.

Dynamic entries are learned and age out; static entries stay until
removed. `complete == false` means the router asked and got no answer,
usually an offline device. `macForAddress` returns `""` on a miss
instead of throwing, because a miss is normal.

## Examples

List one interface's neighbours:

```jennifer
def neighbours as list of mt.ArpEntry init mt.arpTableOn($c, "brlan");
for (def n in $neighbours) {
    io.printf("%s -> %s dynamic=%t complete=%t\n",
        $n.address, $n.mac, $n.dynamic, $n.complete);
}
```

Look a device up both ways:

```jennifer
def mac as string init mt.macForAddress($c, "192.168.88.50");
if ($mac == "") {
    io.printf("the printer has not talked to the router recently\n");
}

def addrs as list of string init mt.addressesForMac($c, "AA:BB:CC:DD:EE:FF");
for (def a in $addrs) {
    io.printf("that device holds %s\n", $a);
}
```

Lock a LAN to pinned devices. `arp` is an interface property, so it is
set with the generic verb:

```jennifer
mt.addStaticArp($c, "192.168.88.50", "AA:BB:CC:DD:EE:FF", "brlan");
mt.addStaticArp($c, "192.168.88.51", "11:22:33:44:55:66", "brlan");
mt.set($c, mt.INTERFACE_PATH,
    mt.idByName($c, mt.INTERFACE_PATH, "brlan"), {"arp": "reply-only"});
```

After a device changed hardware but kept its IP, remove the stale entry
(and re-pin a static one with the new MAC):

```jennifer
mt.removeArpEntry($c, "192.168.88.50");
```

## Pitfalls

- Only layer-2 neighbours appear. Devices behind another router are
  never in the table.
- The table is a cache: absence proves nothing, presence proves recent
  traffic.
- `arp=reply-only` cuts off every device not pinned, possibly including
  your management host. Pin first, switch second.
- Static ARP protects the router's view only; it does not stop spoofing
  between other hosts on the segment.
- The DHCP server can add ARP entries for its leases (`add-arp`, set
  with the generic verbs), which pairs with `arp=reply-only`.

See also: [dhcp.md](dhcp.md), [interfaces.md](interfaces.md),
[wireless.md](wireless.md) (`wifiClients` lists WiFi clients).
