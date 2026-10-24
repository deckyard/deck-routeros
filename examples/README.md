# routeros examples

One example per topic file in `src/topics/`. Each connects, prints that topic's
state and leaves the mutating calls commented out, so running one changes
nothing on the router.

```sh
MT_HOST=192.168.88.1 MT_USER=admin MT_PASSWORD=secret jennifer run examples/firewall.j
```

The examples import `../src/routeros.j` as `mt` and exit 1 with a usage line
unless `MT_HOST` and `MT_USER` are set. Guides: [../docs/index.md](../docs/index.md);
reference: [../docs/cheatsheet.md](../docs/cheatsheet.md).
