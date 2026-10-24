# Management services

File: `src/topics/services.j`. Path: `/ip/service` (`SERVICE_PATH`).
Reference: [cheatsheet](cheatsheet.md#management-services).

`/ip/service` is the fixed list of ways into the router: `api` and
`api-ssl` (what the deck connects through), `ssh`, `winbox`, `www` and
`www-ssl` (WebFig), and the cleartext `telnet` and `ftp`. Services are
enabled, disabled, moved and restricted, never added or removed. Names
are checked against that list locally; a typo fails with the valid names
in the message.

Unrestricted services listen on every address, the WAN included: a fresh
router answers WinBox from the internet. Restrict them here, block them
in the input chain ([firewall.md](firewall.md)), or both.

```jennifer
mt.disableInsecureServices($c);                       # telnet and ftp; returns the count
mt.restrictService($c, "winbox", "10.0.9.0/24");
mt.restrictService($c, "ssh", "10.0.9.0/24");
mt.restrictService($c, "api-ssl", "10.0.9.0/24");
mt.disableService($c, "www");                         # WebFig over TLS only
mt.setServicePort($c, "ssh", 2200);                   # refused if another service uses 2200

def svcs as list of mt.Service init mt.services($c);
for (def s in $svcs) {
    if (not $s.disabled and $s.address == "") {
        io.printf("open to the world: %s on port %d\n", $s.name, $s.port);
    }
}
```

## Notes

- Disabling or mis-restricting the API service this session uses
  disconnects it; if it was the only way in, recovery needs a serial
  cable. Change `api` from an `api-ssl` session and the other way round,
  and check that winbox or ssh works first.
- `restrictService` applies to new connections. The current session
  survives a mistake, so test a fresh connection before logging out.
- `invalid` true (typically `api-ssl` or `www-ssl` without a
  certificate) means enabled but not listening. Fix it with
  `assignServiceCertificate` ([certificates.md](certificates.md)).
- A non-default port cuts scanner noise; the address restriction is
  what protects.
- MAC-WinBox and MAC-Telnet (`/tool/mac-server`, generic verbs) are
  separate LAN-only ways in that ignore these settings.
- `restrictUser` ([users.md](users.md)) is the per-account equivalent.
