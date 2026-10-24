<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 mplx <mplx@jennifer-lang.dev> -->

# SMS

File: `src/topics/sms.j`. Paths: `/tool/sms` (`SMS_PATH`),
`/tool/sms/inbox` (`SMS_INBOX_PATH`), `/tool/sms/send`
(`SMS_SEND_COMMAND`). Reference: [cheatsheet](cheatsheet.md#sms).

A router with a cellular modem ([lte.md](lte.md)) sends and receives
text messages. An SMS leaves over the modem when the wired uplink is
down and an e-mail alert would not arrive; trigger it from
[netwatch.md](netwatch.md) or the [scheduler](scheduler.md).

Reception is off by default and needs the modem port (`lteInterfaces`
lists them, usually `lte1`). RouterOS can also run commands sent by SMS;
`restrictSms` sets the one sender it accepts them from.

## Examples

Alert from a site whose uplink failed:

```jennifer
mt.sendSms($c, "lte1", "+441632960123", "gw1: uplink down");
```

Receive, restrict and read:

```jennifer
mt.enableSmsReceive($c, "lte1");
mt.restrictSms($c, "+441632960123", 50);

for (def m in mt.smsInbox($c)) {
    io.printf("%s  %s: %s\n", $m.timestamp, $m.phone, $m.message);
}
io.printf("cleared %d\n", mt.clearSmsInbox($c));
```

## Pitfalls

- Set `allowedNumber` unless the SIM number is secret. Unrestricted,
  SMS commands are an unauthenticated way onto the router.
- `keepMaxSms` (1-100) caps the inbox. Old messages are dropped only when
  the router's `autoErase` is on; otherwise run `clearSmsInbox` on a
  schedule.
- Phone numbers are checked leniently: digits, `+ - ( )` and spaces, with
  at least one digit. That catches a name where a number belongs, not a
  wrong number.
- A registered modem that will not send is usually out of credit or
  barred for premium or roaming SMS. The error is `kind "mikrotik"` from
  the modem.
