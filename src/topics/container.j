# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# routeros - containers: run OCI images on the router (RouterOS v7).
# Spliced into routeros.j via include - not a standalone module.

/** RouterOS API path of the container list. */
export def const CONTAINER_PATH as string init "/container";

/** RouterOS API path of the container environment-variable lists. */
export def const CONTAINER_ENVS_PATH as string init "/container/envs";

/** RouterOS API path of the container mount lists. */
export def const CONTAINER_MOUNTS_PATH as string init "/container/mounts";

/** RouterOS API path of the container config (registry, temp dir). */
export def const CONTAINER_CONFIG_PATH as string init "/container/config";

/**
 * One container on the router.
 *
 * RouterOS's own `name` property is read-only and reports the image tag
 * ("pihole:latest"), so `name` here is the container's comment, which
 * `addContainer` sets; it falls back to the tag when there is no comment.
 *
 * @field id {string} RouterOS item id
 * @field name {string} the comment `addContainer` set, else the image tag
 * @field tag {string} image tag it runs
 * @field status {string} "running", "stopped", "extracting", "error", ...;
 *        derived from `running` when the router sends no status
 * @field running {bool} whether the container is up
 * @field interfaceName {string} veth interface it attaches to
 * @field rootDir {string} path of its filesystem on the router
 * @field envLists {string} comma-separated env lists, "" for none
 * @field mountLists {string} comma-separated mount lists, "" for none
 */
export def struct Container {
    id as string,
    name as string,
    tag as string,
    status as string,
    running as bool,
    interfaceName as string,
    rootDir as string,
    envLists as string,
    mountLists as string
};

/**
 * One environment variable belonging to a named env list.
 *
 * @field id {string} RouterOS item id
 * @field listName {string} env list it belongs to
 * @field key {string} variable name, e.g. "TZ"
 * @field value {string} variable value
 */
export def struct ContainerEnv {
    id as string,
    listName as string,
    key as string,
    value as string
};

/**
 * One mount belonging to a named mount list.
 *
 * @field id {string} RouterOS item id
 * @field listName {string} mount list it belongs to
 * @field src {string} path on the router's storage
 * @field dst {string} path inside the container
 */
export def struct ContainerMount {
    id as string,
    listName as string,
    src as string,
    dst as string
};

/**
 * List the containers on the router.
 *
 * @param c {Client} an open client
 * @return {list of Container} every container
 */
export func containers(c as Client) {
    def rows as list of map of string to string init getAll($c, CONTAINER_PATH);
    def out as list of Container init [];
    for (def row in $rows) {
        $out[] = containerFromRow($row);
    }
    return $out;
}

/**
 * Add a container from a registry image.
 *
 * The image (`remote-image`) is extracted into `rootDir` on the router's
 * storage and the container attaches to an existing veth interface.
 * Prerequisites, set up first: the `container` package, container
 * support enabled in the device mode (a console-side step this call
 * does not bypass), the veth, and the storage. The container's comment
 * is set to `name`, the handle the other container calls use.
 *
 * Attach env and mount lists (`setContainerEnvLists`,
 * `setContainerMountLists`) before the first `startContainer`: most
 * images read their config only at startup.
 *
 * @param c {Client} an open client
 * @param name {string} handle for the container, stored as its comment
 * @param remoteImage {string} registry image, e.g. "pihole/pihole:latest"
 * @param interfaceName {string} existing veth interface
 * @param rootDir {string} filesystem path on the router, e.g. "usb1/pihole"
 * @return {string} the RouterOS id of the container
 * @throws {Error} kind "routeros" on a bad name, an empty image or root
 *         directory, or an unknown interface
 * @example
 *   # prerequisites (generic verbs): a veth, and container support enabled
 *   mt.add($c, "/interface/veth", {"name": "veth1", "address": "172.17.0.2/24",
 *       "gateway": "172.17.0.1"});
 *   mt.addContainerEnv($c, "pihole-env", "TZ", "Europe/Vienna");
 *   mt.addContainerMount($c, "pihole-etc", "usb1/pihole/etc", "/etc/pihole");
 *   mt.addContainer($c, "pihole", "pihole/pihole:latest", "veth1", "usb1/pihole");
 *   mt.setContainerEnvLists($c, "pihole", ["pihole-env"]);
 *   mt.setContainerMountLists($c, "pihole", ["pihole-etc"]);
 *   mt.startContainer($c, "pihole");
 */
