# DRILL-004: restore drill (util01 data)

| Field | Value |
|---|---|
| Date | 2026-11-03 |
| Command | `ahmed-backup drill` (`scripts/lab.sh drill restore`; also every `lab.sh up` and `resume`) |
| Decision | D-066 |
| Result | PASS, every target met |

## Scenario
1. A user deletes a file and opens a ticket: restore that one file.
2. util01's data volume is lost: restore everything (into a scratch
   directory, compared with the live data).

## Result (measured, 2026-11-03 18:38 UTC)
| Measure | Result | Target |
|---|---|---|
| RPO (data at risk: since the last backup or the volume's creation) | 649 s | 24 h |
| Backup (homes, team shares, logs) | 3 s | |
| Single-file RTO (content, owner by name, SELinux label checked) | 1 s | 5 min |
| Full-data RTO (98 MB; homes and team shares identical to live) | 2 s | 15 min |

Every run appends a line to `/srv/logs/reports/drills/restore-drills.log`;
`test-lab.sh` fails if the last one is not PASS.

## Notes
- The full RTO covers the data only. Recovering util01 itself means
  rebuilding the host from code (`terraform -replace`, `lab.sh resume`),
  whose restore step is the same command; rebuilding the whole lab from
  Git takes about an hour (`lab.sh up`).
- The numbers are small because the data is small; the drill's value is
  that the whole path (S3, tar, owners by name, labels) is proven every
  session.
