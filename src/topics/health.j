# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - system health: temperature, voltage, fans.
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the system health sensors. */
export def const SYSTEM_HEALTH_PATH as string init "/system/health";

/**
 * One hardware health sensor reading.
 *
 * @field name {string}  what is measured ("cpu-temperature", "voltage",
 *                      "fan1-speed", "temperature", ...)
 * @field value {string} the reading as reported (units vary by sensor)
 * @field kind {string}  the reading type ("C", "V", "RPM", ...) when reported
 */
export def struct HealthSensor {
    name as string,
    value as string,
    kind as string
};

/**
 * Read every hardware health sensor the router exposes.
 *
 * The sensors depend on the model: a small home router may report none,
 * a rack unit reports temperatures, voltages, fan speeds and PSU state.
 * An empty result is not an error. RouterOS 7 reports one sensor per row;
 * older models pack several properties into one row, which become one
 * sensor each with `kind` "".
 *
 * @param c {Client} an open client
 * @return {list of HealthSensor} the available sensors
 */
export func healthSensors(c as Client) {
    def rows as list of map of string to string init getAll($c, SYSTEM_HEALTH_PATH);
    def out as list of HealthSensor init [];
    for (def row in $rows) {
        # RouterOS 7 reports one sensor per row (name/value/type); older
        # models pack several fields into a single row.
        if (maps.has($row, "name") and maps.has($row, "value")) {
            $out[] = healthSensorFromRow($row);
        } else {
            def keys as list of string init maps.keys($row);
            for (def key in $keys) {
                if ($key != ".id") {
                    $out[] = HealthSensor{name: $key, value: $row[$key], kind: ""};
                }
            }
        }
    }
    return $out;
}

/**
 * Read one named sensor.
 *
 * @param c {Client}    an open client
 * @param name {string} the sensor name (e.g. "cpu-temperature")
 * @return {string} the reading, or "" when absent
 */
export func healthValue(c as Client, name as string) {
    def sensors as list of HealthSensor init healthSensors($c);
    for (def s in $sensors) {
        if ($s.name == $name) {
            return $s.value;
        }
    }
    return "";
}

/**
 * Fold a reply row into a HealthSensor.
 *
 * @param row {map of string to string} a "/system/health/print" row
 * @return {HealthSensor} the typed sensor
 * @internal
 */
func healthSensorFromRow(row as map of string to string) {
    return HealthSensor{
        name: rowValue($row, "name"),
        value: rowValue($row, "value"),
        kind: rowValue($row, "type")
    };
}
