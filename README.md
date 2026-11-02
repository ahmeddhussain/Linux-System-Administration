# ahmed-infra

An enterprise-style Linux administration lab on AWS, for a fictional company
called **ahmed**. It runs the company layer a Linux administrator owns:
central identity, access control, endpoints, internet policy, file
services, logging and backups. Built on **RHEL 10**, with Terraform for
infrastructure and Ansible for configuration. Everything is code: the
whole lab is destroyed after each session and rebuilt from Git.

## What it does
| Area | How |
|---|---|
| Identity | FreeIPA on idm01: users, team groups, login rules (HBAC), sudo rules, SSH keys, DNS, certificates. Every host is enrolled. |
| Remote access | WireGuard VPN on gw01, carried inside TLS on TCP 443 (wstunnel). Each team's VPN range reaches only what its policy allows. |
| Network policy | Private subnets, default-deny security groups per role, every allowed flow declared in code; host firewalls as a second layer. |
| Internet policy | Workstations have no direct internet. Squid on util01: HTTPS only, social media and streaming blocked; allow-list only for some teams, enforced per user. |
| Home directories | NFSv4 from util01, mounted on demand through an automount map in FreeIPA. |
| Central logs | Every host sends its logs to util01 over TLS, authenticated by its FreeIPA certificate. |
| Backups | util01's data goes to a versioned S3 bucket before every teardown and is restored on rebuild. |
| Secrets | Ansible Vault, with the vault password in SSM Parameter Store; nothing secret in Git or Terraform state. |
| Verification | `scripts/test-lab.sh`: 120+ checks, including logging in as each user and proving what is allowed and what is refused. |

## Hosts
| Host | Role |
|---|---|
| gw01 | VPN gateway, the only host with a public address |
| control01 | Ansible control node (admin only) |
| idm01 | FreeIPA |
| util01 | Web proxy, NFS homes, central logs, backups |
| ws-dev01, ws-ops01 | Team workstations |

Teams, access rules and the checklist for adding a team:
[docs/architecture/org-structure.md](docs/architecture/org-structure.md).

## Repository layout
| Path | Contents |
|---|---|
| `terraform/` | The lab layer: network, security groups (`network-policy.tf`), hosts, IAM. Destroyed every session. |
| `terraform/persistent/` | What survives teardown: the Vault password, the backup bucket. |
| `terraform/bootstrap/` | The S3 bucket that holds every layer's Terraform state. |
| `ansible/` | Roles and playbooks; `playbooks/site.yml` configures everything in order. Runs on control01. |
| `ansible/inventory/group_vars/` | The data: identity, VPN policy, web policy. |
| `scripts/` | `lab.sh` (build, configure, test, teardown), `vpn-client.sh`, `test-lab.sh`. |
| `Decisions.md` | Every design decision, with the alternatives considered and why. |
| `docs/incident-reports/` | Real problems met while building, with evidence and root cause. |
| `docs/runbooks/` | How to operate the VPN client and FreeIPA. |

## Using it
Requires AWS credentials, Terraform >= 1.11, and an SSH agent on a Linux
laptop.

    eval "$(ssh-agent)"
    scripts/lab.sh up               # build, configure, test (about an hour from scratch)
    scripts/vpn-client.sh connect   # VPN to the company network
    ssh control01-vpn               # admin entry
    scripts/lab.sh verify           # rerun the checks
    scripts/lab.sh down             # back up util01, then destroy the lab

## Status
Done: network and access, Ansible Vault, FreeIPA, per-team VPN policy,
util01 services (proxy, NFS homes, logs, backups). Next: storage (quotas,
shared team directories), patching cadence, audit, restore drills, and an
application tier.
