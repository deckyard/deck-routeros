# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - SMS over the cellular modem: settings, sending, the inbox.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the SMS settings. */
export def const SMS_PATH as string init "/tool/sms";

/** RouterOS API path of the received-message store. */
export def const SMS_INBOX_PATH as string init "/tool/sms/inbox";

/** RouterOS API command that sends a text message. */
export def const SMS_SEND_COMMAND as string init "/tool/sms/send";

def const PHONE_CHARS as string init "0123456789+-() ";

/**
 * The router's SMS settings.
 *
 * @field receiveEnabled {bool} whether incoming messages are stored
 * @field port {string} modem port, e.g. "lte1"
 * @field channel {string} modem channel, "" for the default
 * @field allowedNumber {string} the only sender accepted for remote
 *        commands, "" when unrestricted
 * @field keepMaxSms {int} cap on stored received messages
 * @field autoErase {bool} whether the oldest message is dropped at the cap
 */
export def struct SmsSettings {
    receiveEnabled as bool,
    port as string,
    channel as string,
    allowedNumber as string,
    keepMaxSms as int,
    autoErase as bool
};

/**
 * One received text message.
 *
 * @field id {string} RouterOS item id
 * @field phone {string} sender's number
 * @field message {string} message text
 * @field timestamp {string} receive time, as RouterOS prints it
 * @field kind {string} RouterOS `type` value, "" when absent
 */
export def struct SmsMessage {
    id as string,
    phone as string,
    message as string,
    timestamp as string,
    kind as string
};

/**
 * Read the router's SMS settings.
 *
 * @param c {Client} an open client
 * @return {SmsSettings} the current settings
 * @example
 *   def s as mt.SmsSettings init mt.smsSettings($c);
 *   if ($s.receiveEnabled) { io.printf("storing SMS on %s\n", $s.port); }
 */
export func smsSettings(c as Client) {
    return smsSettingsFromRow(singleRow($c, SMS_PATH));
}

/**
 * Start storing incoming text messages received on one modem port.
 *
 * Reception is off by default. `lteInterfaces` lists the modem ports,
 * usually "lte1".
 *
 * @param c {Client} an open client
 * @param port {string} modem port, e.g. "lte1"
 * @throws {Error} kind "routeros" on an empty or spaced port name
 * @example
 *   mt.enableSmsReceive($c, "lte1");
 */
export func enableSmsReceive(c as Client, port as string) {
    ensureName($port, "SMS port");
    apiRun($c, SMS_PATH + "/set", {"receive-enabled": "yes", "port": strings.trim($port)});
}

/**
 * Stop storing incoming text messages; the inbox is kept.
 *
 * @param c {Client} an open client
 * @example
 *   mt.disableSmsReceive($c);
 */
export func disableSmsReceive(c as Client) {
    apiRun($c, SMS_PATH + "/set", {"receive-enabled": "no"});
}

/**
 * Set the sender the router accepts commands from, and the inbox cap.
 *
 * RouterOS can run commands sent by SMS. Without `allowedNumber`,
 * anyone who knows the SIM number can drive the router. Pass "" to
 * clear the restriction.
 *
 * @param c {Client} an open client
 * @param allowedNumber {string} the sender to accept, "" for any
 * @param keepMaxSms {int} received messages to keep, 1-100
 * @throws {Error} kind "routeros" on a malformed number or a cap outside 1-100
 * @example
 *   mt.restrictSms($c, "+441632960123", 50);
 */
export func restrictSms(c as Client, allowedNumber as string, keepMaxSms as int) {
    if ($keepMaxSms < 1 or $keepMaxSms > 100) {
        raiseError("the kept-message count must be between 1 and 100");
    }
    def number as string init strings.trim($allowedNumber);
    if ($number != "") {
        ensurePhoneNumber($number);
    }
    apiRun(
        $c,
        SMS_PATH + "/set",
        {"allowed-number": $number, "keep-max-sms": convert.toString($keepMaxSms)});
}

