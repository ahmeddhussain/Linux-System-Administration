# PROJECT_HANDOFF.md: ahmed-infra

Handoff for a fresh Claude Code session (written 2026-11-03, verified against
the repository at commit `c30f4a0`). Read `CLAUDE.md` first for the working
rules; this file is the project's memory. Details live in `Decisions.md`
(D-001 to D-062), `docs/incident-reports/` (INC-001 to INC-006) and
`docs/runbooks/`.

---

## 1. Overview and objectives

An enterprise-style **Linux administration lab on AWS**, a portfolio project for
Ahmed (Linux / Cloud / DevOps job readiness). A fictional company, **ahmed**,
with teams (dev, ops, dba, security, contractors). Ahmed plays its Linux
administrator. The focus is the company layer an admin owns: identity, access,
endpoints, internet policy, file services, logging, backups. Workloads (app01)
come later as tenants.

Principles: Terraform builds, Ansible configures, everything is code. **The lab
layer is destroyed after every session and rebuilt from Git**; anything not in
code is lost by design. Verification is `scripts/test-lab.sh` (logs in as real
users and proves allowed and denied paths).

GitHub: `github.com/ahmeddhussain/Linux-System-Administration` (public).

---

## 2. Architecture

### Network (VPC 10.0.0.0/16, us-east-1a)
| Subnet | CIDR | Hosts |
|---|---|---|
| public | 10.0.0.0/24 | gw01 (Elastic IP), NAT gateway |
| infra | 10.0.1.0/24 | control01 .10, idm01 .11, util01 .12, Instance Connect Endpoint |
| workstation | 10.0.2.0/24 | ws-dev01 .10, ws-ops01 .11 |
| app | 10.0.3.0/24 | empty (app01 planned) |

### Hosts (RHEL 10, patched to 10.2)
| Host | Type | Disks | Role |
|---|---|---|---|
| gw01 | t3.small | 20 GiB | WireGuard-in-TLS VPN gateway; the only public host; admin-only logins |
| control01 | t3.small | 20 GiB | Ansible control node; admin only; runs all Ansible and the tests |
| idm01 | c7i-flex.large (4 GB) | 20 GiB | FreeIPA: identity, DNS, CA |
| util01 | t3.small | 20 GiB + data 20 + 10 GB | Squid, NFS homes and team shares, central logs, backups |
| ws-dev01, ws-ops01 | t3.small | **10 GiB OS only** | team workstations; no user data locally |

### Access
- Admin: laptop -> VPN (wstunnel on TCP 443, WireGuard inside) -> `ssh control01-vpn` -> any host.
- Break-glass: `ssh control01` through the AWS EC2 Instance Connect Endpoint.
- Employees: VPN team range -> their workstation (ops also idm01/util01).
- Only internet-facing port: TCP 443 on gw01. Servers accept SSH only from
  control01 (plus the per-team VPN exceptions above).

### Services
- **FreeIPA** on idm01: realm `AHMED.INTERNAL`, integrated DNS (forwarding to
  the VPC resolver) and CA, no `allow_all` HBAC rule, fixed ID range with
  explicit UID/GID per user and group. All other hosts are enrolled.
- **VPN policy** on gw01: firewalld zone per team range, forwarding policy per
  team, written as whole XML files; security groups as a second layer.
- **util01:** LVM `vg_data` on two disks (`lv_home` 12 G, `lv_teams` 8 G,
  `lv_logs` 6 G); NFSv4 homes at `/users/<name>` and team shares at
  `/teams/<team>` via IPA automount maps; XFS user and project quotas; Squid
  (HTTPS only; port 3128 standard policy, 3129 allow-list); rsyslog over TLS
  with IPA certificates; tar + awscli2 backups to S3.

### Teams and policy (as built; source: `docs/architecture/org-structure.md`)
| Team | Example user | Logins | sudo | Internet |
|---|---|---|---|---|
| admins | ahmed.admin | everywhere | all | standard |
| dev | ahmed | ws-dev01 | none yet | standard (no social/streaming) |
| ops | sara | ws-ops01, idm01, util01 | all | standard |
| dba | omar | ws-ops01 | none yet | allow-list |
| security | laila | util01 (reads central logs) | audit tools | standard |
| contractors | contractor1 (expires 2026-12-31) | ws-dev01 | none | allow-list, 50 MB home |

---

## 3. Repository structure

