# Organization Structure - Company "ahmed"

## Hosts
| Host | Role | Subnet | Private IP | Who uses it |
|---|---|---|---|---|
| gw01 | VPN gateway: only host with a public address | public | 10.0.0.10 | Everyone connects through it |
| control01 | Ansible control node, Git | infra | 10.0.1.10 | Admin only |
| idm01 | FreeIPA identity, DNS | infra | 10.0.1.11 | All hosts, invisibly |
| util01 | Squid proxy, NFS homes, central logs, backups | infra | 10.0.1.12 | All hosts, invisibly |
| ws-dev01 | Dev team workstation | workstation | 10.0.2.10 | Dev team, contractors |
| ws-ops01 | Ops and DBA workstation | workstation | 10.0.2.11 | Ops and DBA teams |
| app01 | Web and database tier (added in Phase 10) | app | 10.0.3.x | Teams, by permission |

## VPN address plan
| Range | Who |
|---|---|
| 10.8.0.0/24 | Admin |
| 10.8.1.0/24 | Dev team |
| 10.8.2.0/24 | Ops team |

## Teams and policy
| Team | Example user | Can log into | sudo | Internet policy |
|---|---|---|---|---|
| dev | ahmed | ws-dev01, app01 (deploy only) | restart the app service only | General web, GitHub, package repos; social media and streaming blocked |
| ops | sara | ws-ops01, all servers | full sudo, logged | Social media blocked |
| dba | omar | ws-ops01, app01 (database) | sudo -u postgres only | Social media blocked; no general browsing |
| security | laila | read-only access to logs on util01 | audit tools only | Unrestricted, fully logged |
| contractors | temporary accounts | ws-dev01 only | none | Default deny, allow-list only; accounts expire automatically |

## Access paths
- Admin: laptop -> VPN (admin range) -> control01 -> any host
- Employees: laptop -> VPN (team range) -> their team's workstation
  (gw01's firewall limits each team range to its own workstations)
- Servers accept SSH only from control01
- The only internet-facing port is UDP 51820 on gw01
- Every connection not listed in terraform/main.tf is denied

## Checklist: adding a new team (example: HR)
1. FreeIPA: create user group `hr` and host group `hr-workstations`
2. FreeIPA: create the HBAC rule (who may log into which hosts)
3. FreeIPA: create the sudo rule (or none)
4. util01: add the team's Squid ACL (internet policy)
5. Terraform: add a VPN range for the team (`vpn_ranges`) and `ws-hr01`
   to the `hosts` map, then apply
6. gw01: add the team's VPN peers and firewall rule
7. Ansible: add `hr-workstations` to the inventory and group_vars, then run
   the workstation playbook
8. Create the first users, test login, test the blocked sites, and record
   the change as a ticket in `tickets/`