<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# System health

File: `src/topics/health.j`. Path: `/system/health`
(`SYSTEM_HEALTH_PATH`).
Reference: [cheatsheet](cheatsheet.md#system-health).

Larger MikroTiks expose hardware sensors: CPU and board temperatures,
supply voltage, fan RPM, PSU state. A small home router may expose none;
an empty list is not an error.

```jennifer
def sensors as list of mt.HealthSensor init mt.healthSensors($c);
for (def s in $sensors) {
    io.printf("%s: %s %s\n", $s.name, $s.value, $s.kind);
}

def cpu as string init mt.healthValue($c, "cpu-temperature");   # "" when absent
if ($cpu != "") { io.printf("CPU is at %s C\n", $cpu); }
```

- Sensor names and units vary by model; check `healthSensors` on the
  actual hardware before hard-coding a name.
- Values are strings as reported. RouterOS 7 sends one row per sensor
  (`name`, `value`, `type`); older models pack several properties into
  one row, and each becomes a sensor with `kind` `""`.
- Threshold logic is the caller's, or let a monitoring system poll the
  same sensors over [SNMP](snmp.md).
