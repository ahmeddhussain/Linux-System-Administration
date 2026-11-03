# Runbook: patching (D-065)

## Cadence
| Cycle | When | Command | Scope |
|---|---|---|---|
| Monthly | first Saturday after Red Hat's monthly errata, 02:00 UTC | `scripts/lab.sh patch` | all updates |
| Urgent | within 7 days of a Critical or Important security advisory | `scripts/lab.sh patch --security` | security errata only |
| New or rebuilt host | every `lab.sh up` / `resume` (first step of site.yml) | automatic | all updates |

In this lab every session starts with a full patch (the lab is rebuilt
each session), so the monthly cycle is exercised with `lab.sh patch`.

## What the cycle does
1. Rings, in order, each followed by a gate (`patch-gate.yml`):
   | Ring | Hosts | Why this order |
   |---|---|---|
   | 1 | ws-dev01 | canary: least critical, same OS as the rest |
   | 2 | ws-ops01, util01 | users' homes, proxy and logs after the canary proved the update |
   | 3 | gw01, idm01 | VPN and identity only after everything else works on the new level |
   | 4 | control01 | runs the cycle; reports a needed reboot, never reboots itself |
2. Per host (`patch.yml`): free space >= 1 GB on `/` and `/var`; list of
   services already failed; update; `sshd -t`; reboot if
   `dnf needs-restarting -r` says so; no service newly failed; record.
3. The gate checks that every host of the ring finished and that IPA
   (`ipactl status`), SSSD (online), util01 (nfs-server, squid, rsyslog)
   and the VPN (wg-quick@wg0, wstunnel) answer. A failure ends the cycle.
4. `lab.sh patch` then runs the full test suite.

## Records
- Each host: `/var/log/ahmed-patch.log`, one line per run:
  `2026-11-03T18:00:00Z full dnf history 12: 34 package changes; reboot=yes; kernel=...`
- Centrally: the same line in syslog (`ahmed-patch`), stored on util01 in
  `/srv/logs/<fqdn>/ahmed-patch.log` (not for the very first patch of a
  new lab, which runs before central logging exists).
- Package detail: `sudo dnf history info <ID>` on the host.

## Rollback
| Problem | Action |
|---|---|
| One package broke a service | `sudo dnf history info <ID>` to find it; `sudo dnf history undo <ID>` (or `dnf downgrade <pkg>`); restart the service; then exclude it (`excludepkgs=` in the repo file) until fixed, in code |
| New kernel does not boot or misbehaves | the previous kernel stays installed: `sudo grubby --info=ALL`, `sudo grubby --set-default <previous vmlinuz>`, reboot; through the EC2 serial console if SSH is gone |
| Host unusable | rebuild it from code: `terraform -replace` on the host, then `lab.sh resume` (release it in IPA first, see the FreeIPA runbook) |
| Cycle stopped at a gate | later rings are untouched; fix or roll back the failed host, then rerun `lab.sh patch` (finished hosts have nothing left to do) |

After any rollback, write an incident report (`docs/incident-reports/`).