| Path | Contents |
|---|---|
| `terraform/` | Lab layer (destroyed each session): `main.tf` (module calls), `network-policy.tf` (all security group roles, flows, CIDR rules), `hosts.tf`, `variables.tf` (all variables incl. the `hosts` map), `iam.tf`, `access.tf`, `vpn.tf`, `compute.tf`, `moved.tf`, `outputs.tf`, `tests/` |
| `terraform/modules/` | `network`, `security-groups`, `ec2-instance` (each with `versions.tf`; tests in the first two) |
| `terraform/persistent/` | Survives teardown: SSM Vault password (write-only), S3 backup bucket |
| `terraform/bootstrap/` | The state bucket itself (adopted with `import`) |
| `ansible/playbooks/` | `site.yml` (everything, in order), `idm.yml` (IPA, roles only), `patch.yml`, `bootstrap.yml` |
| `ansible/roles/` | `base`, `audit`, `wireguard_gateway`, `ipa_server_verify`, `ipa_client_prepare`, `ipa_client_health`, `ipa_identity`, `ipa_client_config`, `util_storage`, `log_server`, `log_forwarder`, `nfs_server`, `nfs_client`, `team_shares`, `web_proxy`, `proxy_client` |
| `ansible/inventory/` | `aws_ec2.yml` (dynamic inventory); `group_vars/`: `all.yml`, `ipaclients.yml`, `role_control.yml`, `role_gateway/{main,vault}.yml`, `role_idm/{main,vault,identity}.yml`, `role_util/{storage,web_policy}.yml` |
| `ansible/tests/` | Encrypted private test keys (IPA users, VPN test peers) |
| `ansible/scripts/vault-password.py` | Vault password from SSM |
| `scripts/` | `lab.sh` (+ `lib/`), `vpn-client.sh`, `test-lab.sh`, `control01-setup.sh` |
| `Decisions.md` | Every decision with alternatives and reasons (D-001 to D-062) |
| `docs/` | `architecture/` (org-structure, FreeIPA options), `incident-reports/`, `runbooks/` (vpn-client, freeipa, storage) |

Where to change things (data, not code): users/groups/HBAC/sudo/IDs in
`role_idm/identity.yml`; VPN peers and per-team VPN policy in
`role_gateway/main.yml`; web lists in `role_util/web_policy.yml`; team to
web-policy map in `all.yml`; quotas and shares in `role_util/storage.yml`;
hosts and disks in `terraform/variables.tf`.

---

## 4. Technologies and versions

| Component | Version |
|---|---|
| OS | RHEL 10 (official Red Hat AMI looked up by name; patched to 10.2) |
| Terraform | >= 1.11 (`~> 1.11`; laptop has 1.15.6); providers aws `~> 6.0` (locked 6.70.0), random 3.9.1 |
| State | S3 bucket with native lock file, versioned, TLS-only |
| Ansible | ansible-core 2.18 in a venv on control01; collections ansible.posix 2.2.2, amazon.aws 12.0.0, freeipa.ansible_freeipa 1.17.0 |
| FreeIPA | 4.13.4 |
| VPN | WireGuard + wstunnel 11.1.0 (pinned, SHA-256 checked) |
| Others | Squid 6.10, nfs-utils 2.8, rsyslog (OpenSSL TLS driver), awscli2 |

---

## 5. What has been implemented (all verified)

| Area | Status |
|---|---|
| Network, default-deny security groups, NAT, Instance Connect break-glass | done |
| Ansible from control01, dynamic inventory, base hardening, patch baseline | done |
| VPN: WireGuard inside wstunnel on 443, server key in Vault (survives rebuilds) | done |
| Persistent layer: Vault password in SSM; state bucket in code | done |
| FreeIPA (roadmap 1): server, all clients, identity as data, HBAC, sudo, SSHFP | done |
| Per-team VPN policy (roadmap 2) with synthetic test peers per team | done |
| util01 (roadmap 3): forced web proxy with per-user layer, NFS homes, TLS logs, S3 backups + restore | done |
| Storage (roadmap 4): second disk, online growth, user and team quotas, team shares with default ACLs | done |
| Polish: stable IPA IDs (D-060), roles instead of long playbooks, docs as built | done |
| Fixed host IPs protected by subnet CIDR reservations (D-062, INC-006) | done |
| Audit (roadmap 5a): keyed rules on every host, records central on util01, hourly report (D-063) | done |

**Last verification: `lab.sh verify` 144/144** (2026-11-03), and `site.yml`
rerun idempotent. The first complete build from nothing worked after the fixes
in section 7. First real backup restore: 1 s.

---

## 6. Important configuration decisions (see `Decisions.md` for alternatives)

- **Rebuild every session** (D-032, D-048): IPA is reinstalled from code each
  time; nothing is changed by hand.
