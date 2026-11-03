# ahmed-infra

An enterprise-style Linux administration lab on AWS, for a fictional company
called **ahmed**. It runs the company layer a Linux administrator owns:
central identity, access control, endpoints, internet policy, file
services, logging, audit, compliance, patching and backups. Built on
**RHEL 10**, with Terraform for infrastructure and Ansible for
configuration. Everything is code: the whole lab is destroyed after each
session and rebuilt from Git.

## What it does
| Area | How |
|---|---|
| Identity | FreeIPA on idm01: users, team groups, login rules (HBAC), sudo rules, SSH keys, DNS, certificates. Every host is enrolled. |
| Remote access | WireGuard VPN on gw01, carried inside TLS on TCP 443 (wstunnel). Each team's VPN range reaches only what its policy allows. SSH is key-only, proven by a test of what each server offers. |
| Network policy | Private subnets, default-deny security groups per role, every allowed flow declared in code; host firewalls as a second layer; fixed host IPs protected by subnet CIDR reservations. |
| Internet policy | Workstations have no direct internet. Squid on util01: HTTPS only, social media and streaming blocked; allow-list only for some teams, enforced per user. |
| File services | NFSv4 homes and team shares from util01 (automount maps in FreeIPA), user and team quotas, default ACLs. |
| Central logs | Every host sends its logs to util01 over TLS, authenticated by its FreeIPA certificate. |
| Audit | auditd rules on every host (identity, sudoers, SSH, root commands by real users), records central on util01 for the security team, hourly report. |
| Compliance | OpenSCAP CIS Level 1 on every host: **100%**, each rule not met a documented exception; a test fails if a host drops below its minimum. Hardening (kernel, network, SSH, PAM, sudo, crypto policy, AIDE) in one role. |
| Patching | Monthly cycle in rings (canary first, identity last) with health gates, urgent security-only cycle, a record of every run, rollback runbook. |
| Backups and drills | util01's data to a versioned S3 bucket; restore drills measure RPO and RTO against targets; incident drills (identity outage, log disk full, package rollback) with reports. |
| Secrets | Ansible Vault, with the vault password in SSM Parameter Store; nothing secret in Git or Terraform state. |
| Verification | `scripts/test-lab.sh`: 158 checks, including logging in as each user and proving what is allowed and what is refused. |

## Hosts
| Host | Role |
|---|---|
| gw01 | VPN gateway, the only host with a public address |
| control01 | Ansible control node (admin only) |
| idm01 | FreeIPA |
| util01 | Web proxy, NFS homes and team shares, central logs and audit, backups |
| ws-dev01, ws-ops01 | Team workstations |

Teams, access rules and the checklist for adding a team:
[docs/architecture/org-structure.md](docs/architecture/org-structure.md).

## Repository layout
| Path | Contents |
|---|---|
| `terraform/` | The lab layer: network, security groups (`network-policy.tf`), hosts, IAM. Destroyed every session. |
| `terraform/persistent/` | What survives teardown: the Vault password, the backup bucket. |
| `terraform/bootstrap/` | The S3 bucket that holds every layer's Terraform state. |
| `ansible/` | Roles and playbooks; `playbooks/site.yml` configures everything in order, `compliance.yml` scans, `patch-cycle.yml` patches, `drills/` holds the drills. Runs on control01. |
| `ansible/inventory/group_vars/` | The data: identity, VPN policy, web policy, storage, compliance minimums and exceptions. |
| `scripts/` | `lab.sh` (build, configure, scan, patch, drill, test, teardown), `vpn-client.sh`, `test-lab.sh`. |
| `Decisions.md` | Every design decision, with the alternatives considered and why. |
| `docs/incident-reports/` | Real problems met while building, with evidence and root cause. |
| `docs/drills/` | Planned incident drills and their measured results. |
| `docs/runbooks/` | Operating the VPN client, FreeIPA, storage and patching. |

## Using it
Requires AWS credentials, Terraform >= 1.11, and an SSH agent on a Linux
laptop.

    eval "$(ssh-agent)"
    scripts/lab.sh up               # build, configure, scan, restore drill, test (about an hour)
    scripts/vpn-client.sh connect   # VPN to the company network
    ssh control01-vpn               # admin entry
    scripts/lab.sh verify           # rerun the checks
    scripts/lab.sh compliance       # rerun the CIS scan
    scripts/lab.sh patch            # patch cycle in rings (--security: errata only)
    scripts/lab.sh drill restore    # or idm-outage, logs-disk-full, package-rollback
    scripts/lab.sh down             # back up util01, then destroy the lab

## Status
Done: network and access, Ansible Vault, FreeIPA, per-team VPN policy,
util01 services (proxy, NFS homes, logs, backups), storage (quotas, team
shares), audit, CIS Level 1 compliance and hardening, patching cadence,
restore and incident drills. Next: an application tier (app01).
