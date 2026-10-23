# Remove the temporary kernel security workaround after a confirmed fix

Recorded October 23, 2026. Status: pending a verified kernel fix for
ZDI-CAN-33367. The workaround has no automatic expiry.

The local file `/etc/modprobe.d/security-zdi-can-33367.conf` blocks these
modules from loading:

- `nlmon`, used for netlink packet monitoring.
- `act_pedit`, used for traffic-control packet editing.

Both modules were unloaded when the block was applied. The configuration is
also included in both installed kernels' boot images. It is a partial
mitigation for the demonstrated attack chain, not a complete kernel fix.
Unprivileged user namespaces remain enabled.

This is a local workaround, not a permanent setup default for other machines.
The [original report](https://lkml.iu.edu/2610.2/14824.html) and
[CloudLinux investigation](https://blog.cloudlinux.com/dirty-frag-v2-0-zdi-can-33367)
provide references for checking the eventual fix.

## When to remove it

- Confirm that the vendor's released kernel includes the fix for
  ZDI-CAN-33367. A newer version number alone is not sufficient.
- Install that kernel, reboot, and verify the running version with `uname -r`.
  Any fallback kernel you intend to boot must also contain the fix.
- Only then disable the workaround and rebuild all installed boot images:

```sh
sudo mv /etc/modprobe.d/security-zdi-can-33367.conf /etc/modprobe.d/security-zdi-can-33367.conf.disabled
sudo limine-mkinitcpio
```

The renamed file preserves a backup; modprobe reads files ending in `.conf`.
Check that every boot-image rebuild succeeds. These dry runs should no longer
resolve to `install /bin/false` from this workaround:

```sh
modprobe -n -v nlmon
modprobe -n -v act_pedit
```

Record the fixed kernel version and removal date here when complete.

## Changes that should stay

Keep the browser, certificate, Node.js, and other software updates. The signed
Arch packages installed directly were `nodejs 26.12.1-1`, `brotli 1.2.1-1`,
and `chromium 156.0.8078.47-1`. Normal updates can manage them when Omarchy's
mirror catches up; do not downgrade them to match an older mirror version.
The unused older Node installations do not need restoring. The temporary
update sleep inhibitor was already stopped.