- **Secrets**: Ansible Vault, password in SSM via a write-only Terraform
  argument (D-042, D-043); IPA passwords and gw01's WireGuard key are in
  vault files; clients never get the IPA admin password (one-time passwords).
- **Workstations have no direct internet** (D-057): only IPA, DNS, Squid, NFS;
  HTTPS only, no TLS interception; per-user layer is nftables on UIDs.
- **NFS sec=sys** (D-058) because logins are key-only (no Kerberos tickets);
  homes at `/users`, not `/home` (would hide local accounts like `ansible`).
- **Logs** over TLS with IPA certificates; directory by sender's reverse DNS (D-059).
- **Stable IDs** (D-060): fixed IPA range 455400000-455599999 and explicit
  UID/GID in `identity.yml`. Next free ID is noted in that file.
- **Workstations hold no data** (D-061); util01 gets the space.
- **Fixed host IPs** live in an explicit subnet CIDR reservation `10.0.x.8/29` (D-062).
- **Audit** (D-063): own keyed rules, records through the syslog plugin and the
  TLS log path to `/srv/logs/<fqdn>/audit.log` (raw, `ausearch -if`).

---

## 7. Troubleshooting history (lessons that still matter)

| Problem | Cause | Fix in code |
|---|---|---|
| WireGuard handshakes dropped (INC-001) | WireGuard UDP filtered on Ahmed's network | WireGuard inside wstunnel on TCP 443 |
| site.yml froze (INC-002) | unknown; a stalled Instance Connect session is a strong candidate | logging, keepalives, task timeout; long jobs run detached (below) |
| firewalld "not running" on a fresh host (INC-003) | systemd "started" before ready | wait for `firewall-cmd --state` |
| Fresh build hung on workstation dnf (INC-004) | no direct internet and Squid not built yet | `site.yml` builds util01 + Squid first, dnf proxy by IP |
| Instance Connect SSH session stalled; laptop never saw the end | tunnel stops carrying data on long sessions | `run_on_control01`: detached run + polling (`~/run-<name>.log/.rc`) |
| Leaked key of another IAM user used for Bedrock (INC-005) | key leaked outside this repo | users/roles deleted, key rotated; cost $0 (all calls throttled) |
| IPA roles silently skipped | AWS inventory host variable `state` | pass `state: present` as role parameter |
| IPA client enrollment failures | short server names, empty `ca.crt` left behind, role delegating to a non-inventory name | full names, cleanup guard, OTP created in the play |
| sudo rules missing on clients | SSSD cached "no rules" from before they existed | identity checksum -> SSSD cache reset |
| SSSD stuck offline after an outage | backoff + its DNS library preferring the VPC resolver | restart offline SSSD on every run |
| Restored files with wrong owners | IPA reinstall changed numeric IDs; backup stored numbers | backups by name; stable IDs (D-060) |
| Backup failed | NFS `.nfsXXXX` silly-rename files locked | exclude `.nfs*` |
| Security group delete hung ~15 min | Terraform deletes an SG before moving instances | create new SGs and rules, move instances, delete old last |
| Re-enrolling a replaced host | IPA refuses an OTP for an enrolled host | release (disable) the old entry first |
| Audit tests found nothing on util01 | central log directories are FQDNs (`ws-ops01.ahmed.internal`) | use the FQDN in paths |
| A "word not in /var/log/messages" check failed | Ansible logs every command line it runs | match the program field, not the word |
| `InvalidIPAddress.InUse` for control01 (INC-006) | Instance Connect Endpoint auto-assigned 10.0.1.10 | explicit subnet CIDR reservation for fixed host IPs (D-062) |

Shell and Ansible traps (full list in `CLAUDE.md` lessons): ssh needs a closed
stdin (`-n`); `pgrep/pkill -f` match their own ssh command line (use `[x]yz`);
with pipelining a running module is a bare `python3`; never pipe secrets
through Ansible ad hoc (it logs); XFS cannot enable quotas by remount; NFSv4
clients do not show POSIX ACLs; multi-line Jinja `set_fact` needs `{%- -%}`;
an EBS root volume cannot shrink (`-replace`); never interrupt dnf.

---

## 8. Current state (2026-11-03)

- **Lab layer is DOWN** (destroyed with `lab.sh down` after a backup).
  Persistent and bootstrap layers exist and are untouched.
- Repository clean and pushed; roadmap items 1-4 done and verified.
- **AWS account after INC-005:** only the root user (MFA on, no access keys)
  and the IAM user `ahmeddhussain` with one rotated access key. All other
  users, roles, the admin group and the GitHub OIDC provider were deleted.
