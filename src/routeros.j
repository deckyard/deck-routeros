# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * routeros - typed verbs and structs over the MikroTik RouterOS API.
 *
 * The bundled `mikrotik` module speaks the binary API (command paths,
 * `=key=value` words, reply rows). This module wraps it per topic:
 * interfaces, ethernet, bonding, bridges, VLANs, wireless, the firewall
 * (filter, NAT, raw, mangle, address lists), addressing, DHCP, DNS,
 * IPv6, PPPoE, hotspot, routing, queues, tunnels and VPNs, VRRP,
 * diagnostics, users, services, certificates, clock, files, logging and
 * system maintenance. Inputs are validated before anything is sent and
 * reply rows are folded into value-semantic structs. Local validation
 * failures throw `Error{kind: "routeros"}`; router and transport errors
 * throw `Error{kind: "mikrotik"}`.
 *
 * The topic files under `topics/` are spliced in with `include`, so this
 * file is the module boundary and holds every `export`. The white-box
 * tests are in `routeros_test.j`.
 *
 * @module routeros
 * @see https://jennifer-lang.dev/modules/mikrotik.html
 * @example
 *   import "./routeros.j" as mt;
 *
 *   def c as mt.Client init mt.connect("192.168.88.1", "admin", "secret");
 *   mt.addBridge($c, "brlan");
 *   mt.addBridgePort($c, "brlan", "ether2");
 *   mt.allowService($c, "tcp", 22, "ssh management");
 *   mt.disconnect($c);
 */

use strings;
use lists;
use maps;
use convert;
use io;
use os;

import "mikrotik.j";
import "ipnet.j";

include "topics/core.j";
include "topics/interfaces.j";
include "topics/interfacelist.j";
include "topics/ethernet.j";
include "topics/lte.j";
include "topics/bonding.j";
include "topics/bridges.j";
include "topics/switch.j";
include "topics/vlans.j";
include "topics/firewall.j";
include "topics/nat.j";
include "topics/raw.j";
include "topics/addresslist.j";
include "topics/mangle.j";
include "topics/contrack.j";
include "topics/ip.j";
include "topics/ipv6.j";
include "topics/arp.j";
include "topics/neighbor.j";
include "topics/dhcp.j";
include "topics/ppp.j";
include "topics/l2tp.j";
include "topics/sstp.j";
include "topics/ovpn.j";
include "topics/hotspot.j";
include "topics/dns.j";
include "topics/routing.j";
include "topics/upnp.j";
include "topics/trafficflow.j";
include "topics/queues.j";
include "topics/wireless.j";
include "topics/wifi.j";
include "topics/capsman.j";
include "topics/wireguard.j";
include "topics/eoip.j";
include "topics/gre.j";
include "topics/ipsec.j";
include "topics/vrrp.j";
include "topics/tools.j";
include "topics/sms.j";
include "topics/netwatch.j";
include "topics/scheduler.j";
include "topics/script.j";
include "topics/users.j";
include "topics/services.j";
include "topics/certificates.j";
include "topics/clock.j";
include "topics/files.j";
include "topics/disk.j";
include "topics/cloud.j";
include "topics/snmp.j";
include "topics/radius.j";
include "topics/health.j";
include "topics/container.j";
include "topics/log.j";
include "topics/system.j";
