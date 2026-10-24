# SNMP

File: `src/topics/snmp.j`. Paths: `/snmp` (`SNMP_PATH`),
`/snmp/community` (`SNMP_COMMUNITY_PATH`).
Reference: [cheatsheet](cheatsheet.md#snmp).

Monitoring systems (Zabbix, LibreNMS, PRTG, Observium) read interface
counters, CPU, memory and temperatures over SNMP. Access is granted per
*community*, a shared string that works as a password and, in v2c,
crosses the wire in cleartext. `enableSnmp` therefore always creates a
read-only community, restricted to the sources you pass.

```jennifer
mt.enableSnmp($c, "mon4711", "10.0.9.0/24");
mt.setSnmpInfo($c, "noc@example.org", "rack 3, office Berlin");
```

Some configurations ship the default `public` community enabled. Close
it, and flag any community with write access:

```jennifer
def coms as list of mt.SnmpCommunity init mt.snmpCommunities($c);
for (def com in $coms) {
    if ($com.name == "public" and not $com.disabled) {
        mt.disable($c, mt.SNMP_COMMUNITY_PATH, $com.id);
    }
    if ($com.writeAccess) {
        io.printf("WARNING: community %s has write access\n", $com.name);
    }
}
```

Keep SNMP off the WAN: pass `addresses`, and add a firewall rule for
UDP 161 ([firewall.md](firewall.md)). SNMPv3 with authentication is not
wrapped; configure it with the generic verbs. An API account in the
`read` group ([users.md](users.md)) is an alternative to SNMP for
monitoring.

If bandwidth graphs show zeros after interface changes, check that the
monitoring system still polls the right ifIndex.