- **AWS Free plan**: usage is paid from credits (about $107 left on
  2026-11-02); the plan **expires 2026-12-21**, after which the account closes
  unless upgraded to a paid plan (then lab costs reach the card). Check:
  `aws freetier get-account-plan-state`. A $0.10 budget alert exists.

---

## 9. Known issues and limitations

- sec=sys NFS and the nftables per-user web layer can be bypassed by root on a
  workstation (ops have full sudo on ws-ops01).
- SSHFP records exist but without DNSSEC OpenSSH still relies on known_hosts.
- chrony's AWS time source comes from the image default, not from `base`
  (guarded by a test).
- amazon.aws removes the `tags` host variable after 2026-12-01; this repo uses
  `ec2_tags` (recheck on collection upgrades).
- Backups are full tar.gz each time (fine at lab size).
- Single IPA server (no replica); idm01 is a single point of failure.
- Dev "restart app" and dba "sudo -u postgres" rules wait for app01.
- No CI or linters, by Ahmed's choice; the tests are `test-lab.sh` and the
  Terraform mock tests.

---

## 10. Remaining tasks and roadmap

**Ahmed (manual, AWS console):** enable MFA and set a new console password for
`ahmeddhussain`; recheck the bill for Bedrock charges; decide about the Free
plan before 2026-12-21.

**Roadmap item 5 (next):** patching cadence, logging/audit (auditd, reports),
backup/restore drills with measured RTO, OpenSCAP compliance, app01 (web/db
tier, activates the dev and dba sudo rules), incident drills.

**Roadmap item 6 (possible):** golden image to shorten rebuilds, SSH
certificates, execution environments, SSM break-glass.

Open ideas: IAM Identity Center (short-lived credentials) instead of an access
key; default tag `Layer = "lab"`.

---

## 11. How to continue (exact commands, on Ahmed's Linux laptop)

    cd ~/ahmed-infra
    eval "$(ssh-agent)"
    scripts/lab.sh up               # Terraform apply + bootstrap + site.yml + tests (about 1 h from nothing)
    scripts/vpn-client.sh connect   # needs Ahmed's sudo
    ssh control01-vpn               # admin entry (break-glass: ssh control01)
    scripts/lab.sh verify           # tests (expect 144/144; --full adds idempotency)
    scripts/lab.sh down             # backs up util01 to S3, then destroys the lab layer

Rules of the workflow: change code on the laptop, commit, **push**, then
control01 pulls (lab.sh does it). Ansible runs **only on control01** from
`~/ahmed-infra/ansible`. For a long run outside lab.sh, start it detached on
control01 and poll. Ending a roadmap item: verify, commit, push, update
`CLAUDE.md` sections 10/12, review `terraform plan -destroy`, then
`lab.sh down`.

Credentials (never in Git or docs): AWS CLI credentials in `~/.aws/credentials`
on the laptop; bootstrap SSH key `~/.ssh/ivolve.pem`; WireGuard client key in
`/etc/wireguard/`; Vault password in SSM (read by control01's instance role).

---

## 12. Approaches decided against (and why)

| Rejected | Why |
|---|---|
| Plain WireGuard on UDP | filtered on Ahmed's network (INC-001) |
| Keeping IPA or util01 data alive between sessions | breaks "rebuild from code"; drift (D-048, D-056) |
| Persistent EBS for util01 | costs while down, not a backup (D-056) |
| Kerberos NFS / Kerberos proxy auth | needs user passwords; logins are key-only (D-057, D-058) |
| Automounting `/home` | hides local accounts incl. the ansible key |
| Per-role SG flows for every IPA port | too many rules; VPC CIDR + idm01 /32 (D-051) |
| firewall-cmd rule-by-rule for VPN policy | only ever adds; whole XML files instead (D-052) |
| restic (EPEL) for backups | extra third-party repo; tar + awscli2 + S3 versioning (D-056) |
| Renumbering IPA IDs | would change live users; froze the existing numbers (D-060) |
| CI pipelines and linters | Ahmed's choice: focus on sysadmin, tests already exist |
| Admin access keys for several IAM users, GitHub roles trusting `repo:*` | caused / enabled INC-005; removed |

---

## 13. Where we stopped and the immediate next step

Stopped after roadmap item 4 (verified 134/134), a documentation polish, and
containing INC-005. The lab is down.

**Next step:** Ahmed enables MFA on `ahmeddhussain`; then start a session with
`scripts/lab.sh up` (expect 134/134) and plan roadmap item 5, decisions first
(options, alternatives, Ahmed chooses), one step at a time.