export func addContainer(
    c as Client,
    name as string,
    remoteImage as string,
    interfaceName as string,
    rootDir as string) {
    ensureName($name, "container");
    if (strings.trim($remoteImage) == "") {
        raiseError("the remote image must not be empty (e.g. \"pihole/pihole:latest\")");
    }
    requiredId($c, INTERFACE_PATH, $interfaceName, "veth interface");
    if (strings.trim($rootDir) == "") {
        raiseError("the root directory must not be empty (e.g. \"usb1/pihole\")");
    }
    return add(
        $c,
        CONTAINER_PATH,
        {
            "remote-image": strings.trim($remoteImage),
            "interface": $interfaceName,
            "root-dir": strings.trim($rootDir),
            "comment": $name
        });
}

/**
 * Start a container.
 *
 * @param c {Client} an open client
 * @param name {string} container comment or image tag
 * @throws {Error} kind "routeros" when no such container exists
 */
export func startContainer(c as Client, name as string) {
    apiRun($c, CONTAINER_PATH + "/start", {".id": requiredContainerId($c, $name)});
}

/**
 * Stop a container.
 *
 * @param c {Client} an open client
 * @param name {string} container comment or image tag
 * @throws {Error} kind "routeros" when no such container exists
 */
export func stopContainer(c as Client, name as string) {
    apiRun($c, CONTAINER_PATH + "/stop", {".id": requiredContainerId($c, $name)});
}

/**
 * Remove a container and its extracted filesystem.
 *
 * @param c {Client} an open client
 * @param name {string} container comment or image tag
 * @throws {Error} kind "routeros" when no such container exists
 */
export func removeContainer(c as Client, name as string) {
    remove($c, CONTAINER_PATH, requiredContainerId($c, $name));
}

/**
 * List the container environment variables of every env list.
 *
 * @param c {Client} an open client
 * @return {list of ContainerEnv} every variable, across all lists
 */
export func containerEnvs(c as Client) {
    def rows as list of map of string to string init getAll($c, CONTAINER_ENVS_PATH);
    def out as list of ContainerEnv init [];
    for (def row in $rows) {
        $out[] = containerEnvFromRow($row);
    }
    return $out;
}

/**
 * Add one environment variable to a named env list.
 *
 * A list is a name shared by its entries; the first variable creates
 * it. Attach it with `setContainerEnvLists` before the container's
 * first start. Not idempotent: clear the list first when re-running.
 *
 * @param c {Client} an open client
 * @param listName {string} env list, e.g. "pihole-env"
 * @param key {string} variable name, e.g. "TZ"
 * @param value {string} variable value
 * @return {string} the RouterOS id of the new entry
 * @throws {Error} kind "routeros" on a bad list name or an empty key
 * @example
 *   mt.addContainerEnv($c, "pihole-env", "TZ", "Europe/Vienna");
 */
export func addContainerEnv(c as Client, listName as string, key as string, value as string) {
    ensureName($listName, "env list");
    if (strings.trim($key) == "") {
        raiseError("the environment variable name must not be empty (e.g. \"TZ\")");
    }
    return add(
        $c,
        CONTAINER_ENVS_PATH,
        {"list": $listName, "key": strings.trim($key), "value": $value});
}

/**
 * Delete every environment variable in a named list.
 *
 * Run it before re-adding the variables so a provisioning script can be
 * re-run without duplicates.
 *
 * @param c {Client} an open client
 * @param listName {string} env list to clear
 * @return {int} number of variables deleted
 * @throws {Error} kind "routeros" on an empty list name or one with spaces
 */
