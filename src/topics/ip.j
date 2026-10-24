# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - IP addresses on interfaces.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the IP address list. */
export def const IP_ADDRESS_PATH as string init "/ip/address";

/**
 * One IP address assigned to an interface.
 *
 * @field id {string} internal RouterOS id
 * @field address {string} address with prefix, e.g. "192.168.88.1/24"
 * @field network {string} network address the prefix implies, e.g. "192.168.88.0"
 * @field interfaceName {string} interface the address sits on
 * @field dynamic {bool} true when a DHCP client or PPP session assigned it;
 *        such addresses cannot be removed by hand
 * @field disabled {bool} true when the address is switched off
 * @field comment {string} comment, "" when unset
 */
export def struct IpAddress {
    id as string,
    address as string,
    network as string,
    interfaceName as string,
    dynamic as bool,
    disabled as bool,
    comment as string
};

/**
 * List every IP address on the router.
 *
 * @param c {Client} an open client
 * @return {list of IpAddress} static and dynamic addresses
 */
export func ipAddresses(c as Client) {
    def rows as list of map of string to string init getAll($c, IP_ADDRESS_PATH);
    def out as list of IpAddress init [];
    for (def row in $rows) {
        $out[] = ipAddressFromRow($row);
    }
    return $out;
}

/**
 * Assign an IP address to an interface.
 *
 * The prefix length is required: it sets the size of the connected
 * network, and a bare address would become a /32.
 *
 * @param c {Client} an open client
 * @param address {string} address with prefix length, e.g. "192.168.88.1/24"
 * @param interfaceName {string} interface or bridge to put it on
 * @return {string} id of the new address
 * @throws {Error} kind "routeros" on a malformed address, a missing
 *                 prefix, or an unknown interface
 */
export func addIpAddress(c as Client, address as string, interfaceName as string) {
    ensureCidr($address);
    requiredId($c, INTERFACE_PATH, $interfaceName, "interface");
    return add($c, IP_ADDRESS_PATH, {"address": $address, "interface": $interfaceName});
}

/**
 * Remove an IP address from whatever interface it sits on.
 *
 * Matches the address string exactly as RouterOS lists it, prefix
 * included.
 *
 * @param c {Client} an open client
 * @param address {string} address with prefix, e.g. "192.168.88.1/24"
 * @throws {Error} kind "routeros" when the router has no such address
 */
export func removeIpAddress(c as Client, address as string) {
    def rows as list of map of string to string init getAll($c, IP_ADDRESS_PATH);
    def row as map of string to string init findRowByField($rows, "address", $address);
    if (len($row) == 0) {
        raiseError("the address \"" + $address + "\" is not configured on the router");
    }
    remove($c, IP_ADDRESS_PATH, rowValue($row, ".id"));
}

/**
 * Fold a reply row into an IpAddress.
 *
 * @param row {map of string to string} an "/ip/address/print" row
 * @return {IpAddress} the typed address
 * @internal
 */
func ipAddressFromRow(row as map of string to string) {
    return IpAddress{
        id: rowValue($row, ".id"),
        address: rowValue($row, "address"),
        network: rowValue($row, "network"),
        interfaceName: rowValue($row, "interface"),
        dynamic: rowBool($row, "dynamic"),
        disabled: rowBool($row, "disabled"),
        comment: rowValue($row, "comment")
    };
}
