# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - a scripted RouterOS API peer for the verb tests.
# Spliced into routeros_test.j via include - not a standalone module.
#
# The fake listens on a loopback port, accepts one plain-API connection,
# answers `/login`, `<path>/print` (with `?` query words and `.proplist`),
# `<path>/add` (ret `*F1`, `*F2`, ...) and every other command with `!done`,
# and records each sentence it reads. A test starts it, connects a client,
# calls the verb, then `fakeLog` disconnects and returns the sentences, each
# as its words joined with one space ("/ip/arp/remove =.id=*1").
#
#   def f as Fake init fakeStart(fakeWithRows(fakeRouter(), ARP_PATH, [...]));
#   def c as Client init fakeClient($f);
#   removeArpEntry($c, "10.0.0.5");
#   def log as list of string init fakeLog($c, $f);

# The script: rows per list path, traps per command, commands that drop the
# connection.
def struct FakeRouter {
    rows as map of string to list of map of string to string,
    trapCategories as map of string to string,
    trapMessages as map of string to string,
    closeOn as list of string
};

# A running fake: its listener, the serving task and the bound port.
def struct Fake {
    listener as net.Listener,
    server as task of list of string,
    port as int
};

# Idle limit of the fake's reads, so a test that never disconnects still ends.
def const FAKE_IDLE_MS as int init 5000;

func fakeRouter() {
    def rows as map of string to list of map of string to string init {};
    def texts as map of string to string init {};
    return FakeRouter{rows: $rows, trapCategories: $texts, trapMessages: $texts, closeOn: []};
}

func fakeWithRows(r as FakeRouter, path as string, rows as list of map of string to string) {
    $r.rows[$path] = $rows;
    return $r;
}

func fakeWithTrap(r as FakeRouter, command as string, category as string, message as string) {
    $r.trapCategories[$command] = $category;
    $r.trapMessages[$command] = $message;
    return $r;
}

func fakeWithClose(r as FakeRouter, command as string) {
    $r.closeOn[] = $command;
    return $r;
}

func fakeStart(r as FakeRouter) {
    def l as net.Listener init net.listen("127.0.0.1:0");
    def addr as string init net.address($l);
    def port as int init convert.toInt($addr[strings.lastIndexOf($addr, ":") + 1..]);
    def t as task of list of string init spawn {
        return fakeServe($l, $r);
    };
    return Fake{listener: $l, server: $t, port: $port};
}

func fakeClient(f as Fake) {
    return connectWith("127.0.0.1", $f.port, "admin", "pw", false, true);
}

func fakeLog(c as Client, f as Fake) {
    try {
        disconnect($c);
    } catch (e) { # lint-disable: L103
        # The fake may have dropped the connection on purpose (fakeWithClose).
    }
    def log as list of string init task.wait($f.server);
    net.close($f.listener);
    return $log;
}

# Did the fake see a sentence starting with `prefix`?
func fakeSaw(log as list of string, prefix as string) {
    for (def s in $log) {
        if (strings.startsWith($s, $prefix)) {
            return true;
        }
    }
    return false;
}

func fakeServe(l as net.Listener, r as FakeRouter) {
    def conn as net.Conn init net.accept($l);
    net.setIdleTimeout($conn, FAKE_IDLE_MS);
    def log as list of string init [];
    def next as int init 0;
    while (true) {
        def words as list of string init [];
        try {
            $words = fakeReadSentence($conn);
        } catch (e) {
            if ($e.kind != "timeout" and $e.kind != "closed") {
                throw $e;
            }
        }
        if (len($words) == 0) {
            net.close($conn);
            return $log;
        }
        $log[] = strings.join($words, " ");
        def cmd as string init $words[0];
        if (lists.contains($r.closeOn, $cmd)) {
            net.close($conn);
            return $log;
        }
        if (maps.has($r.trapMessages, $cmd)) {
            def trap as list of string init ["!trap", "=message=" + $r.trapMessages[$cmd]];
            if ($r.trapCategories[$cmd] != "") {
                $trap[] = "=category=" + $r.trapCategories[$cmd];
            }
            fakeWrite($conn, $trap);
            fakeWrite($conn, ["!done"]);
        } elseif (strings.endsWith($cmd, "/print")) {
            def path as string init $cmd[..len($cmd) - 6];
            def rows as list of map of string to string init [];
            if (maps.has($r.rows, $path)) {
                $rows = $r.rows[$path];
            }
            for (def row in fakeSelect($rows, $words)) {
                def out as list of string init ["!re"];
                for (def k in maps.keys($row)) {
                    $out[] = "=" + $k + "=" + $row[$k];
                }
                fakeWrite($conn, $out);
            }
            fakeWrite($conn, ["!done"]);
        } elseif (strings.endsWith($cmd, "/add")) {
            $next = $next + 1;
            fakeWrite($conn, ["!done", "=ret=*F" + convert.toString($next)]);
        } else {
            fakeWrite($conn, ["!done"]);
        }
    }
    return $log;
}

