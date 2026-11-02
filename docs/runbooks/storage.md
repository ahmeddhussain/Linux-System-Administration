# Storage on util01: operating runbook

Design: D-056 (data volume, backups) and D-061 (second disk, quotas, team
shares). Workstations hold no user data; everything is on util01.

## Layout
| Volume | Size | Mount | Quotas | Seen on workstations as |
|---|---|---|---|---|
| `vg_data/lv_home` | 12 G | `/export/home` | per user (XFS user quota) | `/users/<name>` |
| `vg_data/lv_teams` | 8 G | `/export/teams` | per team (XFS project quota) | `/teams/<team>` |
| `vg_data/lv_logs` | 6 G | `/srv/logs` | none | (util01 only) |

`vg_data` spans util01's data disks (`extra_volumes` in
`terraform/variables.tf`). Everything above is backed up to S3.

## Where the settings live
| What | File |
|---|---|
| Disks | `terraform/variables.tf` (util01 `extra_volumes`), `util_storage_disk_count` in `roles/util_storage/defaults/main.yml` |
| Volume sizes, mount options | `roles/util_storage/defaults/main.yml` (`util_storage_volumes`) |
| Default quotas, team shares | `ansible/inventory/group_vars/role_util/storage.yml` |
| A user's own home quota | `home_quota` on the user in `role_idm/identity.yml` |

## Common tasks
- **Add space:** add a volume to util01's `extra_volumes`, raise
  `util_storage_disk_count`, raise a size in `util_storage_volumes`, apply
  Terraform, run `site.yml`. The role adds only blank disks and grows
  volumes online (`lvextend --resizefs`).
- **Change a quota:** edit `storage.yml` or the user's `home_quota`, run
  `site.yml`. Limits are only set when they differ.
- **Add a team share:** add the team to `team_shares` (the IPA group must
  exist in `identity.yml`), run `site.yml`.

## Checks (on util01 as root)

    pvs; vgs; lvs vg_data
    xfs_quota -x -c 'report -u -h' /export/home     # per-user usage and limits
    xfs_quota -x -c 'report -p -h' /export/teams    # per-team usage and limits
    getfacl -p /export/teams/dev                    # default ACL: group:dev:rwx

Over NFSv4 the workstations do not show these POSIX ACLs (`getfacl` there
reports nothing useful); check them on util01.

## Notes
- XFS cannot turn quotas on with a remount. If a mount lacks them, the role
  stops NFS, unmounts and mounts again.
- A restore brings files back by owner name (D-056 as built); project IDs
  are re-applied by `team_shares` when a check finds untagged files.
