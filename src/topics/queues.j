# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - simple queues (bandwidth limits) and the queue tree (QoS).
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the simple-queue list (bandwidth limits). */
export def const QUEUE_SIMPLE_PATH as string init "/queue/simple";

/** RouterOS API path of the queue tree (hierarchical QoS). */
export def const QUEUE_TREE_PATH as string init "/queue/tree";

def const RATE_SUFFIX_CHARS as string init "kKmMgG";

/**
 * One simple queue: a bandwidth limit on a target.
 *
 * Upload is traffic from the target, download is traffic to it. Rates
 * are bits/s with an optional k, M or G suffix ("10M", "512k"); "0" is
 * unlimited.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} queue name
 * @field target {string} limited address, network or interface, comma-separated
 * @field maxUpload {string} upload ceiling (e.g. "10M", "0" = unlimited)
 * @field maxDownload {string} download ceiling (e.g. "20M", "0" = unlimited)
 * @field dynamic {bool} true when created by something else (e.g. PPPoE)
 * @field disabled {bool} true when the queue is switched off
 * @field comment {string} comment, "" when unset
 */
export def struct SimpleQueue {
    id as string,
    name as string,
    target as string,
    maxUpload as string,
    maxDownload as string,
    dynamic as bool,
    disabled as bool,
    comment as string
};

/**
 * List the simple queues.
 *
 * @param c {Client} an open client
 * @return {list of SimpleQueue} all simple queues
 */
export func simpleQueues(c as Client) {
    def rows as list of map of string to string init getAll($c, QUEUE_SIMPLE_PATH);
    def out as list of SimpleQueue init [];
    for (def row in $rows) {
        $out[] = simpleQueueFromRow($row);
    }
    return $out;
}

/**
 * Cap the bandwidth of a device, a network or an interface with a
 * simple queue.
 *
 * The target is an IP address ("192.168.88.50"), a network
 * ("192.168.88.0/24"), an interface name, or a comma-separated mix;
 * interface names are checked against the router. Rates are bits/s with
 * an optional k, M or G suffix in any case ("10M", "512k", "2500000");
 * "0" leaves that direction unlimited. Upload is traffic from the
 * target, download is traffic to it.
 *
 * @param c {Client} an open client
 * @param name {string} queue name, the handle for the other simple-queue verbs
 * @param target {string} addresses, networks or interfaces to limit
 * @param upload {string} upload ceiling (e.g. "5M")
 * @param download {string} download ceiling (e.g. "20M")
 * @return {string} the RouterOS id of the new queue
 * @throws {Error} kind "routeros" on a bad name, target or rate, or an
 *         unknown target interface
 * @example
 *   mt.limitBandwidth($c, "guest-wifi", "192.168.90.0/24", "5M", "20M");
 */
export func limitBandwidth(
    c as Client,
    name as string,
    target as string,
    upload as string,
    download as string) {
    ensureName($name, "queue");
    def tgt as string init normalizedQueueTarget($c, $target);
    def maxLimit as string init normalizedRate($upload) + "/" + normalizedRate($download);
    return add($c, QUEUE_SIMPLE_PATH, {"name": $name, "target": $tgt, "max-limit": $maxLimit});
}

/**
 * Change the bandwidth cap of an existing simple queue.
 *
 * @param c {Client} an open client
 * @param name {string} queue name
 * @param upload {string} new upload ceiling (e.g. "10M", "0" = unlimited)
 * @param download {string} new download ceiling
 * @throws {Error} kind "routeros" on a bad rate or an unknown queue
 */
export func setBandwidthLimit(c as Client, name as string, upload as string, download as string) {
    def maxLimit as string init normalizedRate($upload) + "/" + normalizedRate($download);
    set(
        $c,
        QUEUE_SIMPLE_PATH,
        requiredId($c, QUEUE_SIMPLE_PATH, $name, "simple queue"),
        {"max-limit": $maxLimit});
}

/**
 * Delete a simple queue: the target's bandwidth is no longer limited.
 *
 * @param c {Client} an open client
 * @param name {string} queue name
 * @throws {Error} kind "routeros" when no queue has that name
 */
export func removeSimpleQueue(c as Client, name as string) {
    remove($c, QUEUE_SIMPLE_PATH, requiredId($c, QUEUE_SIMPLE_PATH, $name, "simple queue"));
}

/**
 * Switch a simple queue on.
 *
 * @param c {Client} an open client
 * @param name {string} queue name
 * @throws {Error} kind "routeros" when no queue has that name
 */
