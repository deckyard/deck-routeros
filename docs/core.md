# Core: connecting and the generic verbs

File: `src/topics/core.j`. It holds the connection, the generic verbs that
work on any RouterOS list path, and the validators every other topic uses.

Reference: [cheatsheet](cheatsheet.md#core).

## Connecting

```jennifer
import "@deckyard/routeros/" as mt;

# plaintext API, port 8728
def c as mt.Client init mt.connect("192.168.88.1", "admin", "secret");

# TLS (api-ssl), port 8729; the router's certificate is verified
def cs as mt.Client init mt.connectTLS("192.168.88.1", "admin", "secret");

# explicit port and TLS choice
def cc as mt.Client init mt.connectWith("192.168.88.1", 18728, "admin", "secret", false);

mt.disconnect($c);
```

The router must have the `api` (8728) or `api-ssl` (8729) service enabled
under `/ip/service`. Login works on RouterOS 6.43+ and v7; the transport
falls back to MD5 challenge-response for older versions. `connectWith`
rejects a port outside 1-65535 before dialling.

## Generic verbs

`getAll`, `add`, `set` (`update` is a synonym), `remove`, `removeByName`,
`findByName`, `idByName`, `enable` and `disable` work on any list path,
including ones without a typed helper:

```jennifer
def opts as list of map of string to string init mt.getAll($c, "/ip/dhcp-server/option");
for (def o in $opts) {
    io.printf("dhcp option %s code %s\n", $o["name"], $o["code"]);
}

mt.disable($c, "/ip/upnp/interfaces", mt.idByName($c, "/ip/upnp/interfaces", "ether1"));
```

- Paths are normalized: `"interface"`, `"/interface"` and `"/interface/"`
  are the same. An empty path or `"/"` is rejected.
- Attribute maps use RouterOS property names (`"mac-address"`); values are
  strings, booleans `"yes"` / `"no"`.
- Ids look like `"*3"`. `add` returns one, typed structs carry it in `.id`.
  Ids change when an item is re-created, so most typed helpers take a name
  or a comment instead.
- `findByName` filters on the router (`?name=`); it returns an empty map on
  a miss, `idByName` returns `""`.

### Ordering

RouterOS evaluates ordered lists (firewall filter, NAT, mangle, raw, simple
queues) top to bottom and stops at the first match, so position changes
behavior. `moveRule(c, path, id, beforeId)` puts an item directly above
`beforeId` (`""` = bottom; moving an item before itself is rejected),
`moveRuleToTop` reads the list and is a no-op when the item is already
first, `moveRuleToBottom` is `moveRule` with `""`.

```jennifer
mt.moveRule($c, mt.FIREWALL_PATH, $acceptWgId, $dropNonLanId);
```

## Verbose mode

With logging on, every command is printed to stdout before it is sent:

```jennifer
$c = mt.setVerbose($c, true);
mt.addBridge($c, "brlan");
mt.addIpAddress($c, "192.168.88.1/24", "brlan");
```

```
mt> /interface/bridge/add name=brlan
mt> /ip/address/add address=192.168.88.1/24 interface=brlan
mt> /ip/address/print
mt< 3 rows
```

`setVerbose` returns a copy of the client: write
`$c = mt.setVerbose($c, true);`. Called as a bare statement it changes
nothing, because a Jennifer module holds no mutable state and the flag
lives on the `Client`. `MT_VERBOSE=1` (also `yes`, `true`, `on`, any case)
turns it on at connect time without editing the script:

```sh
MT_VERBOSE=1 jennifer run provision.j
```

Logging covers every command the deck sends, reads included: all topics
go through the same four transport functions.

Credentials print as `<redacted>`. Redacted keys: `password`, `secret`,
`passphrase`, `private-key`, keys ending in `-password`, `-secret`,
`-passphrase`, `.passphrase` or `-private-key`, and keys containing
`pre-shared-key`. `public-key`, `key-usage`, `passive` and `passthrough`
are not redacted. An SNMP community travels as a plain `name` and does
appear in the log (see [snmp.md](snmp.md)).

```
mt> /tool/e-mail/set server=smtp.example.org user=router password=<redacted>
```

## Errors

- `Error{kind: "routeros"}`: local validation refused the input; nothing
  was sent.
- `Error{kind: "mikrotik"}`: the router refused (`!trap`), or the
  connection or login failed.

```jennifer
try {
    mt.addBridge($c, "br lan");
} catch (e) {
    io.printf("rejected: %s\n", $e.message);
    # rejected: the bridge name must not contain spaces
}
```

IP addresses and CIDR networks are parsed with the stock `ipnet` module.
Structs returned by the deck are value snapshots, not live views.