# The rows a print returns: filtered by its `?` words (RPN, as RouterOS
# evaluates them) and cut to its `.proplist`.
func fakeSelect(rows as list of map of string to string, words as list of string) {
    def props as list of string init [];
    def queries as list of string init [];
    for (def w in $words) {
        if (strings.startsWith($w, "=.proplist=")) {
            $props = strings.split($w[11..], ",");
        } elseif (strings.startsWith($w, "?")) {
            $queries[] = $w[1..];
        }
    }
    def out as list of map of string to string init [];
    for (def row in $rows) {
        if (fakeMatches($row, $queries)) {
            if (len($props) == 0) {
                $out[] = $row;
            } else {
                def cut as map of string to string init {};
                for (def p in $props) {
                    if (maps.has($row, $p)) {
                        $cut[$p] = $row[$p];
                    }
                }
                $out[] = $cut;
            }
        }
    }
    return $out;
}

func fakeMatches(row as map of string to string, queries as list of string) {
    def stack as list of bool init [];
    for (def q in $queries) {
        if ($q == "#|" or $q == "#&") {
            def b as bool init $stack[len($stack) - 1];
            def a as bool init $stack[len($stack) - 2];
            $stack = $stack[..len($stack) - 2];
            if ($q == "#|") {
                $stack[] = $a or $b;
            } else {
                $stack[] = $a and $b;
            }
        } elseif ($q == "#!") {
            def top as bool init $stack[len($stack) - 1];
            $stack[len($stack) - 1] = not $top;
        } elseif (strings.startsWith($q, "-")) {
            $stack[] = not maps.has($row, $q[1..]);
        } elseif (strings.contains($q, "=")) {
            def at as int init strings.indexOf($q, "=");
            def key as string init $q[..$at];
            $stack[] = maps.has($row, $key) and $row[$key] == $q[$at + 1..];
        } else {
            $stack[] = maps.has($row, $q);
        }
    }
    for (def ok in $stack) {
        if (not $ok) {
            return false;
        }
    }
    return true;
}

func fakeReadSentence(conn as net.Conn) {
    def words as list of string init [];
    while (true) {
        def head as bytes init net.readBytes($conn, 1);
        if (len($head) == 0) {
            return [];
        }
        def n as int init fakeLength($conn, $head[0]);
        if ($n == 0) {
            return $words;
        }
        $words[] = encoding.decode("utf-8", net.readN($conn, $n));
    }
    return $words;
}

func fakeLength(conn as net.Conn, first as int) {
    if ($first < 0x80) {
        return $first;
    }
    def extra as int init 1;
    def value as int init $first & 0x3F;
    if ($first >= 0xE0) {
        $extra = 3;
        $value = $first & 0x0F;
    } elseif ($first >= 0xC0) {
        $extra = 2;
        $value = $first & 0x1F;
    }
    def rest as bytes init net.readN($conn, $extra);
    for (def b in $rest) {
        $value = ($value << 8) | $b;
    }
    return $value;
}

func fakeWrite(conn as net.Conn, words as list of string) {
    def out as bytes;
    for (def w in $words) {
        def b as bytes init encoding.encode("utf-8", $w);
        def n as int init len($b);
        if ($n < 0x80) {
            $out[] = $n;
        } elseif ($n < 0x4000) {
            $out[] = ($n >> 8) | 0x80;
            $out[] = $n & 0xFF;
        } else {
            $out[] = ($n >> 16) | 0xC0;
            $out[] = ($n >> 8) & 0xFF;
            $out[] = $n & 0xFF;
        }
        $out = binary.concat($out, $b);
    }
    $out[] = 0;
    net.writeBytes($conn, $out);
}
