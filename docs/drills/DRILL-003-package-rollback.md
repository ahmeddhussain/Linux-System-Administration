# DRILL-003: package rollback on the canary

| Field | Value |
|---|---|
| Date | 2026-11-03 |
| Playbook | `ansible/playbooks/drills/package-rollback.yml` (`scripts/lab.sh drill package-rollback`) |
| Decision | D-065 (runbook), D-067 |
| Result | PASS |

## Scenario
"The last update broke a tool on ws-dev01." Practice the rollback of
`docs/runbooks/patching.md` on one package, check the host, then patch
forward again (normally only once the fix is released).

## Result (measured)
| Step | Result |
|---|---|
| Version before | rsync-3.5.0-3.el10_2 |
| `dnf downgrade rsync` | rsync-3.4.4-1.el10_2, in **4 s** |
| Host healthy on the old version | no failed services |
| Patch forward | back to rsync-3.5.0-3.el10_2 |

## Notes
- rsync was chosen because it has older versions in the repositories and
  nothing in the lab depends on its version; tmux, the first choice, has
  only one version in RHEL 10, so it cannot be downgraded.
- A downgrade needs the older package to still be in the repository; for a
  kernel the previous version stays installed instead (`grubby`).
