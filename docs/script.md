<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# Scripts (the repository)

File: `src/topics/script.j`. Path: `/system/script` (`SCRIPT_PATH`).
Reference: [cheatsheet](cheatsheet.md#scripts-the-repository).

`/system/script` stores named scripts. The [scheduler](scheduler.md),
[netwatch](netwatch.md) and `runScript` run a stored script by name, so a
long or reused script lives in one place. The source is RouterOS script,
not Jennifer.

## Examples

Store once, schedule by name:

```jennifer
mt.addScript($c, "nightly", "/system backup save name=nightly", "nightly config backup");
mt.scheduleDaily($c, "run-nightly", "03:00:00", "nightly");
```

Run on demand and read the return value:

```jennifer
mt.addScript($c, "wan-ip", ":put [/ip/cloud/get public-address]", "print the WAN IP");
def ip as string init mt.runScript($c, "wan-ip");
```

Replace the source:

```jennifer
mt.updateScript($c, "nightly", "/system backup save name=nightly password=secret");
```

## Pitfalls

- routeros checks the name and that the source is not empty, nothing
  else. Syntax errors and missing permissions show up in the router log
  at run time. Try one-liners in the RouterOS terminal first.
- A script runs with its own `policy`. A script that reboots or writes
  config needs those policies, and so does the user who creates or runs
  it; without them it does nothing.
- Removing a script breaks scheduler entries that call it by name.
- RouterOS quotes inside the source need `\"` in a Jennifer string.

See also [tools.md](tools.md) (`sendEmail`) and [users.md](users.md)
(policies).
