# Router users

File: `src/topics/users.j`. Paths: `/user` (`USER_PATH`),
`/user/group` (`USER_GROUP_PATH`), `/user/active` (`USER_ACTIVE_PATH`).
Reference: [cheatsheet](cheatsheet.md#router-users).

Permissions come from the account's group. The built-ins are `full`
(everything), `write` (configure, no user or package management) and
`read` (look only); custom groups combine individual policies. The API
login the deck uses needs the `api` policy; a `read` account can call
every listing function.

Passwords are write-only: set by `addUser` or `setUserPassword`, never
read back. The deck rejects an empty password, although RouterOS allows
one.

```jennifer
# a read-only monitoring account, reachable only from the management network
mt.addUser($c, "monitoring", "a long random password", mt.GROUP_READ);
mt.restrictUser($c, "monitoring", "10.0.9.0/24,192.168.88.10");

mt.disableUser($c, "kim");     # keeps the account
mt.removeUser($c, "kim");      # deletes it

def sessions as list of mt.UserSession init mt.activeUsers($c);
for (def s in $sessions) {
    io.printf("%s via %s from %s since %s\n", $s.name, $s.via, $s.address, $s.when);
}
```

## Self-protection

The `Client` records the account it logged in as. `removeUser`,
`disableUser` and `setUserGroup` refuse that account with
`kind: "routeros"`:

```jennifer
# logged in as "admin":
mt.removeUser($c, "admin");
# refusing to remove "admin" - it is the account this session is logged in as
```

The guard is per session. A second admin account can still remove the
first, and nothing stops you demoting or disabling the last `full` user
from another account.

## Notes

- `restrictUser` applies to new logins. Restricting your own account does
  not drop the current session, but the next login must come from a
  listed network.
- `setUserPassword` leaves the user's existing sessions alive; disabling
  the account stops new logins.
- Password strength beyond non-empty is the caller's job; Jennifer's
  `password` module generates strong ones.
- Scheduled tasks run with their creator's policies
  ([scheduler.md](scheduler.md)); `reboot` needs the `reboot` policy
  ([system.md](system.md)).
