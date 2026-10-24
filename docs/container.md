<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Containers

File: `src/topics/container.j`. Paths: `/container` (`CONTAINER_PATH`),
`/container/envs` (`CONTAINER_ENVS_PATH`), `/container/mounts`
(`CONTAINER_MOUNTS_PATH`), `/container/config` (`CONTAINER_CONFIG_PATH`).
Reference: [cheatsheet](cheatsheet.md#containers).

RouterOS 7 runs OCI (Docker) images on ARM, ARM64 and x86 models with
enough storage. Prerequisites, set up once before this topic is useful:
the `container` package, container support enabled in the device mode
(a deliberate console-side step that needs a reboot; this deck does not
flip it), a veth interface, and storage.

A container's RouterOS `name` is read-only and reports the image tag
(`pihole:latest`). `addContainer` therefore stores your handle as the
comment, and `Container.name` and every call that takes a container
`name` match the comment first, then the tag.

## Environment and mounts

Environment variables and mounts are named lists: each entry under
`/container/envs` or `/container/mounts` carries a `list` name, and a
container references lists through `envlists` and `mountlists`. Create
the entries, create the container, attach the lists, then start it:
most images read their config only at startup, and a running container
needs a stop and start to see a change. Mount a config directory out to
disk so its state survives a re-pull of the image.

`addContainerEnv` and `addContainerMount` always add. To re-run a
provisioning script without duplicates, clear the list first:
`removeContainerEnvList` and `removeContainerMountList` return how many
entries they deleted.

## Example: Pi-hole on the router

```jennifer
# prerequisites (generic verbs): a veth for container networking
mt.add($c, "/interface/veth", {"name": "veth1", "address": "172.17.0.2/24",
    "gateway": "172.17.0.1"});
# then bridge the veth, and NAT or route 172.17.0.0/24

mt.removeContainerEnvList($c, "pihole-env");
mt.addContainerEnv($c, "pihole-env", "TZ", "Europe/Vienna");
mt.addContainerEnv($c, "pihole-env", "FTLCONF_dns_upstreams", "9.9.9.9");
mt.addContainerMount($c, "pihole-etc", "usb1/pihole/etc", "/etc/pihole");

mt.addContainer($c, "pihole", "pihole/pihole:latest", "veth1", "usb1/pihole");
mt.setContainerEnvLists($c, "pihole", ["pihole-env"]);
mt.setContainerMountLists($c, "pihole", ["pihole-etc"]);
mt.startContainer($c, "pihole");

def cts as list of mt.Container init mt.containers($c);
for (def ct in $cts) { io.printf("%s (%s): %s\n", $ct.name, $ct.tag, $ct.status); }
```

## Pitfalls

- Storage: each container extracts a few hundred MB onto the router's
  disk. Point `rootDir` at USB or NVMe storage that is formatted
  ([disk.md](disk.md)); an unformatted disk shows up later as an
  extraction failure for "no space".
- Networking is ordinary [bridging](bridges.md), [routing](routing.md)
  and [NAT](nat.md) work on the veth.
- With the generic verbs, the field names are `list` (not `name`) on env
  and mount entries, and `envlists` / `mountlists` (plural) on the
  container; anything else gets `!trap: unknown parameter`.
- A container is software running on your router; treat its image and
  exposure like any other host.

See also [dns.md](dns.md) (point DHCP clients at a DNS container) and
[files.md](files.md).
