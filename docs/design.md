# Design

## Scope

The deck is a full RouterOS™ abstraction layer for configuring MikroTik™
routers over the RouterOS binary API (port 8728, or 8729 with TLS). It is a
thick, typed layer over the thin protocol client `mikrotik`: one topic per
RouterOS menu area (interfaces and L2, the firewall, addressing and
services, routing and tunnels, traffic shaping, system maintenance), about
460 exported verbs over 56 topics. It validates input locally, sends
commands, and folds reply rows into structs, so a router's configuration
can be written as a Jennifer program (Infrastructure as Code).

It needs the `net` capability and the default binary; `jennifer-tiny` has
no sockets.

Out of scope:

- **The wire protocol.** Sentence framing, login and TLS belong to the
  `mikrotik` client; the deck never touches a socket itself.
- **The REST API and SSH.** The deck speaks the binary API only, which
  RouterOS v6 and v7 both serve.

## Decisions

- **Every request goes through five helpers.** `apiRun` (writes and
  actions), `apiTalk` (commands returning rows), `apiPrint` (a whole list),
  `apiPrintWhere` (with query words) and `apiPrintSelect` (query words
  plus `.proplist`). No topic calls `mikrotik` directly, so verbose logging
  and its redaction cover every request.
- **Filter on the router.** A lookup of one item (by name, comment, list,
  MAC, interface, address) sends `?` query words instead of reading the
  whole table, and listings that only need a few columns ask for them with
  `.proplist`. Large tables (address lists, the connection table, files
  with their contents, the DNS cache) then stay inside one reply's cap.
  Many items are removed with one `remove` per 100 ids (`removeMany`).
- **An empty handle matches nothing.** `findRowByField` only matches rows
  that carry the property and never matches `""`; `findByName("")` sends
  nothing; the `*ByComment` verbs and the container verbs refuse an empty
  handle. An empty comment would otherwise select the first uncommented
  rule.
- **Idempotent helpers converge.** `ensureInputAccept` (the VPN server
  openings) sets the properties that differ on an existing rule, so a
  server moved to another port moves its opening; `removeInputAcceptsByPrefix`
  touches only input-chain accept rules. `addBridgeVlan` ignores dynamic
  VLAN entries and finds an id inside a list or range; `bypassHotspotMac`
  refuses a MAC with a non-bypass binding; `addToAddressList` normalizes
  the address as RouterOS stores it before looking it up.
- **Validate before sending.** Every verb checks its input (names, ids,
  ports, CIDRs through `ipnet`, MAC addresses, port specs) and throws
  before any I/O. A typo is caught locally with a clear message instead of
  a router trap, and the verbs can be tested offline.
- **Comments are the stable handle for ordered tables.** A firewall rule's
  `.id` changes when it is re-added; its comment does not. The `*ByComment`
  verbs (firewall, NAT, raw, mangle, WireGuard™ peers and others) resolve
  through the comment. Containers are also identified by the comment
  `addContainer` writes, because RouterOS reports the image tag as the
  read-only container name.
- **Version differences are absorbed in the deck.** Booleans read as `true`
  or `yes`; CAPsMAN™ status tries the v7 path, then v6; formatting a disk
  falls back to the older command; a disk without a `name` (v7 USB storage)
  falls back to its slot; a container's `running` falls back to its status
  word; `forceEthernetLink` sends the 7.12+ link-mode word and falls back
  to `speed` plus `full-duplex`. Fallbacks read the `MikrotikError` fields
  (`reply`, `category`), never the message, and when both forms are
  refused the first error is thrown.
- **Missing packages read as empty lists.** Several list readers (disks,
  LTE, switch chips and hosts, wireless, wifi, WireGuard, CAPsMAN) return
  `[]` when the menu is missing, so a program runs on routers without the
  package. Only a router `!trap` counts as missing (`optionalMenuRows`);
  a dropped connection, a timeout or a reached cap is thrown.
- **Self-lockout guards.** The user helpers refuse to remove, disable or
  regroup the user the client is logged in as.
- **Commands that drop the connection.** `reboot`, `shutdown` and
  `installUpdates` succeed by killing the connection, so they swallow the
  router closing it (`"closed"`, a `!fatal`, a `net.NetError` with `sent`)
  and re-throw everything else: a refusal, a session that never connected,
  a network error before the command was sent, a timeout.
- **Streaming commands fold progress rows.** Ping, bandwidth test, fetch,
  update checks and the LTE and ethernet monitors read every reply row and
  merge them, later rows winning.
- **Value semantics.** `Client` is `{session, user, verbose}`, passed first
  to every verb; `setVerbose` returns a copy. `MT_VERBOSE` in the
  environment seeds the verbose flag at connect time.
- **One topic, one guide, one example.** Each topic has a guide in
  `docs/`, an example and a cheatsheet section (the L2TP, SSTP and OpenVPN™
  topics share the VPN guide). The guides import the deck as `mt`.

## Errors

- `Error{kind: "routeros"}`: local validation refused the input, or a
  plain-TCP login was not opted into; nothing was sent.
- `mikrotik.MikrotikError` (kind `"mikrotik"`): the router answered `!trap`
  or `!fatal`, or the login failed; `reply`, `category` and
  `routerMessage` hold the router's answer.
