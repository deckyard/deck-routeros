# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - the router log: reading entries, routing what gets logged.
# Spliced into routeros.j via include - not a standalone module.

/**
 * RouterOS API path of the log entries. The rules that decide what is
 * logged where are under LOGGING_PATH.
 */
export def const LOG_PATH as string init "/log";

/** RouterOS API path of the logging rules (topic -> action). */
export def const LOGGING_PATH as string init "/system/logging";

/** RouterOS API path of the logging actions (memory, disk, echo, remote). */
export def const LOGGING_ACTION_PATH as string init "/system/logging/action";

/**
 * One log entry.
 *
 * @field id {string} RouterOS item id
 * @field time {string} time as RouterOS prints it, e.g. "15:33:02"; older
 *        entries carry a date prefix
 * @field topics {string} comma-separated topics, e.g. "system,info"
 * @field message {string} the log line
 */
export def struct LogEntry {
    id as string,
    time as string,
    topics as string,
    message as string
};

/**
 * One logging rule: which topics go to which action.
 *
 * @field id {string} RouterOS item id
 * @field topics {string} comma-separated topics matched, e.g. "info,!dns"
 * @field action {string} "memory", "disk", "echo", "remote", or a custom action
 * @field prefix {string} text prepended to each entry, "" when unset
 * @field disabled {bool} whether the rule is switched off
 */
export def struct LoggingRule {
    id as string,
    topics as string,
    action as string,
    prefix as string,
    disabled as bool
};

/**
 * Read the in-memory log buffer, oldest first.
 *
 * The buffer holds 1000 entries by default and is cleared on reboot.
 * For history, log to disk or remote (`setupRemoteLogging`).
 *
 * @param c {Client} an open client
 * @return {list of LogEntry} the buffered entries
 */
export func logEntries(c as Client) {
    def rows as list of map of string to string init getAll($c, LOG_PATH);
    def out as list of LogEntry init [];
    for (def row in $rows) {
        $out[] = logEntryFromRow($row);
    }
    return $out;
}

/**
 * Read the newest `count` log entries, oldest of them first.
 *
 * @param c {Client} an open client
 * @param count {int} number of entries from the end of the log, at least 1
 * @return {list of LogEntry} at most `count` entries
 * @throws {Error} kind "routeros" on a count below 1
 */
export func recentLogEntries(c as Client, count as int) {
    if ($count < 1) {
        raiseError("the entry count must be at least 1");
    }
    return lastEntries(logEntries($c), $count);
}

/**
 * Read the log entries carrying one topic, matched as an exact word.
 *
 * @param c {Client} an open client
 * @param topic {string} topic such as "firewall", "dhcp", "wireless"
 * @return {list of LogEntry} matching entries, oldest first
 */
export func logEntriesWithTopic(c as Client, topic as string) {
    def all as list of LogEntry init logEntries($c);
    def out as list of LogEntry init [];
    for (def entry in $all) {
        if (logHasTopic($entry.topics, $topic)) {
            $out[] = $entry;
        }
    }
    return $out;
}

/**
 * Read the log entries with topic "error" or "critical".
 *
 * @param c {Client} an open client
 * @return {list of LogEntry} the problem entries, oldest first
 */
export func logErrors(c as Client) {
    def all as list of LogEntry init logEntries($c);
    def out as list of LogEntry init [];
    for (def entry in $all) {
        if (isProblemTopics($entry.topics)) {
            $out[] = $entry;
        }
    }
    return $out;
}

/**
 * List the logging rules: which topics are logged where.
 *
 * @param c {Client} an open client
 * @return {list of LoggingRule} every rule
 */
export func loggingRules(c as Client) {
    def rows as list of map of string to string init getAll($c, LOGGING_PATH);
    def out as list of LoggingRule init [];
    for (def row in $rows) {
        $out[] = loggingRuleFromRow($row);
    }
    return $out;
}

/**
 * Send the given topics to a logging action.
 *
 * Topics are RouterOS categories ("firewall", "dhcp") and severities
 * ("info", "warning", "error"), comma-separated, "!" negates:
 * "info,!dns". The action must exist on the router; the built-ins are
 * "memory", "disk", "echo" and "remote". Idempotent: a rule with the
 * same normalized topics and action is reused.
 *
 * @param c {Client} an open client
 * @param topics {string} comma-separated topics to match
 * @param action {string} name of the logging action
 * @return {string} the RouterOS id of the new or existing rule
 * @throws {Error} kind "routeros" on a malformed topics list or an
 *         unknown action
 * @example
 *   mt.addLoggingRule($c, "firewall", "disk");
 */
export func addLoggingRule(c as Client, topics as string, action as string) {
    def wanted as string init normalizedLogTopics($topics);
    requiredId($c, LOGGING_ACTION_PATH, $action, "logging action");
    def rows as list of map of string to string init getAll($c, LOGGING_PATH);
    def existing as map of string to string init findLoggingRow($rows, $wanted, $action);
    if (len($existing) > 0) {
        return rowValue($existing, ".id");
    }
    return add($c, LOGGING_PATH, {"topics": $wanted, "action": $action});
}

/**
 * Remove the logging rule that sends exactly these topics to an action.
 *
 * Topics are compared after normalization and in order: "info,error"
 * does not match a rule for "error,info".
 *
 * @param c {Client} an open client
 * @param topics {string} the rule's topics, as given to `addLoggingRule`
 * @param action {string} the rule's action
 * @throws {Error} kind "routeros" on a malformed topics list or when no
 *         such rule exists
 */