export func removeContainerEnvList(c as Client, listName as string) {
    return removeListEntries($c, CONTAINER_ENVS_PATH, $listName, "env list");
}

/**
 * List the container mounts of every mount list.
 *
 * @param c {Client} an open client
 * @return {list of ContainerMount} every mount, across all lists
 */
export func containerMounts(c as Client) {
    def rows as list of map of string to string init getAll($c, CONTAINER_MOUNTS_PATH);
    def out as list of ContainerMount init [];
    for (def row in $rows) {
        $out[] = containerMountFromRow($row);
    }
    return $out;
}

/**
 * Add one mount to a named mount list.
 *
 * `src` is a path on the router's storage, created if missing; `dst`
 * is where it appears inside the container. A config directory mounted
 * out to disk survives a re-pull of the image.
 *
 * @param c {Client} an open client
 * @param listName {string} mount list, e.g. "pihole-etc"
 * @param src {string} path on the router, e.g. "usb1/pihole/etc"
 * @param dst {string} path inside the container, e.g. "/etc/pihole"
 * @return {string} the RouterOS id of the new entry
 * @throws {Error} kind "routeros" on a bad list name or an empty source or
 *         destination
 * @example
 *   mt.addContainerMount($c, "pihole-etc", "usb1/pihole/etc", "/etc/pihole");
 */
export func addContainerMount(c as Client, listName as string, src as string, dst as string) {
    ensureName($listName, "mount list");
    if (strings.trim($src) == "") {
        raiseError("the mount source must not be empty (a path on the router, e.g. \"usb1/pihole/etc\")");
    }
    if (strings.trim($dst) == "") {
        raiseError("the mount destination must not be empty (a path inside the container, e.g. \"/etc/pihole\")");
    }
    return add(
        $c,
        CONTAINER_MOUNTS_PATH,
        {"list": $listName, "src": strings.trim($src), "dst": strings.trim($dst)});
}

/**
 * Delete every mount in a named list.
 *
 * @param c {Client} an open client
 * @param listName {string} mount list to clear
 * @return {int} number of mounts deleted
 * @throws {Error} kind "routeros" on an empty list name or one with spaces
 */
export func removeContainerMountList(c as Client, listName as string) {
    return removeListEntries($c, CONTAINER_MOUNTS_PATH, $listName, "mount list");
}

/**
 * Set the env lists a container reads, replacing the previous ones.
 *
 * An empty list detaches all of them. A running container picks the
 * change up only after a stop and start.
 *
 * @param c {Client} an open client
 * @param name {string} container comment or image tag
 * @param listNames {list of string} env lists to attach
 * @throws {Error} kind "routeros" when no such container exists or a list
 *         name is empty or contains spaces
 * @example
 *   mt.setContainerEnvLists($c, "pihole", ["pihole-env"]);
 */
export func setContainerEnvLists(c as Client, name as string, listNames as list of string) {
    def id as string init requiredContainerId($c, $name);
    set($c, CONTAINER_PATH, $id, {"envlists": joinListNames($listNames, "env list")});
}

/**
 * Set the mount lists a container uses, replacing the previous ones.
 *
 * An empty list detaches all of them. Set it before the first start.
 *
 * @param c {Client} an open client
 * @param name {string} container comment or image tag
 * @param listNames {list of string} mount lists to attach
 * @throws {Error} kind "routeros" when no such container exists or a list
 *         name is empty or contains spaces
 * @example
 *   mt.setContainerMountLists($c, "pihole", ["pihole-etc"]);
 */
export func setContainerMountLists(c as Client, name as string, listNames as list of string) {
    def id as string init requiredContainerId($c, $name);
    set($c, CONTAINER_PATH, $id, {"mountlists": joinListNames($listNames, "mount list")});
}