export func enableSimpleQueue(c as Client, name as string) {
    enable($c, QUEUE_SIMPLE_PATH, requiredId($c, QUEUE_SIMPLE_PATH, $name, "simple queue"));
}

/**
 * Switch a simple queue off; the limit pauses until enabled again.
 *
 * @param c {Client} an open client
 * @param name {string} queue name
 * @throws {Error} kind "routeros" when no queue has that name
 */
export func disableSimpleQueue(c as Client, name as string) {
    disable($c, QUEUE_SIMPLE_PATH, requiredId($c, QUEUE_SIMPLE_PATH, $name, "simple queue"));
}

/**
 * Validate and normalize one rate.
 *
 * Accepts digits with an optional single k, M or G suffix in any case,
 * whitespace trimmed, and spells the suffix the RouterOS way (k, M, G).
 * "0" is valid and means unlimited.
 *
 * @param rate {string} candidate rate (e.g. "10M", "512k", "2500000")
 * @return {string} the normalized rate
 * @throws {Error} kind "routeros" on anything else
 * @internal
 */
func normalizedRate(rate as string) {
    def r as string init strings.trim($rate);
    if ($r == "") {
        raiseError("the rate must not be empty - write it like \"10M\" or \"512k\"");
    }
    def digits as string init "";
    def suffix as string init "";
    def chars as list of string init strings.chars($r);
    for (def ch in $chars) {
        if (strings.contains(DIGIT_CHARS, $ch)) {
            if ($suffix != "") {
                raiseError("\"" + $rate +
                    "\" is not a rate - digits must come before the k/M/G suffix");
            }
            $digits = $digits + $ch;
        } elseif (strings.contains(RATE_SUFFIX_CHARS, $ch)) {
            if ($suffix != "" or $digits == "") {
                raiseError("\"" + $rate + "\" is not a rate - write it like \"10M\" or \"512k\"");
            }
            $suffix = $ch;
        } else {
            raiseError("\"" + $rate + "\" is not a rate - write it like \"10M\" or \"512k\"");
        }
    }
    if ($digits == "") {
        raiseError("\"" + $rate + "\" is not a rate - write it like \"10M\" or \"512k\"");
    }
    match ($suffix) {
        when "k", "K" { $suffix = "k"; }
        when "m", "M" { $suffix = "M"; }
        when "g", "G" { $suffix = "G"; }
    }
    return $digits + $suffix;
}

/**
 * Split a RouterOS "max-limit" pair into its halves.
 *
 * "10M/20M" -> upload "10M", download "20M". A value without a slash
 * counts for both directions; "" stays "".
 *
 * @param maxLimit {string} the reported "max-limit" value
 * @return {list of string} two elements: upload, download
 * @internal
 */
func rateHalves(maxLimit as string) {
    def out as list of string init [];
    if (strings.contains($maxLimit, "/")) {
        def parts as list of string init strings.split($maxLimit, "/");
        $out[] = $parts[0];
        $out[] = $parts[1];
    } else {
        $out[] = $maxLimit;
        $out[] = $maxLimit;
    }
    return $out;
}

/**
 * Classify one queue-target entry.
 *
 * @param entry {string} one target, no commas
 * @return {string} "cidr", "address", or "name"
 * @throws {Error} kind "routeros" on a malformed CIDR or an empty or
 *         spaced name
 * @internal
 */
func targetKind(entry as string) {
    if (strings.contains($entry, "/")) {
        ensureCidr($entry);
        return "cidr";
    }
    if (isIpAddress($entry)) {
        return "address";
    }
    ensureName($entry, "queue target");
    return "name";
}

/**
 * Validate and normalize a queue target list; interface-name entries
 * are checked against the router.
 *
 * @param c {Client} an open client
 * @param target {string} address, CIDR and interface entries, comma-separated
 * @return {string} the normalized target list
 * @throws {Error} kind "routeros" on an empty entry, a malformed
 *         address or an unknown interface
 * @internal
 */
func normalizedQueueTarget(c as Client, target as string) {
    def parts as list of string init strings.split($target, ",");
    def ifaceRows as list of map of string to string init getAll($c, INTERFACE_PATH);
    def out as list of string init [];
    for (def part in $parts) {
        def p as string init strings.trim($part);
        if ($p == "") {
            raiseError("the queue target \"" + $target + "\" must not contain empty entries");
        }
        if (targetKind($p) == "name" and len(findRowByField($ifaceRows, "name", $p)) == 0) {
            raiseError("the queue target interface \"" + $p + "\" was not found on the router");
        }
        $out[] = $p;
    }
    return strings.join($out, ",");
}

