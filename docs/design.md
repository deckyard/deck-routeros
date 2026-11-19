# Design

## Scope

The deck is a full RouterOS abstraction layer for configuring MikroTik
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

- **Every request goes through four helpers.** `apiRun` (writes and
  actions), `apiTalk` (commands returning rows), `apiPrint` (a whole list)
  and `apiPrintWhere` (with query words). No topic calls `mikrotik`
  directly, so verbose logging and its redaction cover every request.
- **Validate before sending.** Every verb checks its input (names, ids,
  ports, CIDRs through `ipnet`, MAC addresses, port specs) and throws
  before any I/O. A typo is caught locally with a clear message instead of
  a router trap, and the verbs can be tested offline.
- **Comments are the stable handle for ordered tables.** A firewall rule's
  `.id` changes when it is re-added; its comment does not. The `*ByComment`
  verbs (firewall, NAT, raw, mangle, WireGuard peers and others) resolve
  through the comment. Containers are also identified by the comment
  `addContainer` writes, because RouterOS reports the image tag as the
  read-only container name.
- **Version differences are absorbed in the deck.** Booleans read as `true`
  or `yes`; CAPsMAN status tries the v7 path, then v6; formatting a disk
  falls back to the older command; a disk without a `name` (v7 USB storage)
  falls back to its slot; a container's `running` falls back to its status
  word.
- **Missing packages read as empty lists.** Several list readers (disks,
  LTE, switch chips, wireless, wifi, WireGuard, CAPsMAN) return `[]` on any
  error, so a program runs on routers without the package or menu. The cost
  is that they also hide a dropped connection.
- **Self-lockout guards.** The user helpers refuse to remove, disable or
  regroup the user the client is logged in as.
- **Commands that drop the connection.** `reboot`, `shutdown` and
  `installUpdates` succeed by killing the connection, so they swallow the
  transport error that follows and re-throw only a router refusal.
- **Streaming commands fold progress rows.** Ping, bandwidth test, fetch,
  update checks and the LTE and ethernet monitors read every reply row and
  merge them, later rows winning.
- **Value semantics.** `Client` is `{session, user, verbose}`, passed first
  to every verb; `setVerbose` returns a copy. `MT_VERBOSE` in the
  environment seeds the verbose flag at connect time.
- **One topic, one guide, one example.** Each topic has a guide in
  `docs/`, an example and a cheatsheet section (the L2TP, SSTP and OpenVPN
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
  `passphrase`, private keys and pre-shared keys. The match is narrow on
  purpose, so `public-key`, `key-usage`, `passive` and `passthrough` stay
  visible. A new secret-carrying attribute whose name does not fit those
  patterns has to be added to the redaction and its tests. Query words of
  `apiPrintWhere` are logged unredacted.
- TLS is the way in: `connectTLS` dials api-ssl and verifies the router's
  certificate. The plain `api` service (8728) sends the login in the clear
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
  connection is then half-read and the client should be closed. Read a big
  table in parts with `apiPrintWhere` queries.

## Testing and validation

- No router is contacted in the tests. They cover the validators, the
  row folding, the builders and the log redaction, and call verbs on a
  never-connected client to prove that bad input is refused before I/O (a
  verb that passes validation fails with kind `"closed"`). About 650 tests
  in one overlay per topic, run together through `src/routeros_test.j`.
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

- The list readers that return `[]` on any error cannot tell a missing
  package from a dropped connection.
- RouterOS attribute names are not guessable (env and mount entries group
  under `list`, containers reference `envlists` and `mountlists`); a wrong
  name is a router trap, `unknown parameter`, found only on a router.
- The bundled `mikrotik` module is deprecated in favour of the
  `@jennifer/mikrotik` deck. The deck moves to it (a `[decks]` entry) in a
  release before `jennifer` 0.28.0 removes the bundled copy.

## Dependencies on the interpreter

- The bundled `mikrotik` (`jennifer`'s M18.39) and `ipnet` modules.
- `net.NetError` and the `"net"` kind for transport failures (`jennifer`'s
  M28.65, transport errors have their own kind).
- `mikrotik.MikrotikError` as a thrown struct, and the 0.26 certificate API
  the certificates topic uses; floor `>=0.26.0`.
- `mikrotik.Options.allowInsecureAuth` (jennifer 0.27.0), which the 0.26
  `mikrotik` lacks. `withInsecureAuth` (core.j) sets it inside a `try` and
  treats the kind `"runtime"` of a missing field as "0.26, no opt-in
  needed", since an unknown field fails only when the assignment runs. The
  `try` goes when the deck moves to `@jennifer/mikrotik`.
