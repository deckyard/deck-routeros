# The router log

File: `src/topics/log.j`. Paths: `/log` (`LOG_PATH`), `/system/logging`
(`LOGGING_PATH`), `/system/logging/action` (`LOGGING_ACTION_PATH`).
Reference: [cheatsheet](cheatsheet.md#the-router-log).

The entries live under `/log`, by default an in-memory ring buffer of
1000 lines that a reboot clears. The rules under `/system/logging` send
topics (categories such as `firewall`, `dhcp`, `wireless`, and
severities `info`, `warning`, `error`, `critical`) to actions: `memory`
(the buffer), `disk`, `echo` (console) or `remote` (syslog). Each entry
carries its topics as a comma list (`"system,info"`); the filter helpers
match on whole words from that list.

Topic lists passed to the rule calls are normalized (spaces around commas
removed, `!` negation passed through) and rejected when an entry is empty
or contains a space. Actions are looked up on the router, so custom
actions work.

## Examples

Problems in the buffer:

```jennifer
def problems as list of mt.LogEntry init mt.logErrors($c);
for (def e in $problems) {
    io.printf("%s [%s] %s\n", $e.time, $e.topics, $e.message);
}
```

The last 20 lines, and one subsystem:

```jennifer
def tail as list of mt.LogEntry init mt.recentLogEntries($c, 20);
def dhcp as list of mt.LogEntry init mt.logEntriesWithTopic($c, "dhcp");
```

Firewall history on disk, everything important to a syslog server:

```jennifer
mt.addLoggingRule($c, "firewall", "disk");
mt.setupRemoteLogging($c, "192.168.88.40", 514, "info,warning,error,critical");
```

## Pitfalls

- The memory buffer is small and a chatty topic pushes the interesting
  lines out; a reboot clears it. For history use `disk` or `remote`.
- Disk logging writes flash on most MikroTik devices. On small devices
  send heavy topics to `remote` and keep `disk` for rare, important ones.
- Topic filters match exact words: `"fire"` matches nothing, `"firewall"`
  does. Firewall rules log only when the rule's own log flag is set
  (generic `set` with `"log": "yes"`).
- `removeLoggingRule` compares the topic list in order: a rule for
  `"error,info"` is not found as `"info,error"`.
- `setupRemoteLogging` repoints the built-in `remote` action. If it
  already sends to another server, that server stops receiving; check
  `loggingRules(c)` on a shared router first.
- Remote syslog is plain UDP: fine on a management LAN, not across the
  internet.

See also [users.md](users.md) (logins appear as `system,info`) and
[scheduler.md](scheduler.md) (failed tasks are logged).
