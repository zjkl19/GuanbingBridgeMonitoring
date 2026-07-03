# Guanbing Operations Notes

This directory records the remote-control layer around the Guanbing data
processing project. It is intentionally separate from algorithm and report
generation code.

Use these files as the first stop when remote machines, storage, SSH, RDP, or
long-running scheduled tasks are involved:

- `machines.md`: machine inventory and connection policy.
- `current_remote_state.md`: current recoverable remote task state.
- `ssh_config.template`: non-sensitive SSH config template.

Sensitive values do not belong here:

- passwords
- VPN passwords
- private keys
- one-time tokens
- unrestricted public port mappings

Local helper scripts live in `scripts/ops/`.

Machine-specific Guanbing paths are handled in source-controlled
`config/path_profiles.json` plus optional untracked
`config/path_profiles.local.json`. Prefer this mechanism over editing
`config/bridge_profiles.json` when the same bridge data root differs between
the developer PC, 133 compute machine, and 126 storage server. Set
`GUANBING_PATH_PROFILE=<profile_id>` to force a profile during tests.
