# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# routeros - white-box tests for the container topic.
# Spliced into routeros_test.j via include - run with:
#   jennifer test src/routeros_test.j

func testContainerFromRowRunning() {
    def row as map of string to string init {
        ".id": "*1",
        "name": "pihole",
        "tag": "pihole/pihole:latest",
        "status": "running",
        "interface": "veth1",
        "root-dir": "usb1/pihole"
    };
    def ct as Container init containerFromRow($row);
    testing.assertEqual($ct.name, "pihole");
    testing.assertEqual($ct.tag, "pihole/pihole:latest");
    testing.assertEqual($ct.status, "running");
    testing.assertTrue($ct.running);
    testing.assertEqual($ct.interfaceName, "veth1");
    testing.assertEqual($ct.rootDir, "usb1/pihole");
}

func testContainerFromRowStoppedNamedByComment() {
    def row as map of string to string init {
        ".id": "*2",
        "comment": "adguard",
        "status": "stopped",
        "tag": "adguard/adguardhome:latest"
    };
    def ct as Container init containerFromRow($row);
    testing.assertEqual($ct.name, "adguard");
    testing.assertFalse($ct.running);
    testing.assertEqual($ct.status, "stopped");
}

func testContainerFromRowPrefersCommentOverImageTag() {
    # RouterOS 7.21.5 reports "name" as the image tag, read-only.
    def row as map of string to string init {
        ".id": "*4",
        "name": "pihole:latest",
        "comment": "pihole",
        "interface": "veth-pihole",
        "root-dir": "/usb1-part1/pihole/rootfs",
        "running": "true"
    };
    def ct as Container init containerFromRow($row);
    testing.assertEqual($ct.name, "pihole");
    testing.assertEqual($ct.tag, "pihole:latest");
    testing.assertTrue($ct.running);
    testing.assertEqual($ct.status, "running");
}

func testContainerFromRowRunningFromPlainBool() {
    def row as map of string to string init {".id": "*4", "comment": "pihole", "running": "false"};
    def ct as Container init containerFromRow($row);
    testing.assertFalse($ct.running);
    testing.assertEqual($ct.status, "stopped");
}

func testContainerFromRowTagFallsBackToRemoteImage() {
    def row as map of string to string init {
        ".id": "*5",
        "comment": "adguard",
        "remote-image": "adguard/adguardhome:latest"
    };
    def ct as Container init containerFromRow($row);
    testing.assertEqual($ct.tag, "adguard/adguardhome:latest");
    testing.assertEqual($ct.name, "adguard");
}

func testContainerFromRowCarriesLists() {
    def row as map of string to string init {
        ".id": "*4",
        "comment": "pihole",
        "envlists": "pihole-env",
        "mountlists": "pihole-etc,pihole-dnsmasq"
    };
    def ct as Container init containerFromRow($row);
    testing.assertEqual($ct.envLists, "pihole-env");
    testing.assertEqual($ct.mountLists, "pihole-etc,pihole-dnsmasq");
}

func testContainerEnvFromRow() {
    def row as map of string to string init {
        ".id": "*1",
        "list": "pihole-env",
        "key": "TZ",
        "value": "Europe/Vienna"
    };
    def e as ContainerEnv init containerEnvFromRow($row);
    testing.assertEqual($e.listName, "pihole-env");
    testing.assertEqual($e.key, "TZ");
    testing.assertEqual($e.value, "Europe/Vienna");
}

func testContainerMountFromRow() {
    def row as map of string to string init {
        ".id": "*2",
        "list": "pihole-etc",
        "src": "usb1/pihole/etc",
        "dst": "/etc/pihole"
    };
    def m as ContainerMount init containerMountFromRow($row);
    testing.assertEqual($m.listName, "pihole-etc");
    testing.assertEqual($m.src, "usb1/pihole/etc");
    testing.assertEqual($m.dst, "/etc/pihole");
}

func testJoinListNames() {
    testing.assertEqual(joinListNames(["a", "b"], "env list"), "a,b");
    def none as list of string init [];
    testing.assertEqual(joinListNames($none, "env list"), "");
}

func failJoinListNamesEmptyEntry() {
    joinListNames(["ok", ""], "env list");
}

func testJoinListNamesRejectsEmptyEntry() {
    testing.assertThrows("failJoinListNamesEmptyEntry", "routeros");
}

# Verbs: local validation before any I/O

func failAddContainerEmptyImage() {
    addContainer(offlineClient(), "pihole", "  ", "veth1", "usb1/pihole");
}

func testAddContainerRejectsEmptyImage() {
    testing.assertThrows("failAddContainerEmptyImage", "routeros");
}

func failAddContainerEnvEmptyKey() {
    addContainerEnv(offlineClient(), "piholeenv", "", "Europe/Vienna");
}

func testAddContainerEnvRejectsEmptyKey() {
    testing.assertThrows("failAddContainerEnvEmptyKey", "routeros");
}

func failAddContainerMountEmptyDst() {
    addContainerMount(offlineClient(), "piholemounts", "usb1/pihole/etc", "");
}

func testAddContainerMountRejectsEmptyDst() {
    testing.assertThrows("failAddContainerMountEmptyDst", "routeros");
}

func failRemoveContainerEnvListSpaced() {
    removeContainerEnvList(offlineClient(), "pihole env");
}

func testRemoveContainerEnvListRejectsSpacedName() {
    testing.assertThrows("failRemoveContainerEnvListSpaced", "routeros");
}

func failRemoveContainerMountListEmpty() {
    removeContainerMountList(offlineClient(), "");
}

func testRemoveContainerMountListRejectsEmptyName() {
    testing.assertThrows("failRemoveContainerMountListEmpty", "routeros");
}

func containerFake() {
    return fakeWithRows(
        fakeRouter(),
        CONTAINER_PATH,
        [
            {".id": "*1", "name": "postgres:16", "tag": "postgres:16"},
            {".id": "*2", "name": "pihole:latest", "comment": "postgres:16"}
        ]);
}

func testRemoveContainerRefusesEmptyName() {
    def f as Fake init fakeStart(containerFake());
    def c as Client init fakeClient($f);
    def got as string init "";
    try {
        removeContainer($c, "");
    } catch (e) {
        $got = $e.kind;
    }
    def log as list of string init fakeLog($c, $f);
    testing.assertEqual($got, "routeros");
    testing.assertFalse(fakeSaw($log, "/container/remove"));
}

func testContainerCommentWinsOverTag() {
    def f as Fake init fakeStart(containerFake());
    def c as Client init fakeClient($f);
    stopContainer($c, "postgres:16");
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/container/stop =.id=*2"));
}

func testRemoveContainerEnvListBatches() {
    def r as FakeRouter init fakeWithRows(
        fakeRouter(),
        CONTAINER_ENVS_PATH,
        [
            {".id": "*1", "list": "db", "key": "A", "value": "1"},
            {".id": "*2", "list": "web", "key": "B", "value": "2"},
            {".id": "*3", "list": "db", "key": "C", "value": "3"}
        ]);
    def f as Fake init fakeStart($r);
    def c as Client init fakeClient($f);
    testing.assertEqual(removeContainerEnvList($c, "db"), 2);
    def log as list of string init fakeLog($c, $f);
    testing.assertTrue(fakeSaw($log, "/container/envs/print =.proplist=.id,list ?list=db"));
    testing.assertTrue(fakeSaw($log, "/container/envs/remove =.id=*1,*3"));
}
