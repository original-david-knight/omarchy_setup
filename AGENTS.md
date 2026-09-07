# Public and private setup boundary

This repository is public. Everything App is a private repository: keep its
source checkout/build provisioning and repository URL in
`~/workspace/omarchy-setup-private`.

The Everything App passcode and other credentials belong only in the private
setup repository and the local runtime configuration it deploys. Never copy
their values into this repository, including documentation, fixtures, or logs.
Public widgets may read credentials from local runtime configuration; they
must not embed credentials. Keep account sign-in steps in the private wizard
manifest, after the GitHub authentication and private checkout handoff.
