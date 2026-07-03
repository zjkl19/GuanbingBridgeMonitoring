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

