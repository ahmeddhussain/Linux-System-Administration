# INC-004: fresh build hung on the workstations' first dnf task

| Field | Value |
|---|---|
| Date | 2026-11-02 |
| Severity | Medium: `lab.sh up` could not complete on a fresh lab; nothing lost |
| Status | Resolved in code (commit fad725b); first fresh build after the fix: see CLAUDE.md section 10 |
| Systems | ws-dev01, ws-ops01, util01 (Squid), control01 (controller) |

## Summary
The first `lab.sh up` after D-057 (workstations reach the web only through
Squid on util01) stopped making progress in `patch.yml` at "Install the
reboot-check tool" on ws-dev01. On a fresh lab the workstations had no
direct HTTPS egress, Squid did not exist yet, and dnf had no proxy
setting, so dnf waited on connections that could never be established.
D-057 had been built and tested on a running lab, where the workstations
were already patched before the proxy appeared.

## Timeline (UTC)
| Time | Event |
|---|---|
| 12:42 | Instances created by `lab.sh up` |
| 13:07:33 | patch.yml batch 2 (idm01, ws-dev01) starts "Install the reboot-check tool" |
| 13:07:46 | idm01 done; ws-dev01 never returns |
| 13:11:58 | On ws-dev01: a `SYN-SENT` connection to 44.197.135.178:443 (RHUI), no `proxy=` in dnf.conf |
| 13:13 | Module process found: PID 5395, a bare `python3.12` (pipelined module), owning that connection, holding no rpm database files |
| ~13:15 | Fix committed; stuck controller run and PID 5395 stopped; `lab.sh resume` started |

## Investigation
- The controller log showed the batch partner (idm01) finishing and
  ws-dev01 not returning: the wait was on one host.
- `ss state syn-sent` on ws-dev01 showed HTTPS to the internet not being
  answered: the workstation security groups no longer allow it (D-057).
- `pgrep -af AnsiballZ` and `grep dnf` found nothing at first: with
  pipelining the module runs as `python3.12` reading stdin, so neither name
  appears. `ps --forest` under the ansible user's sshd session found it.
- Before stopping it: no open files under `/var/lib/rpm` (still in the
  metadata download, no transaction), so stopping it was safe.

## Root cause
A build-order dependency introduced by D-057 and not tested from scratch:
workstations depend on Squid for packages, but `site.yml` patched every
host before util01 had Squid and before workstations had a proxy setting.

## Fix
`site.yml` now: patch util01, apply `base` and `web_proxy` to util01, set
the workstations' dnf proxy (by util01's IP, because IPA DNS does not exist
yet at that point), then patch all other hosts and continue as before.

## Lessons
- A design that removes a network path must be tested on a fresh build,
  not only on the running lab.
- With pipelining, look for the module as `python3` under the ansible
  user's sshd session (`ps --forest`), not by AnsiballZ or module name.
- `pkill -f <pattern>` inside `ssh host '...'` can match the ssh session's
  own command line and kill it; match a narrower pattern.

## Actions
| Action | Status |
|---|---|
| Reorder site.yml so Squid exists before workstations need packages | Done (fad725b) |
| Prove a complete fresh build (`lab.sh up` from nothing) | In progress |
