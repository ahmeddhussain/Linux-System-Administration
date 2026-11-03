# Organization Structure - Company "ahmed"

The company's people, hosts and access policy. Everything here is
enforced by code; the "Where" column of each section names the file that
implements it. Decisions: `Decisions.md` (D-0xx).

## Hosts
| Host | Role | Subnet | Private IP | Who uses it |
|---|---|---|---|---|
| gw01 | VPN gateway, the only host with a public address | public | 10.0.0.10 | Everyone connects through it; admin-only logins |
| control01 | Ansible control node | infra | 10.0.1.10 | Admin only |
| idm01 | FreeIPA identity, DNS, certificates | infra | 10.0.1.11 | All hosts, invisibly |
| util01 | Web proxy, NFS homes, central logs, backups | infra | 10.0.1.12 | All hosts, invisibly |
| ws-dev01 | Dev team workstation | workstation | 10.0.2.10 | Dev team, contractors |
| ws-ops01 | Ops and DBA workstation | workstation | 10.0.2.11 | Ops and DBA teams |
| app01 | Web and database tier (planned, Phase 10) | app | 10.0.3.10 | Teams, by permission |

Where: `terraform/variables.tf` (`hosts`). Fixed IPs must be inside the
subnet's reserved block `10.0.x.8/29` (D-062); a validation enforces it.

## VPN address plan
| Range | Who | May reach |
|---|---|---|
| 10.8.0.0/24 | Admin | control01, both workstations, IPA web UI, SSH to gw01 |
| 10.8.1.0/24 | Dev team | ws-dev01 |
| 10.8.2.0/24 | Ops team | ws-ops01, idm01, util01 |

Where: `ansible/inventory/group_vars/role_gateway/main.yml`
(`vpn_team_policy`, gw01's firewall, D-052) and
`terraform/network-policy.tf` (security groups, the second layer).

## Teams and policy
| Team | Example user | Can log into | sudo | Internet policy |
|---|---|---|---|---|
| admins | ahmed.admin | every host | everything | standard |
| dev | ahmed | ws-dev01 | none yet (restart the app service, with app01) | standard: social media and streaming blocked |
| ops | sara | ws-ops01, idm01, util01 | full, logged | standard |
| dba | omar | ws-ops01 | none yet (sudo -u postgres, with app01) | allow-list only |
| security | laila | util01 | audit tools only (journalctl, ausearch, aureport, last) | standard; reads the central logs |
| contractors | contractor1 | ws-dev01 | none | allow-list only; accounts expire (2026-12-31) |

- Logins are by SSH key only. control01 and gw01 are admin-only
  (D-010, D-051).
- "Standard" internet: any HTTPS site except the deny lists (social media,
  video and music streaming). AI assistants are allowed for work.
  "Allow-list": package repositories, GitHub and documentation only.
  No plain HTTP for anyone. Workstations reach the web only through the
  proxy (D-057).
- Home directories: `/users/<name>`, from util01 on the workstations
  (D-058); local on servers.

Where: `ansible/inventory/group_vars/role_idm/identity.yml` (users, groups,
login and sudo rules), `ansible/inventory/group_vars/all.yml`
(`web_proxy_team_policy`), `ansible/inventory/group_vars/role_util/web_policy.yml`
(domain lists).

## Access paths
- Admin: laptop -> VPN (admin range) -> control01 -> any host.
  Break-glass: AWS Instance Connect -> control01.
- Employees: laptop -> VPN (team range) -> their team's workstation;
  ops also to idm01 and util01 (D-053).
- Servers otherwise accept SSH only from control01.
- The only internet-facing port is TCP 443 on gw01 (WireGuard inside TLS,
  D-040).
- Every connection not listed in `terraform/network-policy.tf` is denied.

## Security operations
| What | Where the security team reads it (util01) | Produced by | Decision |
|---|---|---|---|
| Every host's logs | `/srv/logs/<fqdn>/<program>.log` | rsyslog over TLS | D-059 |
| Audit records (identity, sudoers, SSH, root commands) | `/srv/logs/<fqdn>/audit.log`: `sudo ausearch -if <file> -k <key>` | auditd + syslog plugin | D-063 |
| Daily audit summary per host | `/srv/logs/reports/audit-<date>.txt` | hourly timer | D-063 |
| CIS Level 1 results | `/srv/logs/reports/openscap/summary.txt`, `<fqdn>/report.html.gz` | `lab.sh compliance` (and every up/resume) | D-064 |
| Patch record | `/var/log/ahmed-patch.log` per host, `/srv/logs/<fqdn>/ahmed-patch.log` | every patch run | D-065 |
| Restore and incident drills | `/srv/logs/reports/drills/` | `lab.sh drill <name>` | D-066, D-067 |

Deliberate exceptions to CIS Level 1, each with its reason:
`compliance_exceptions` in `ansible/inventory/group_vars/all.yml`.
Hardening that applies to every host: `ansible/roles/hardening/`.

## Checklist: adding a new team (example: HR)
1. `identity.yml`: add group `hr` (next free GID), its users (next free
   UIDs, SSH keys), host group `hr-workstations`, an HBAC rule and a sudo
   rule (or none).
2. `terraform/variables.tf`: add `ws-hr01` to `hosts` (a free IP in
   `10.0.2.8/29`, D-062) with
   `security_group = "workstation-hr"`, and a VPN range `hr` to
   `vpn_ranges`. `terraform/network-policy.tf`: add `hr = "workstation-hr"`
   to `team_workstation_sg`. Plan, review, apply.
3. `role_gateway/main.yml`: add `hr` to `vpn_team_policy` (range and the
   hosts it may reach) and the team's VPN peers.
4. `all.yml`: add `hr` to `web_proxy_team_policy` if it should get the
   allow-list instead of the standard internet policy.
5. Run `site.yml`, add checks for the new team to `scripts/test-lab.sh`
   (login, sudo, VPN reach, web), and run `lab.sh verify`.
6. Record the change in `Decisions.md` if it changes a policy.