export func removeLoggingRule(c as Client, topics as string, action as string) {
    def wanted as string init normalizedLogTopics($topics);
    def rows as list of map of string to string init getAll($c, LOGGING_PATH);
    def row as map of string to string init findLoggingRow($rows, $wanted, $action);
    if (len($row) == 0) {
        raiseError("no logging rule sends \"" + $wanted + "\" to \"" + $action + "\"");
    }
    remove($c, LOGGING_PATH, rowValue($row, ".id"));
}

/**
 * Send the log to a remote syslog server over UDP.
 *
 * Points the built-in "remote" action at the server, replacing any
 * earlier target, and routes the given topics to it. Idempotent. The
 * memory log keeps working alongside.
 *
 * @param c {Client} an open client
 * @param address {string} syslog server IP address
 * @param port {int} UDP port, 514 for standard syslog
 * @param topics {string} topics to send, e.g. "info,warning,error,critical"
 * @return {string} the RouterOS id of the logging rule
 * @throws {Error} kind "routeros" on a malformed address, port or topics
 * @example
 *   mt.setupRemoteLogging($c, "192.168.88.40", 514, "info,warning,error,critical");
 */
export func setupRemoteLogging(c as Client, address as string, port as int, topics as string) {
    ensureIpAddress($address);
    ensurePort($port);
    def actionId as string init requiredId($c, LOGGING_ACTION_PATH, "remote", "logging action");
    set(
        $c,
        LOGGING_ACTION_PATH,
        $actionId,
        {"remote": strings.trim($address), "remote-port": convert.toString($port)});
    return addLoggingRule($c, $topics, "remote");
}

/**
 * Return the last `count` elements of an entry list.
 *
 * @param entries {list of LogEntry} the full list, oldest first
 * @param count {int} number of entries from the end, already validated >= 1
 * @return {list of LogEntry} the tail, order preserved
 * @internal
 */
func lastEntries(entries as list of LogEntry, count as int) {
    if (len($entries) <= $count) {
        return $entries;
    }
    return $entries[len($entries) - $count..];
}

/**
 * Test whether a comma-separated topic list contains one topic.
 *
 * @param topicsCsv {string} the entry's topics, e.g. "system,info"
 * @param topic {string} the topic to look for, as an exact word
 * @return {bool} true when present
 * @internal
 */
func logHasTopic(topicsCsv as string, topic as string) {
    def parts as list of string init strings.split($topicsCsv, ",");
    for (def part in $parts) {
        if (strings.trim($part) == $topic) {
            return true;
        }
    }
    return false;
}

/**
 * Test whether a topic list marks a problem entry.
 *
 * @param topicsCsv {string} the entry's topics
 * @return {bool} true on "error" or "critical"
 * @internal
 */
func isProblemTopics(topicsCsv as string) {
    return logHasTopic($topicsCsv, "error") or logHasTopic($topicsCsv, "critical");
}

/**
 * Validate and normalize a logging-topics list.
 *
 * Each entry must be non-empty and contain no space ("!"-negation such
 * as "info,!dns" passes through); spaces around commas are removed.
 * Case and topic names are not checked.
 *
 * @param csv {string} the candidate list
 * @return {string} the normalized list
 * @throws {Error} kind "routeros" on an empty entry or one containing a space
 * @internal
 */
func normalizedLogTopics(csv as string) {
    def parts as list of string init strings.split($csv, ",");
    def out as list of string init [];
    for (def part in $parts) {
        def p as string init strings.trim($part);
        if ($p == "") {
            raiseError("the topics list \"" + $csv + "\" must not contain empty entries");
        }
        if (strings.contains($p, " ")) {
            raiseError("the topic \"" + $p +
                "\" must be a single word (e.g. \"firewall\", \"info\", \"!dns\")");
        }
        $out[] = $p;
    }
    if (len($out) == 0) {
        raiseError("the topics list must contain at least one topic");
    }
    return strings.join($out, ",");
}

/**
 * Find the rule matching a normalized topics list and an action.
 *
 * @param rows {list of map of string to string} "/system/logging/print" rows
 * @param topics {string} the normalized topics list
 * @param action {string} the action name
 * @return {map of string to string} the matching row, or an empty map
 * @internal
 */
func findLoggingRow(rows as list of map of string to string, topics as string, action as string) {
    for (def row in $rows) {
        if (rowValue($row, "topics") == $topics and rowValue($row, "action") == $action) {
            return $row;
        }
    }
    def none as map of string to string init {};
    return $none;
}

/**
 * Fold a "/log/print" row into a LogEntry.
 *
 * @param row {map of string to string} the reply row
 * @return {LogEntry} the typed entry
 * @internal
 */
func logEntryFromRow(row as map of string to string) {
    return LogEntry{
        id: rowValue($row, ".id"),
        time: rowValue($row, "time"),
        topics: rowValue($row, "topics"),
        message: rowValue($row, "message")
    };
}

/**
 * Fold a "/system/logging/print" row into a LoggingRule.
 *
 * @param row {map of string to string} the reply row
 * @return {LoggingRule} the typed rule
 * @internal
 */
func loggingRuleFromRow(row as map of string to string) {
    return LoggingRule{
        id: rowValue($row, ".id"),
        topics: rowValue($row, "topics"),
        action: rowValue($row, "action"),
        prefix: rowValue($row, "prefix"),
        disabled: rowBool($row, "disabled")
    };
}