/**
 * Send a text message through the router's modem.
 *
 * It goes out over the cellular network, so it works when the wired
 * uplink is down and e-mail cannot.
 *
 * @param c {Client} an open client
 * @param port {string} modem port, e.g. "lte1"
 * @param phoneNumber {string} recipient's number
 * @param message {string} message text
 * @throws {Error} kind "routeros" on a bad port, a bad number or an empty
 *         message, kind "mikrotik" when the modem refuses to send
 * @example
 *   mt.sendSms($c, "lte1", "+441632960123", "gw1: uplink down");
 */
export func sendSms(c as Client, port as string, phoneNumber as string, message as string) {
    ensureName($port, "SMS port");
    def number as string init strings.trim($phoneNumber);
    ensurePhoneNumber($number);
    if ($message == "") {
        raiseError("the message must not be empty");
    }
    apiRun(
        $c,
        SMS_SEND_COMMAND,
        {"port": strings.trim($port), "phone-number": $number, "message": $message});
}

/**
 * Read the received messages; empty until `enableSmsReceive` is on.
 *
 * @param c {Client} an open client
 * @return {list of SmsMessage} the stored messages
 * @example
 *   for (def m in mt.smsInbox($c)) { io.printf("%s: %s\n", $m.phone, $m.message); }
 */
export func smsInbox(c as Client) {
    def rows as list of map of string to string init getAll($c, SMS_INBOX_PATH);
    def out as list of SmsMessage init [];
    for (def row in $rows) {
        $out[] = smsMessageFromRow($row);
    }
    return $out;
}

/**
 * Delete one received message.
 *
 * @param c {Client} an open client
 * @param id {string} message id from `SmsMessage.id`
 * @throws {Error} kind "routeros" on an empty id
 */
export func removeSmsMessage(c as Client, id as string) {
    remove($c, SMS_INBOX_PATH, $id);
}

/**
 * Delete every received message.
 *
 * @param c {Client} an open client
 * @return {int} number of messages deleted
 * @example
 *   io.printf("cleared %d messages\n", mt.clearSmsInbox($c));
 */
export func clearSmsInbox(c as Client) {
    def rows as list of map of string to string init getAll($c, SMS_INBOX_PATH);
    def removed as int init 0;
    for (def row in $rows) {
        remove($c, SMS_INBOX_PATH, rowValue($row, ".id"));
        $removed = $removed + 1;
    }
    return $removed;
}

/**
 * Fold the "/tool/sms/print" row into SmsSettings.
 *
 * @param row {map of string to string} the reply row
 * @return {SmsSettings} the typed settings
 * @internal
 */
func smsSettingsFromRow(row as map of string to string) {
    return SmsSettings{
        receiveEnabled: rowBool($row, "receive-enabled"),
        port: rowValue($row, "port"),
        channel: rowValue($row, "channel"),
        allowedNumber: rowValue($row, "allowed-number"),
        keepMaxSms: rowInt($row, "keep-max-sms"),
        autoErase: rowBool($row, "auto-erase")
    };
}

/**
 * Fold a "/tool/sms/inbox/print" row into an SmsMessage.
 *
 * @param row {map of string to string} the reply row
 * @return {SmsMessage} the typed message
 * @internal
 */
func smsMessageFromRow(row as map of string to string) {
    return SmsMessage{
        id: rowValue($row, ".id"),
        phone: rowValue($row, "phone"),
        message: rowValue($row, "message"),
        timestamp: rowValue($row, "timestamp"),
        kind: rowValue($row, "type")
    };
}

/**
 * Validate a phone number: digits, `+ - ( )` and spaces, at least one digit.
 *
 * Lenient because national formats vary; it catches a name or an
 * address passed where a number belongs.
 *
 * @param number {string} the candidate, already trimmed
 * @throws {Error} kind "routeros" when empty, with another character, or
 *         without a digit
 * @internal
 */
func ensurePhoneNumber(number as string) {
    if ($number == "") {
        raiseError("the phone number must not be empty");
    }
    def digits as int init 0;
    def parts as list of string init strings.chars($number);
    for (def ch in $parts) {
        if (not strings.contains(PHONE_CHARS, $ch)) {
            raiseError("\"" + $number + "\" is not a valid phone number");
        }
        if (strings.contains(DIGIT_CHARS, $ch)) {
            $digits = $digits + 1;
        }
    }
    if ($digits == 0) {
        raiseError("\"" + $number + "\" is not a valid phone number - it has no digits");
    }
}
