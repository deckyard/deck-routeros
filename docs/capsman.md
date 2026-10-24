<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# CAPsMAN: central WiFi management

File: `src/topics/capsman.j`. Paths: legacy `/caps-man/*`
(`CAPSMAN_PATH`, `CAPSMAN_REGISTRATION_PATH`, `CAPSMAN_REMOTE_PATH`),
CAPsMANv2 `/interface/wifi/capsman`, `/interface/wifi/cap`
(`WIFI_CAPSMAN_PATH`, `WIFI_CAP_PATH`).

Reference: [cheatsheet](cheatsheet.md#capsman).

## Background

CAPsMAN makes one router the controller for many access points (CAPs),
which download their SSID, security and channel plan from it. A change
on the controller reaches every AP, and clients roam between them.

RouterOS has two incompatible generations:

- legacy `/caps-man`, for classic-wireless hardware
  ([wireless.md](wireless.md));
- CAPsMANv2 under `/interface/wifi`, for wifiwave2/ax hardware
  ([wifi.md](wifi.md)).

This topic reports and toggles whichever the router has, trying v2
first. `CapsmanStatus.version` is 2, 1, or 0 for neither. Read errors
count as "menu absent", so a dropped connection also reads as version 0
and an empty `managedAps`.

## Example

```jennifer
def st as mt.CapsmanStatus init mt.capsmanStatus($c);
if ($st.version == 0) { io.printf("no CAPsMAN on this router\n"); }
else { io.printf("CAPsMAN v%d, %d APs\n", $st.version, $st.managedAps); }

mt.enableCapsman($c);

def aps as list of mt.ManagedAp init mt.managedAps($c);
for (def ap in $aps) { io.printf("%s at %s: %s\n", $ap.identity, $ap.address, $ap.state); }
```

## Configuration and provisioning

`enableCapsman` only switches the manager on. The configuration (SSID,
security, datapath/bridge) and the provisioning rules (which
configuration a joining AP receives) differ between the generations, so
this topic leaves them to the generic verbs:
`/caps-man/configuration` + `/caps-man/provisioning` (v1) or
`/interface/wifi/configuration` + `/interface/wifi/provisioning` (v2).
Without them, joining APs register but broadcast nothing. On the AP
side, enable the CAP with `/interface/wifi/cap set enabled=yes` (v2) or
`/interface/wireless/cap` (v1), pointing at the manager.

## Pitfalls

- v1 configuration on v2 hardware, or the reverse, has no effect.
  Check `capsmanStatus($c).version` first.
- The CAPs must reach the controller at a stable address (CAPsMAN
  discovery or a configured address), usually on the management VLAN.
- A managed CAP ignores its local WiFi settings; configure the
  controller.