- `net.NetError` (kind `"net"`): the router could not be reached (refused,
  reset, unreachable, no DNS answer, a failed TLS handshake). A deadline is
  kind `"timeout"`, a connection closed under a command `"closed"`, and a
  `Client` that was never connected fails with `"closed"`.
- `"limit"` (jennifer 0.27.0 and later): a reply over one of `mikrotik`'s
  caps.

The deck passes the `mikrotik` and transport errors on unchanged; it wraps
nothing.

## Security and limits

- Verbose logging redacts secrets by attribute name: `password`, `secret`,
  `passphrase`, `pin`, `contents`, keys ending in `-key` (private, preshared,
  TCP-MD5 keys) and pre-shared keys; under one menu only, a container env's
  `value` and an SNMP community's `name` (`isSecretFor`). Query words on a
  secret property are redacted the same way. The match is narrow on
  purpose, so `public-key`, `key-usage`, a container env's `key`, `passive`
  and `passthrough` stay visible. A new secret-carrying attribute whose
  name does not fit those patterns has to be added to the redaction and
  its tests.
- `importCertificatePem` moves the private key through a file on the
  router and removes both temporary files also when the import fails.
- TLS is the way in: `connectTLS` dials api-ssl and verifies the router's
  certificate against the host's roots; `connectTLSWithCA` and
  `connectWithCA` pass a PEM through to `mikrotik.withCA` (in 0.26.0), which
  verifies against it instead, for self-signed and private-CA routers.
  `generateSelfSigned` sets the subject alternative name from the common
  name, because Go's TLS ignores the common name. The plain `api` service (8728) sends the login in the clear
  on RouterOS 6.43 and later (an MD5 challenge on older routers) and every
  command after it, so the deck logs in over it only on an explicit
  `allowInsecureAuth` (`connectWith`'s last argument), the name and meaning
  of the `mikrotik` option it is passed on to. Without it, `connect` and
  `connectWith` refuse with kind `"routeros"` before dialling, on every
  interpreter: the deck checks itself rather than relying on `mikrotik`,
  whose own refusal (kind `"mikrotik"`) exists only from jennifer 0.27.0.
  Home-lab routers often run only `api`, hence the opt-in rather than no
  plain TCP at all.
- Rules the deck appends (service and VPN accept rules) land at the bottom
  of the input chain; on a firewall that drops early they need moving above
  the drop. The guides say so.
- Read deadlines and reply limits are the `mikrotik` client's. From
  jennifer 0.27.0 a reply over its caps (4096 words in a sentence, 262144
  words or 64 MiB in a reply) throws the generic kind `"limit"`; the
  connection is then half-read and the client should be closed. The deck's
  own lookups filter on the router; `addressLists` and the connection
  readers trim the columns, so they reach about 130,000 and 30,000 rows.

## Testing and validation

- No router is contacted in the tests. They cover the validators, the
  row folding, the builders and the log redaction, and call verbs on a
  never-connected client to prove that bad input is refused before I/O (a
  verb that passes validation fails with kind `"closed"`). Verbs whose
  behaviour depends on the router's answer run against a scripted fake
  (`src/topics/fixtures/fakerouter_test.j`): a loopback listener speaking
  the plain API that answers prints from canned rows (with `?` queries and
  `.proplist`), traps or drops chosen commands and records every sentence,
  so a test asserts what was sent. About 770 tests in one overlay per
  topic, run together through `src/routeros_test.j`.
- `tools/check-extra.sh` checks every `mt.` call in the guides, the README
  and the examples against the code (existence and arity), since the shared
  docs check only knows calls written with the deck's own name.
- The examples need a live router and are only parsed in the gate; they
  are read-only, with mutating calls commented out.

Not covered: the deck has no automated test against a router or a
recorded RouterOS session, and 262 exports (mostly verbs whose only
offline-testable path is validation) are not called from any overlay;
`tools/.coverage-todo` lists them and only shrinks.

## Known limitations and open questions

- Some router behaviour the fake cannot prove: `remove` with a
  comma-separated `.id` list (as `librouteros` sends it), the
  `authority` flag name for CA certificates, the `!trap` an older v7
  answers to a 7.12+ link-mode word, and whether `/file` lists a
  container's extracted files. Each falls back to a conservative reading
  where it can.
- RouterOS attribute names are not guessable (env and mount entries group
  under `list`, containers reference `envlists` and `mountlists`); a wrong
  name is a router trap, `unknown parameter`, found only on a router.

## Dependencies

- The `@deckyard/mikrotik` deck (`^0.5.0`) for the binary API: its
  `Options.allowInsecureAuth` and `MikrotikError` as a thrown struct.
- The bundled `ipnet` module.
- `net.NetError` and the `"net"` kind for transport failures (`jennifer`'s
  M28.65, transport errors have their own kind).
- The 0.26 certificate API the certificates topic uses.
- Floor `>=0.28.0`, the floor of the `@deckyard/mikrotik` release with the
  session and deadline fixes. The UTF-8 codecs of `encoding.encode` /
  `decode` and `strings.replicate` arrived in 0.27.0.
