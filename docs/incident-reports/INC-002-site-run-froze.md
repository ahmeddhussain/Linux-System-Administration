# INC-002: site.yml run froze during a rebuild

| Field | Value |
|---|---|
| Date | 2026-11-01 |
| Severity | Low: the rebuild stalled; no damage, a rerun succeeded |
| Status | Open, monitoring (instrumentation added) |
| Systems | control01 (Ansible controller), gw01 |

## Summary
During `scripts/lab.sh up`, the Ansible run on control01 stopped producing
output and did not progress for over 30 minutes. It was interrupted, and
`scripts/lab.sh resume` then completed normally (34 of 34 tests passed).

## Evidence (package history, UTC)
| Time | Event |
|---|---|
| 16:14 to 16:27 | Patch play completed in three batches of two hosts |
| 16:32 | Base role completed on all six hosts |
| after 16:32 | No package activity on gw01 until the rerun |
| 16:53 | Rerun installed WireGuard on gw01 |

No host was running a package task while the run was frozen, and no
network connection was waiting on a blocked destination. The run most
likely froze early in the gateway play, on gw01, before its first package
install.

## Possible causes (not yet distinguished)
1. A dead shared SSH connection (ControlPersist) to gw01 after its reboot.
2. A stalled HTTPS download of the EPEL signing key.

## Actions
| Action | Status |
|---|---|
| Log every Ansible run to ~/ansible.log on control01 | Done |
| SSH keepalives so dead connections fail in about a minute | Done |
| 30-minute task timeout so a hang fails with the host named | Done |
| On recurrence, read the log to identify the host and task | Open |