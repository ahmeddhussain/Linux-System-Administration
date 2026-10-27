# ahmed-infra

Enterprise-style Linux administration lab for the fictional company **ahmed**,
built on AWS EC2 with Rocky Linux 9 (RHEL-compatible).

## Hosts
| Host | Role |
|---|---|
| control01 | Ansible control node, bastion |
| idm01 | FreeIPA identity, DNS, NTP |
| web01 | Nginx application tier |
| db01 | PostgreSQL database |
| util01 | Logging, monitoring, backups, local repo |

## Structure
- `terraform/`  - infrastructure (VPC, instances, volumes)
- `ansible/`    - configuration management (roles, playbooks, inventory)
- `docs/`       - runbooks, incident reports, architecture
- `tickets/`    - simulated requests from teams
- `DECISIONS.md` - every design choice, with alternatives considered

## Status
Phase 0: Foundation (in progress)