/**
 * Fold a reply row into a SimpleQueue.
 *
 * @param row {map of string to string} a "/queue/simple/print" row
 * @return {SimpleQueue} the typed queue
 * @internal
 */
func simpleQueueFromRow(row as map of string to string) {
    def halves as list of string init rateHalves(rowValue($row, "max-limit"));
    return SimpleQueue{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        target: rowValue($row, "target"),
        maxUpload: $halves[0],
        maxDownload: $halves[1],
        dynamic: rowBool($row, "dynamic"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}

/**
 * One queue-tree node: a branch of the QoS hierarchy.
 *
 * @field id {string} internal RouterOS id
 * @field name {string} node name
 * @field parent {string} an interface, "global", or another node's name
 * @field packetMark {string} mangle packet mark(s) served, "" on inner nodes
 * @field limitAt {string} guaranteed rate ("" = none)
 * @field maxLimit {string} ceiling rate ("" = unlimited)
 * @field priority {int} 1 (first served) to 8 (last), 0 when unset
 * @field disabled {bool} true when switched off
 * @field comment {string} comment, "" when unset
 */
export def struct TreeQueue {
    id as string,
    name as string,
    parent as string,
    packetMark as string,
    limitAt as string,
    maxLimit as string,
    priority as int,
    disabled as bool,
    comment as string
};

/**
 * List the queue tree.
 *
 * @param c {Client} an open client
 * @return {list of TreeQueue} all nodes
 */
export func treeQueues(c as Client) {
    def rows as list of map of string to string init getAll($c, QUEUE_TREE_PATH);
    def out as list of TreeQueue init [];
    for (def row in $rows) {
        $out[] = treeQueueFromRow($row);
    }
    return $out;
}

/**
 * Create the root of a QoS hierarchy.
 *
 * Set `maxLimit` slightly below the real line rate (e.g. "95M" on a
 * 100M line) so packets queue here, where the tree can order them, and
 * not in the modem. Children share that budget. When a node of that
 * name exists, its id is returned and nothing is changed.
 *
 * @param c {Client} an open client
 * @param name {string} root name (e.g. "qosdown")
 * @param parent {string} interface whose egress is shaped ("pppoewan"
 *        shapes upload, "brlan" download), or "global"
 * @param maxLimit {string} total budget (e.g. "95M")
 * @return {string} the RouterOS id of the root node
 * @throws {Error} kind "routeros" on a bad name or rate, or an unknown interface
 * @example
 *   mt.addQueueTreeRoot($c, "qosup", "pppoewan", "38M");
 */
export func addQueueTreeRoot(c as Client, name as string, parent as string, maxLimit as string) {
    ensureName($name, "queue tree node");
    def target as string init strings.trim($parent);
    if ($target != "global") {
        requiredId($c, INTERFACE_PATH, $target, "interface");
    }
    def ceiling as string init normalizedRate($maxLimit);
    def existing as string init idByName($c, QUEUE_TREE_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    return add($c, QUEUE_TREE_PATH, {"name": $name, "parent": $target, "max-limit": $ceiling});
}

/**
 * Add a traffic class under a tree node.
 *
 * The class serves one packet mark, set by a mangle rule (see
 * `setupPacketMark`). A mark no mangle rule sets is refused: the class
 * would match nothing, silently. `limitAt` is the guaranteed share when
 * the line is full, `maxLimit` the ceiling when it is not, and
 * `priority` decides between siblings (1 first). When a node of that
 * name exists, its id is returned and nothing is changed.
 *
 * @param c {Client} an open client
 * @param name {string} class name (e.g. "qosupvoip")
 * @param parentName {string} tree node above it (e.g. the root)
 * @param packetMark {string} mangle packet mark to serve
 * @param limitAt {string} guaranteed rate (e.g. "5M"; "0" for none)
 * @param maxLimit {string} ceiling rate (e.g. "38M" for the whole line)
 * @param priority {int} 1 to 8, lower is served first
 * @return {string} the RouterOS id of the class
 * @throws {Error} kind "routeros" on a bad name, mark, rate or priority,
 *         an unknown parent node, or a mark no mangle rule sets
 * @example
 *   mt.addQueueTreeChild($c, "qosupvoip", "qosup", "voip", "5M", "38M", 1);
 *   mt.addQueueTreeChild($c, "qosuprest", "qosup", "bulk", "10M", "38M", 8);
 */
export func addQueueTreeChild(
    c as Client,
    name as string,
    parentName as string,
    packetMark as string,
    limitAt as string,
    maxLimit as string,
    priority as int) {
    ensureName($name, "queue tree node");
    ensureName($packetMark, "packet mark");
    ensureTreePriority($priority);
    requiredId($c, QUEUE_TREE_PATH, $parentName, "queue tree node");
    def mangleRows as list of map of string to string init getAll($c, MANGLE_PATH);
    def marker as map of string to string init findRowByField(
        $mangleRows,
        "new-packet-mark",
        $packetMark);
    if (len($marker) == 0) {
        raiseError("no mangle rule creates the packet mark \"" + $packetMark +
            "\" - set it up first (setupPacketMark)");
    }
    def guaranteed as string init normalizedRate($limitAt);
    def ceiling as string init normalizedRate($maxLimit);
    def existing as string init idByName($c, QUEUE_TREE_PATH, $name);
    if ($existing != "") {
        return $existing;
    }
    return add(
        $c,
        QUEUE_TREE_PATH,
        {
            "name": $name,
            "parent": $parentName,
            "packet-mark": $packetMark,
            "limit-at": $guaranteed,
            "max-limit": $ceiling,
            "priority": convert.toString($priority)
        });
}

/**
 * Remove a tree node and every node below it, children first.
 *
 * @param c {Client} an open client
 * @param name {string} node name; the root removes the whole tree
 * @throws {Error} kind "routeros" when no tree node has that name
 */
export func removeTreeQueue(c as Client, name as string) {
    def rows as list of map of string to string init getAll($c, QUEUE_TREE_PATH);
    def ids as list of string init treeQueueFamily($rows, $name);
    if (len($ids) == 0) {
        raiseError("no queue tree node named \"" + $name + "\" was found");
    }
    for (def id in $ids) {
        remove($c, QUEUE_TREE_PATH, $id);
    }
}

/**
 * Switch a tree node on.
 *
 * @param c {Client} an open client
 * @param name {string} node name
 * @throws {Error} kind "routeros" when no tree node has that name
 */
export func enableTreeQueue(c as Client, name as string) {
    enable($c, QUEUE_TREE_PATH, requiredId($c, QUEUE_TREE_PATH, $name, "queue tree node"));
}

/**
 * Switch a tree node off (its subtree stops shaping).
 *
 * @param c {Client} an open client
 * @param name {string} node name
 * @throws {Error} kind "routeros" when no tree node has that name
 */
export func disableTreeQueue(c as Client, name as string) {
    disable($c, QUEUE_TREE_PATH, requiredId($c, QUEUE_TREE_PATH, $name, "queue tree node"));
}

/**
 * Validate a queue-tree priority.
 *
 * @param priority {int} candidate priority
 * @throws {Error} kind "routeros" when outside 1-8
 * @internal
 */
func ensureTreePriority(priority as int) {
    if ($priority < 1 or $priority > 8) {
        raiseError("the priority must be between 1 (served first) and 8 (served last)");
    }
}

/**
 * Collect the ids of a node and its descendants, children before parents.
 *
 * @param rows {list of map of string to string} "/queue/tree/print" rows
 * @param name {string} top node name
 * @return {list of string} ids in safe removal order; empty when the
 *         name matches nothing
 * @internal
 */
func treeQueueFamily(rows as list of map of string to string, name as string) {
    def names as list of string init [$name];
    def grew as bool init true;
    while ($grew) {
        $grew = false;
        for (def row in $rows) {
            def rowName as string init rowValue($row, "name");
            if ($rowName != "" and lists.contains($names, rowValue($row, "parent")) and
                not lists.contains($names, $rowName)) {
                $names[] = $rowName;
                $grew = true;
            }
        }
    }
    def ids as list of string init [];
    for (def i as int init len($names) - 1; $i >= 0; $i = $i - 1) {
        for (def row in $rows) {
            if (rowValue($row, "name") == $names[$i]) {
                $ids[] = rowValue($row, ".id");
            }
        }
    }
    return $ids;
}

/**
 * Fold a reply row into a TreeQueue.
 *
 * @param row {map of string to string} a "/queue/tree/print" row
 * @return {TreeQueue} the typed node
 * @internal
 */
func treeQueueFromRow(row as map of string to string) {
    return TreeQueue{
        id: rowValue($row, ".id"),
        name: rowValue($row, "name"),
        parent: rowValue($row, "parent"),
        packetMark: rowValue($row, "packet-mark"),
        limitAt: rowValue($row, "limit-at"),
        maxLimit: rowValue($row, "max-limit"),
        priority: rowInt($row, "priority"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
