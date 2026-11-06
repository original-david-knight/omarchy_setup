# Tailscale keepalive

This machine should always be on the tailnet: sshd accepts connections only on
`tailscale0` (`install_services.sh`), so a logged-out node cannot be reached
remotely.

`tailscaled.service` is enabled and restarts on failure, and it remembers
`WantRunning` across reboots. Two things it does not handle on its own:

- **Stopped** (`tailscale down`): the node stays down until someone runs
  `tailscale up`.
- **Needs login**: the node key expired, or the device was logged out or
  removed in the admin console. Tailscale silently drops off the tailnet.

`tailscale-keepalive` (`bin`), run by `tailscale-keepalive.service` (`desktop`,
enabled by `activate.sh`), checks `tailscale status` every minute:

| State | Action |
| --- | --- |
| `Running` | nothing |
| `Stopped` | `tailscale up` |
| `NeedsLogin`, `NeedsMachineAuth` | starts a login and posts a critical notification with a **Sign in** button that opens the login URL; repeats hourly until signed in |
| anything else | nothing (transient; systemd restarts `tailscaled`) |

Logging in needs a browser, so the script cannot do it alone. To stop key
expiry from causing this, disable key expiry for the machine in the Tailscale
admin console (Machines → … → Disable key expiry).

`tailscale up` and `tailscale login` run without sudo because
`install_services.sh` makes the user the Tailscale operator.

```bash
tailscale-keepalive check                 # prints the state; exit 0 when Running
journalctl --user -u tailscale-keepalive  # what it did
```

`./verify.sh` reports **Tailscale running** as pending until the node is signed in.