/**
 * Delete every entry under a path that belongs to one named list.
 *
 * @param c {Client} an open client
 * @param path {string} env or mount list path
 * @param listName {string} list to clear
 * @param what {string} noun for the error message
 * @return {int} number of entries deleted
 * @throws {Error} kind "routeros" on an empty list name
 * @internal
 */
func removeListEntries(c as Client, path as string, listName as string, what as string) {
    ensureName($listName, $what);
    def rows as list of map of string to string init getAll($c, $path);
    def gone as int init 0;
    for (def row in $rows) {
        if (rowValue($row, "list") == $listName) {
            remove($c, $path, rowValue($row, ".id"));
            $gone = $gone + 1;
        }
    }
    return $gone;
}

/**
 * Validate and join list names into the comma-separated form RouterOS
 * wants in `envlists` / `mountlists`.
 *
 * @param listNames {list of string} the names to join
 * @param what {string} noun for the error message
 * @return {string} the joined names, "" for none
 * @throws {Error} kind "routeros" on an empty or space-containing name
 * @internal
 */
func joinListNames(listNames as list of string, what as string) {
    for (def name in $listNames) {
        ensureName($name, $what);
    }
    return strings.join($listNames, ",");
}

/**
 * Resolve a container to its id by comment or, failing that, image tag.
 *
 * @param c {Client} an open client
 * @param name {string} container comment or image tag
 * @return {string} the container id
 * @throws {Error} kind "routeros" when no such container exists
 * @internal
 */
func requiredContainerId(c as Client, name as string) {
    def rows as list of map of string to string init getAll($c, CONTAINER_PATH);
    for (def row in $rows) {
        if (rowValue($row, "comment") == $name or rowValue($row, "name") == $name) {
            return rowValue($row, ".id");
        }
    }
    raiseError("no container named \"" + $name + "\" was found");
}

/**
 * Fold a "/container/print" row into a Container.
 *
 * Newer builds send a `running` flag, older ones a `status` word; each
 * fills in for the other.
 *
 * @param row {map of string to string} the reply row
 * @return {Container} the typed container
 * @internal
 */
func containerFromRow(row as map of string to string) {
    def label as string init rowValue($row, "comment");
    if ($label == "") {
        $label = rowValue($row, "name");
    }
    def tag as string init rowValue($row, "tag");
    if ($tag == "") {
        $tag = rowValue($row, "name");
    }
    if ($tag == "") {
        $tag = rowValue($row, "remote-image");
    }
    def status as string init rowValue($row, "status");
    def running as bool init rowBool($row, "running") or $status == "running";
    if ($status == "") {
        $status = "stopped";
        if ($running) {
            $status = "running";
        }
    }
    return Container{
        id: rowValue($row, ".id"),
        name: $label,
        tag: $tag,
        status: $status,
        running: $running,
        interfaceName: rowValue($row, "interface"),
        rootDir: rowValue($row, "root-dir"),
        envLists: rowValue($row, "envlists"),
        mountLists: rowValue($row, "mountlists")
    };
}

/**
 * Fold a "/container/envs/print" row into a ContainerEnv.
 *
 * @param row {map of string to string} the reply row
 * @return {ContainerEnv} the typed variable
 * @internal
 */
func containerEnvFromRow(row as map of string to string) {
    return ContainerEnv{
        id: rowValue($row, ".id"),
        listName: rowValue($row, "list"),
        key: rowValue($row, "key"),
        value: rowValue($row, "value")
    };
}

/**
 * Fold a "/container/mounts/print" row into a ContainerMount.
 *
 * @param row {map of string to string} the reply row
 * @return {ContainerMount} the typed mount
 * @internal
 */
func containerMountFromRow(row as map of string to string) {
    return ContainerMount{
        id: rowValue($row, ".id"),
        listName: rowValue($row, "list"),
        src: rowValue($row, "src"),
        dst: rowValue($row, "dst")
    };
}
