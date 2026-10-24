<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Traffic flow (NetFlow / IPFIX)

File: `src/topics/trafficflow.j`. Paths: `/ip/traffic-flow`
(`TRAFFIC_FLOW_PATH`), `/ip/traffic-flow/target`
(`TRAFFIC_FLOW_TARGET_PATH`). Reference:
[cheatsheet](cheatsheet.md#traffic-flow-netflow--ipfix).

Traffic flow exports a record per connection to a collector (ntopng,
Elastiflow, SolarWinds, a commercial appliance) for bandwidth graphs,
top talkers and per-application breakdowns. SNMP gives interface
totals; flow records show individual connections.

It takes two steps: `enableTrafficFlow` turns accounting on for all
interfaces, and `addFlowTarget` names a collector. `version` is `"1"`,
`"5"` (the widely supported legacy format), `"9"` or `"ipfix"`; pick
one your collector reads.

```jennifer
mt.enableTrafficFlow($c);
mt.addFlowTarget($c, "10.0.9.30", 2055, "ipfix");

def ts as list of mt.FlowTarget init mt.flowTargets($c);
for (def t in $ts) { io.printf("export v%s -> %s:%s\n", $t.version, $t.address, $t.port); }
```

## Pitfalls

- Accounting without a target exports nothing, and a target without
  accounting enabled receives nothing.
- Accounting costs per-connection CPU: negligible on most routers,
  noticeable on a small CPU with heavy connection churn.
- Export is unencrypted UDP; keep the collector on a trusted segment.

See also: [snmp.md](snmp.md), [contrack.md](contrack.md),
[mangle.md](mangle.md).
