# INC-003: base role failed on a fresh gw01, firewalld not ready

| Field | Value |
|---|---|
| Date | 2026-11-01 |
| Severity | Low: rebuild stopped on one host; no impact on running services |
| Status | Resolved (fix in the base role, commit 4729555) |
| Systems | gw01 (rebuilt for Vault Step 3), control01 (Ansible controller) |

## Summary
While gw01 was being rebuilt to prove that its WireGuard key survives a
rebuild, `site.yml` failed on gw01 in the base role: the firewalld module
reported "firewall is not currently running" one task after firewalld had
been started. The run stopped for gw01 before the gateway play. firewalld was
running normally seconds later.

## Impact
- `lab.sh resume` ended with exit 2; gw01 had no VPN configuration until the
  rerun. Admin access via Instance Connect was unaffected.

## Timeline (UTC, from ~/ansible.log on control01 and gw01's journal)
| Time | Event |
|---|---|
| 17:58:15 | patch.yml reboots gw01 (planned, after updates) |
| 17:58:23 | gw01 boots |
| 17:58:39 | base role installs baseline packages; firewalld installed for the first time |
| 17:59:06.69 | systemd: "Started firewalld.service" |
| 17:59:07.03 | `ansible.posix.firewalld` (service=ssh) invoked; fails by 17:59:07.64 |
| 17:59:08 | systemd: "Startup finished" (boot still completing, kdump building initramfs) |
| 17:59:41 | firewalld `active (running)`; `/var/log/firewalld` empty (no errors) |

## Investigation
- A reboot seen at first (uptime 1 min) was the planned patch reboot, not an
  unexpected one (log timestamps match).
- firewalld logged no errors and was healthy afterwards, so the daemon itself
  did not fail.
- The module ran 0.34 s after systemd reported the service started, on a host
  that was still finishing its boot.

## Root cause
Most likely a startup race. firewalld is a `Type=dbus` service: systemd marks
it started once it owns its D-Bus name, before it has loaded its
configuration. Until then firewalld reports "not running", and the module
fails immediately instead of waiting. Confidence: high, not proven (the
timing cannot be replayed). The race exists on every fresh host; earlier
rebuilds passed by timing.

## Actions
| Action | Status |
|---|---|
| base role: wait for `firewall-cmd --state` (15 x 2 s) before the first firewalld task | Done |
| Rerun resume on the rebuilt gw01 | See CLAUDE.md section 10 |
