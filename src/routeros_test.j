# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for the routeros module: `jennifer test src/routeros_test.j`.
 *
 * One test file per topic under `topics/`, spliced in with `include`. The
 * tests cover validation, reply-row folding, builders and log redaction,
 * and call the verbs on a never-connected client (`offlineClient` in
 * `core_test.j`) to check that bad input is rejected before any I/O. Nothing
 * here opens a connection; behaviour against a router is not tested here.
 */

use testing;

include "topics/core_test.j";
include "topics/interfaces_test.j";
include "topics/interfacelist_test.j";
include "topics/ethernet_test.j";
include "topics/lte_test.j";
include "topics/bonding_test.j";
include "topics/bridges_test.j";
include "topics/switch_test.j";
include "topics/vlans_test.j";
include "topics/firewall_test.j";
include "topics/nat_test.j";
include "topics/raw_test.j";
include "topics/addresslist_test.j";
include "topics/mangle_test.j";
include "topics/contrack_test.j";
include "topics/ip_test.j";
include "topics/ipv6_test.j";
include "topics/arp_test.j";
include "topics/neighbor_test.j";
include "topics/dhcp_test.j";
include "topics/ppp_test.j";
include "topics/l2tp_test.j";
include "topics/sstp_test.j";
include "topics/ovpn_test.j";
include "topics/hotspot_test.j";
include "topics/dns_test.j";
include "topics/routing_test.j";
include "topics/upnp_test.j";
include "topics/trafficflow_test.j";
include "topics/queues_test.j";
include "topics/wireless_test.j";
include "topics/wifi_test.j";
include "topics/capsman_test.j";
include "topics/wireguard_test.j";
include "topics/eoip_test.j";
include "topics/gre_test.j";
include "topics/ipsec_test.j";
include "topics/vrrp_test.j";
include "topics/tools_test.j";
include "topics/sms_test.j";
include "topics/netwatch_test.j";
include "topics/scheduler_test.j";
include "topics/script_test.j";
include "topics/users_test.j";
include "topics/services_test.j";
include "topics/certificates_test.j";
include "topics/clock_test.j";
include "topics/files_test.j";
include "topics/disk_test.j";
include "topics/cloud_test.j";
include "topics/snmp_test.j";
include "topics/radius_test.j";
include "topics/health_test.j";
include "topics/container_test.j";
include "topics/log_test.j";
include "topics/system_test.j";
