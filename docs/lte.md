<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# LTE / cellular

File: `src/topics/lte.j`. Paths: `/interface/lte` (`LTE_PATH`),
`/interface/lte/apn` (`LTE_APN_PATH`).

Reference: [cheatsheet](cheatsheet.md#lte--cellular).

A cellular modem gives a backup WAN, or the only uplink at a site without
a wired line. It needs the carrier's APN and enough signal.

`lteInterfaces` returns an empty list on any read error: on a router
without a modem, and also on a dropped connection. `lteStatus` runs
`monitor once`; `registered` is true when the status contains
`"registered"`. `setLteApn` creates or updates an APN profile named
`routeros-<interface>` and binds it to the interface.

```jennifer
def s as mt.LteStatus init mt.lteStatus($c, "lte1");
io.printf("%s on %s (%s)\n", $s.status, $s.operator, $s.accessTechnology);
io.printf("RSRP %s, RSRQ %s, SINR %s\n", $s.rsrp, $s.rsrq, $s.sinr);

mt.setLteApn($c, "lte1", "internet");   # fixes "registered but no data"
```

As a backup WAN: give the LTE route a higher distance than the primary
([routing.md](routing.md)), masquerade it ([nat.md](nat.md)), and
optionally watch the primary with [netwatch.md](netwatch.md).

## Pitfalls

- RSRP better than about -90 dBm is good, -100 to -110 dBm marginal,
  worse drops out. An external antenna or a window position helps more
  than configuration.
- A wrong APN registers on the network but passes no data. SIMs that need
  an APN user and password: set them with the generic verbs on the profile.
- On a metered SIM, check route distances so normal traffic does not use
  the backup link.
- Band and technology locking, SIM PIN and roaming: generic verbs on the
  interface.
