# CLAUDE.md: ahmed-infra

Context for Claude Code. Read this first, then `Decisions.md`,
`docs/architecture/org-structure`, and `docs/incident-reports/`. Those files are
the source of truth; this file is the map.

---

## 1. What this project is

An enterprise-style Linux system administration lab on AWS EC2, built as a
portfolio project to show job readiness for Linux / Cloud / DevOps roles.

- Fictional company: **ahmed**. Repo root folder: `ahmed-infra`.
  GitHub: `github.com/ahmeddhussain/Linux-System-Administration`.
- The owner (Ahmed) plays the company's **Linux administrator**. The focus is
  running a company and its teams (identity, access, endpoints, policy), not just
  deploying a web server. Workloads (web/db, maybe Kubernetes later) are tenants
  on top of the company layer.
- Modeled on a Red Hat Academy classroom lab (one account usable on every server),
  done the enterprise way: Terraform builds, Ansible configures, FreeIPA (planned)
  provides central identity.
- OS: **RHEL 10** (official Red Hat AMI, looked up by name). Region: **us-east-1**.

---

## 2. How to work with Ahmed (mandatory)

Act as a senior DevOps / Linux / Cloud engineer mentoring Ahmed.

1. **One step at a time.** Give only the next logical step. Explain what each
   command does and what output to expect. Wait for the real output before
   continuing. Never assume a command worked.
2. **Troubleshooting order:** Understand -> Investigate -> Diagnose -> Fix ->
   Verify -> Optimize (if needed) -> Alternatives (if useful). Do not jump to a
   list of possible fixes. Narrow the cause with evidence first.
3. **Every decision states the alternatives and why this one was chosen**, and is
   recorded in the decision log (`D-0xx` entries).
4. **Full files, not partial diffs**, whenever a file changes.
5. **Everything must be permanent and reproducible.** If something must survive a
   rebuild, it lives in code, in the right Terraform layer or Ansible role. No
   hand-made fixes left on servers. Manual repairs are allowed only to recover a
   broken host, and must be followed by a code change that prevents recurrence.
6. **Respect the existing environment.** Minimal, targeted changes. Explain the
   consequences of anything destructive before running it. Ask before
   destructive or irreversible actions.
7. **Be honest about uncertainty.** Say when something is a hypothesis. If a
   hypothesis is disproved, say so and correct any document that relied on it.
8. Be direct, technical, and concise. Use headings and tables where they help.
9. Real incidents get a report in `docs/incident-reports/INC-0xx-*.md`
   (summary, impact, timeline, investigation with evidence, root cause, actions).
10. **Keep this file current.** At the end of every session, update section 10
    (current state) and section 12 (open items) so the next session, or a
    reviewer, picks up exactly where work stopped.
11. **Ending a roadmap item (Ahmed, 2026-11-02):** only after it is verified
    (`lab.sh verify` all passing) and everything is committed and pushed,
    end the session: update sections 10 and 12, commit, review the destroy
    plan, then bring the lab down with `scripts/lab.sh down` (it backs up
    util01 first).

---

## 3. Architecture

### Network (Terraform module `network`)
| Subnet | CIDR | Public? | Hosts |
|---|---|---|---|
| public | 10.0.0.0/24 | yes (IGW route, public IPs) | gw01, NAT gateway |
| infra | 10.0.1.0/24 | no (egress via NAT) | control01, idm01, util01, Instance Connect Endpoint |
| workstation | 10.0.2.0/24 | no | ws-dev01, ws-ops01 |
| app | 10.0.3.0/24 | no | empty (app01 planned, Phase 10) |

- VPC `10.0.0.0/16`, one AZ (`us-east-1a`). NAT gateway can be toggled with
  `enable_nat_gateway` (costs about $32/month if left running).
- Private route table also routes `10.8.0.0/16` (VPN clients) to gw01's ENI
  (`terraform/vpn.tf`). gw01 has source/destination check disabled.

### Hosts (`terraform/hosts.tf`, one map; adding a host is one entry)
| Host | Role tag | Team tag | IP | Type | Purpose |
|---|---|---|---|---|---|
| gw01 | gateway | platform | 10.0.0.10 | t3.small | VPN gateway, only public host (Elastic IP) |
| control01 | control | platform | 10.0.1.10 | t3.small | Ansible control node, admin entry |
| idm01 | idm | platform | 10.0.1.11 | c7i-flex.large (4 GB, free-tier eligible) | FreeIPA (planned) |
| util01 | util | platform | 10.0.1.12 | t3.small (+20 GB data volume) | Squid, NFS homes, logs, backups (planned) |
| ws-dev01 | workstation | dev | 10.0.2.10 | t3.small | Dev team workstation |
| ws-ops01 | workstation | ops | 10.0.2.11 | t3.small | Ops/DBA workstation |

All hosts: FQDN `<name>.ahmed.internal` set by cloud-init, IMDSv2 required,
encrypted gp3 root, AMI changes ignored (patched in place, not replaced).
The account plan only allows free-tier-eligible instance types.

### Access paths
- **Admin (normal):** laptop -> VPN -> control01 (`ssh control01-vpn`) -> any host.
- **Admin (break-glass):** laptop -> AWS EC2 Instance Connect Endpoint -> control01
  (`ssh control01`). Authenticated by AWS credentials, no inbound internet rule.
- **Employees (planned):** laptop -> VPN (team range) -> their team's workstation.
- Servers accept SSH only from control01.
- Only internet-facing port: **TCP 443 on gw01** (wstunnel).

### Identity (FreeIPA on idm01, D-046 to D-051, built 2026-11-01)
- Realm `AHMED.INTERNAL`, domain `ahmed.internal`, IPA 4.13.4, integrated CA,
  integrated DNS forwarding to the VPC resolver (10.0.0.2), reverse zones per
  subnet, **no allow_all HBAC rule**. Single server, rebuilt from code every
  session (D-048).
- All five other hosts are clients: resolver idm01 then 10.0.0.2, SSHFP
  records, SSSD for users/sudo, `ipaclient_no_ntp` (time stays AWS 169.254.169.123).
- Users: `ahmed.admin` (admins, everywhere, full sudo), `ahmed` (dev), `sara`
  (ops), `omar` (dba), `laila` (security), `contractor1` (expires 2026-12-31).
  Login/sudo per `org-structure.md`; control01 and gw01 are admin-only.
  Dev "restart app" and dba "sudo -u postgres" wait for app01.
- Ops' *network* path to servers is deferred (Ahmed, 2026-11-01): HBAC allows
  sara on idm01/util01, but servers accept SSH only from control01.
- The local `ansible` account stays everywhere; automation never needs IPA.

### util01 services (roadmap item 3, D-056 to D-059, built 2026-11-01)
- **Storage (D-061):** LVM `vg_data` on two disks (20 + 10 GB): `lv_home`
  12 G -> `/export/home` (user quotas), `lv_teams` 8 G -> `/export/teams`
  (project quota per team), `lv_logs` 6 G -> `/srv/logs`. Workstations have
  a 10 GiB OS disk only. Team shares `/teams/<team>` (2770 + default ACL),
  `/teams/company` (group employees, sticky). Runbook: `docs/runbooks/storage.md`. Lab layer, so rebuilt every
  session. `ahmed-backup backup|restore|verify` (tar + awscli2) to S3 bucket
  `ahmed-infra-backups-<account>` (persistent layer, versioned, 30-day
  history); daily timer; `lab.sh down` backs up first; a new volume restores
  the latest backup. util01 role `ahmed-backup-writer` (no delete).
- **Web proxy:** Squid, HTTPS (CONNECT 443) only. Port 3128 "standard"
  (deny social media + streaming lists, AI sites allowed) for dev/ops;
  3129 "allowlist" (repos, GitHub, docs) for dba/contractors. Workstations
  have **no direct internet** (SGs), only IPA, DNS, Squid, NFS. Per-user
  layer: nftables on workstations rejects allow-list users' UIDs on 3128.
  Lists: `group_vars/role_util/web_policy.yml`; team->policy: `all.yml`.
- **NFS homes:** NFSv4 only, sec=sys, root_squash, to the two workstations;
  IPA automount map `auto.home` at **`/users`** (IPA users' homes are
  `/users/<name>`; local accounts keep /home). Servers create local homes.
  Gap: root on a workstation can act as any user (sec=sys).
- **Central logs:** every host -> util01 TCP 6514 TLS (rsyslog OpenSSL,
  IPA certificate per host via certmonger); `/srv/logs/<sender>/<program>.log`,
  readable by IPA group `security`; 14 days rotation; Squid access log too.

### VPN
- **WireGuard carried inside TLS by wstunnel on TCP 443** (D-040). Reason:
  INC-001 proved WireGuard UDP is dropped on Ahmed's network while plain UDP and
  HTTPS pass. TLS is camouflage only; WireGuard provides encryption and auth.
- Server: gw01, wg0 = 10.8.0.1/16, UDP 51820 closed to the outside (reached only
  via wstunnel on localhost). wstunnel 11.1.0, pinned, SHA-256 verified, systemd
  service with DynamicUser + CAP_NET_BIND_SERVICE, `--restrict-to localhost:51820`.
- **Per-team policy (D-052 to D-054, 2026-11-01):** wg0 in firewalld zone
  `vpn` (target DROP); zones `vpn-admin/-dev/-ops` by source range; policy
  `vpn-<team>-to-vpc` (target REJECT) allows only `vpn_team_policy` entries in
  `group_vars/role_gateway/main.yml`. Written as whole XML files, so removed
  rules disappear. Admin: control01:22, idm01:443, both workstations:22, ping.
  Dev: ws-dev01:22. Ops: ws-ops01, idm01, util01 :22. gw01 itself: SSH from
  admin only, ping from all. Routed, no NAT.
- VPN ranges: admin 10.8.0.0/24, dev 10.8.1.0/24, ops 10.8.2.0/24.
- Peers are data in `ansible/inventory/group_vars/role_gateway/main.yml`
  (peers: `ahmed-laptop` 10.8.0.2, plus test peers `test-admin/-dev/-ops` at
  10.8.x.250 used only by test-lab.sh, D-055). The role refuses to run with no
  peers or invalid keys.
- gw01's server private key comes from the encrypted
  `group_vars/role_gateway/vault.yml` (D-043), so it survives rebuilds.
  Public key: `pq8I2l7QAZgjHDOFEhtE11ivKmRMi4QlnejGrwj+VCk=`.

### Security groups (`terraform/main.tf`, module `security-groups`)
Default deny. One group per role (`eice`, `gateway`, `control`, `idm`, `util`,
`workstation-dev`, `workstation-ops`; a host's `security_group` overrides its
role, the Ansible Role tag stays `workstation`). VPC default SG emptied. Allowed:
- Flows (both halves declared): eice->control:22, control->gateway/idm/util/workstation:22.
- Ingress: gateway TCP 443 from `vpn_client_cidr` (default 0.0.0.0/0, only when
  `enable_vpn_endpoint = true`); control SSH+ICMP from VPN admin range;
  each workstation group SSH from admin and its own team range, ICMP from
  admin; idm01/util01 SSH from the ops range (D-053); ICMP from VPC.
- Egress: TCP 443 to internet (via NAT) for every host role; ICMP inside VPC;
  gateway TCP 22 to infra and workstation subnets (forwarded VPN SSH).
- Port 80 is blocked on purpose (some mirrors are plain HTTP); the only
  exception is TCP 80 to idm01 (IPA certificate revocation), once applied.
- FreeIPA (D-051, **code written, not applied yet**): idm01 ingress from the
  VPC CIDR on DNS 53 tcp/udp, Kerberos 88/464 tcp/udp, 389, 636, 80, 443, and
  443 from the VPN admin range; every other role egress to `10.0.1.11/32` on
  the same ports (443 already allowed everywhere).

---

## 4. Terraform layout

| Layer | Path | State | Destroyed by `lab.sh down`? |
|---|---|---|---|
| bootstrap | `terraform/bootstrap/` | S3 key `ahmed-infra/bootstrap.tfstate` | never (the state bucket itself, adopted via import) |
| persistent | `terraform/persistent/` | S3 key `ahmed-infra/persistent.tfstate` | never (holds the Vault password parameter) |
| lab | `terraform/` | S3 key `ahmed-infra/terraform.tfstate` | yes |

- State bucket **`ahmed-statefile`** (D-044, since 2026-11-01): versioned
  (old versions expire after 90 days), SSE-S3 + bucket key, public access
  blocked, ACLs disabled, TLS-only policy (plain HTTP verified denied),
  `prevent_destroy`, native S3 locking (`use_lockfile`). Before that date it
  was NOT versioned: no state history exists from earlier.
- All layers: `required_version = "~> 1.11"`, aws `~> 6.0`, lock files committed.
- Lab modules (each with `versions.tf`): `modules/network`,
  `modules/security-groups`, `modules/ec2-instance`.
- Lab files: `versions.tf`, `providers.tf` (default tags Company/Project/ManagedBy),
  `variables.tf` (**all** lab variables, incl. the `hosts` map with
  validations: known subnet, known role, unique IPs, at most one
  `control_node_role`), `main.tf` (module calls), `network-policy.tf` (roles, flows, CIDR rules), `hosts.tf`
  (module call), `compute.tf` (AMI lookup, `ahmed-bootstrap` key pair from
  `~/.ssh/ivolve.pub`), `iam.tf` (role/profile `ahmed-control-node`:
  describe instances + read `/ahmed-infra/*` secrets), `access.tf` (Instance
  Connect Endpoint), `vpn.tf` (route to gw01), `moved.tf`, `outputs.tf`.
- Tests (mock provider, no credentials, nothing created):
  `terraform -chdir=terraform test` (host validations) and, per module,
  `terraform -chdir=terraform/modules/<m> init -backend=false && ... test`
  (security-groups, network). 12 tests.
- `terraform/terraform.tfvars` (gitignored, laptop only, required by lab.sh):
  `enable_vpn_endpoint = true`. Template: `terraform.tfvars.example`.
- Never put secrets in Terraform state. Use write-only arguments / ephemeral
  resources, or keep secrets outside Terraform.

---

## 5. Ansible layout (runs on control01 only)

- Repo cloned on control01 at `~/ahmed-infra`; venv `~/ansible-venv` with pinned
  `ansible-core>=2.18,<2.19`, `boto3`, `botocore` (`ansible/requirements.txt`);
  collections `ansible.posix`, `amazon.aws` (`ansible/requirements.yml`).
- **Always run Ansible from `~/ahmed-infra/ansible` on control01.** `ansible.cfg`
  is read from the current directory. Running it on the laptop is wrong (it
  treats control01 as local and cannot reach private IPs).
- **Changes are made on the laptop, committed, pushed; control01 pulls from GitHub.**
  Push before `lab.sh up/resume`.
- `ansible.cfg`: dynamic inventory, `roles_path = roles`, become via sudo,
  pipelining, ControlPersist, `log_path = ~/ansible.log`, `task_timeout = 1800`,
  SSH keepalives (ServerAliveInterval 15, CountMax 4),
  `vault_password_file = scripts/vault-password.py` (reads SSM, D-043).
- Inventory `inventory/aws_ec2.yml` (`amazon.aws.aws_ec2`): only running
  instances tagged `Project=ahmed-infra`; names from the Name tag; groups
  `role_<Role>`, `team_<Team>`, `infra`; connects to private IPs; control01 is
  `local`; `HostKeyAlias=<instance_id>` so rebuilt hosts at reused IPs are not
  confused with old ones. The `tags` deprecation warning comes from the plugin
  itself and is harmless.
- `inventory/group_vars/all.yml`: `ansible_user: ansible`, key `~/.ssh/ansible_ed25519`,
  shared IPA settings (`ipa_domain`, `ipa_realm`, `ipaclient_no_ntp`, mkhomedir).
- Inventory groups also include `ipaservers` (idm01) and `ipaclients` (the rest),
  names expected by `freeipa.ansible_freeipa`.
- `inventory/group_vars/role_idm/`: `main.yml` (server), `vault.yml` (admin and
  Directory Manager passwords, encrypted), `identity.yml` (**all users, groups,
  host groups, HBAC and sudo rules**). `group_vars/ipaclients.yml` (clients).
  `group_vars/role_control.yml`: modules on control01 use `/usr/bin/python3`.
- `ansible/tests/test-user-keys.vault.yml`: encrypted private test keys of the
  IPA users, used by `test-lab.sh`.
- Collections pinned in `requirements.yml`: ansible.posix 2.2.2, amazon.aws
  12.0.0, freeipa.ansible_freeipa 1.17.0.
- `inventory/group_vars/role_gateway/`: `main.yml` (VPN peers, maps
  `wireguard_server_private_key` to the vault variable) and `vault.yml`
  (whole file encrypted; `ansible-vault edit` on control01). **The directory
  name must match the group name exactly (underscore).**
- Automation account `ansible` on every host: key-only, password locked,
  passwordless sudo, created once per rebuild by `playbooks/bootstrap.yml`
  (run as `ec2-user` with the laptop key forwarded).

### Playbooks
- `playbooks/site.yml` (order matters, INC-004): patch util01; util01
  `base` + `web_proxy`; workstations' dnf proxy (by IP); patch the rest;
  `base` (all); `idm.yml`; util01 `util_storage`, `log_server`,
  `nfs_server`, `team_shares`; `log_forwarder` (all); workstations `nfs_client`,
  `proxy_client`; gw01 `wireguard_gateway`; VPN test peer tools (control01).
- `playbooks/patch.yml`: `serial: 2`; installs dnf-utils; updates all packages;
  checks `systemctl --version`, `ssh -G localhost` and `sshd -t` before any
  reboot; reboots when `dnf needs-restarting -r` says so; never reboots
  control01 (the script does that).

### Roles
- `base`: troubleshooting packages, UTC + chronyd, SELinux enforcing, firewalld
  with SSH, SSH hardening drop-in `/etc/ssh/sshd_config.d/10-ahmed-hardening.conf`
  (no root, no passwords, MaxAuthTries 4, banner) validated with `sshd -t`,
  `/etc/issue.net` banner, `/etc/motd`.
- `wireguard_gateway`: asserts (peers present, valid keys, pinned wstunnel
  checksum); EPEL repo limited to `wireguard-tools` over HTTPS; kernel module;
  IPv4 forwarding; server key installed from the vault (`/etc/wireguard/server.key`,
  public key derived into `server.pub`; asserts the key is present and valid); `wg0.conf` from template; firewalld (51820/udp
  closed in public zone, 443/tcp open, wg0 -> trusted permanently,
  `vpn_to_vpc` policy); wstunnel download/verify/install to `/usr/local/bin`
  (root, 0755, bin_t) and systemd unit; checks running peers and that 443 listens.

---

## 6. Scripts (run on the laptop from the repo root)

| Script | Purpose |
|---|---|
| `scripts/lab.sh up [-y]` | Terraform apply, then everything `resume` does |
| `scripts/lab.sh resume` | Load agent key, write SSH entries, wait for control01, prepare control01, bootstrap, `site.yml`, reboot control01 if needed, run tests, refresh VPN client |
| `scripts/lab.sh verify [--full]` | Run `test-lab.sh` on control01 (`--full` adds the idempotency run) |
| `scripts/lab.sh status` | Instance table |
| `scripts/lab.sh down [-y]` | Disconnect VPN, `terraform destroy` of the lab layer (Terraform lists every resource and asks `yes`; `-y` skips) |
| `scripts/vpn-client.sh refresh` | Fetch gw01's server key and rewrite `/etc/wireguard/ahmed.conf` |
| `scripts/vpn-client.sh connect / disconnect / status` | Start/stop wstunnel (user unit `ahmed-wstunnel`) and WireGuard; test ping |
| `scripts/control01-setup.sh` | Runs on control01 (piped by lab.sh): packages, repo, venv, collections, key |
| `scripts/test-lab.sh` | Runs on control01: 121 checks (util01 storage/backup, web proxy per user, NFS homes, central logs, VPN test peers per team, access, network policy incl. must-be-blocked, baseline, patch parity, VPN incl. gateway key, time, FreeIPA, per-user logins and sudo) |
| `scripts/lib/*.sh` | `common.sh`, `infra.sh`, `control01.sh`, `configure.sh` |

- `LAB_SSH_KEY` (default `~/.ssh/ivolve.pem`) is the bootstrap key; it is only
  used for `ec2-user` access and the one-time bootstrap.
- `lab.sh` writes `~/.ssh/ahmed-lab.conf` (included from `~/.ssh/config`):
  `control01` (via Instance Connect) and `control01-vpn` (10.0.1.10, HostKeyAlias
  = instance ID).
- Scripts piped over SSH wrap their body in `main() { ... }; main < /dev/null`
  so commands cannot swallow the rest of the script.

### Session routine
    eval "$(ssh-agent)"
    scripts/lab.sh up                 # about 25-35 min, ends with tests and "Ready"
    scripts/vpn-client.sh connect
    ...work...
    scripts/vpn-client.sh disconnect
    scripts/lab.sh down               # stop NAT, instance and address costs

### Laptop / client
- Laptop is a Linux VM under VMware (NAT, interface `ens160`).
- WireGuard client keys: `/etc/wireguard/ahmed.key` and `ahmed.pub`
  (never committed). wstunnel 11.1.0 in `/usr/local/bin`.
- Client config is generated by `vpn-client.sh refresh`: MTU 1280,
  Endpoint 127.0.0.1:51820, AllowedIPs 10.0.0.0/16.

---

## 7. Lessons learned (do not repeat these mistakes)

- RHEL 10.0 image + 10.2 repositories => version skew. Patch the whole fleet
  first (`patch.yml`). Mixed packages broke `systemctl` (systemd vs openssl) and
  SSH (crypto-policies vs openssh-clients).
- **Never interrupt dnf.** An OOM-killed update on a 1 GB control01 left
  duplicate packages and a broken SSH client. Control node is now t3.small.
- Fixed IPs + rebuilt hosts => "host key changed". Key host identity by instance
  ID (HostKeyAlias), never disable host key checking.
- firewalld runtime changes vanish on reload; use permanent configuration.
- Handlers are lost when a play fails after notifying; add explicit
  verification tasks (e.g. running peers == configured peers).
- `pgrep dnf` does not see Ansible's dnf task (`AnsiballZ_dnf.py`); use
  `pgrep -af AnsiballZ` and `ss state syn-sent` for hangs.
- Packet captures must run simultaneously on both ends, started before the test.
- Tarball binaries may lack the execute bit and keep foreign UIDs; set
  owner root and mode 0755 explicitly.
- The `assert` in a loop passes on an empty list; assert the list length too.
- Group_vars files must be named exactly like the group.
- Handling secrets in shell: never pipe a secret through Ansible ad-hoc
  (`~/ansible.log` records output); a nested `ssh` inside a piped script eats
  its stdin (wrap in `main ... < /dev/null`, give each inner ssh `< /dev/null`);
  an EXIT trap cannot see a `local` variable, so cleanup of a plaintext temp
  file silently fails (use a global, verify the file is gone).
- systemd "started" is not "ready": firewalld (Type=dbus) refuses requests
  for a moment after start on a fresh host (INC-003). Wait for
  `firewall-cmd --state` before configuring it.
- `create_before_destroy` on a resource does not cover its dependents in the
  plan order you expect; put it on every resource in a rename chain (role,
  inline policies, profile) and read the apply order.
- Inventory host variables can collide with role variables: the AWS
  inventory's `state` silently switched the IPA roles off (it could as well
  have selected uninstall). Pass critical role inputs as role parameters.
- Roles that delegate to a server *name* assume inventory names are FQDNs;
  ours are short. Do the delegated step in the play via the inventory name.
- A failed install can leave files that break the retry (empty `ca.crt`).
  Check for leftovers before retrying; guard against them in code.
- `connection: local` runs modules in the controller's venv; system Python
  packages (ipapython) are invisible there. Set `ansible_python_interpreter`.
- SSSD caches "no sudo rules" from before the rules existed; restart and
  `sss_cache -R` do not fix it; only a cache reset (full refresh) does.
- Always give `ssh` a closed stdin (`-n` or `< /dev/null`) in scripts and ad
  hoc commands, or it can hang waiting for input.
- Removing a security group that instances use: Terraform deletes it before
  moving the instances, AWS refuses (DependencyViolation) and the apply hangs
  ~15 min. Recovery used: move instances to the new groups **only after their
  rules exist** (I moved them first and left both workstations without rules
  for ~3 min). Prefer: create the new groups and rules in one apply, move the
  instances in a second (targeted) apply, delete the old group last.
- `cp -a src/. dst/` copies the mode of `src` onto `dst`: /etc/skel's 0755
  made every NFS home readable (caught by the root_squash test).
- Guards must test the thing itself: "automount: sss" is in RHEL's default
  nsswitch, so it did not show that ipa-client-automount had run.
- `'Online' in 'Online status: Offline'` is true. Match whole phrases.
- After an idm01 outage SSSD can stay offline for minutes (backoff, and its
  DNS library prefers the VPC resolver, which says "not found" for
  ahmed.internal). `idm.yml` restarts an offline SSSD on every run.
- Apply network removals only after the replacement path is proven (proxy
  first, then remove direct HTTPS).
- With pipelining, a running module is a bare `python3` under the ansible
  user's sshd session; `pgrep AnsiballZ` finds nothing. Use `ps --forest`.
- `pgrep -f`/`pkill -f <pattern>` inside `ssh host '...'` matches the ssh
  command line itself (`pkill` killed its own session). Use `[x]yz` patterns.
- Long sessions through the Instance Connect tunnel can stall silently; run
  long jobs detached on control01 and poll.
- IPA reinstalls give new numeric IDs; anything restored by number breaks.
  Store names (tar without --numeric-owner).
- NFS clients rename a file deleted while open to `.nfsXXXX`; the server
  cannot open it while locked, so backups exclude `.nfs*`.
- NFSv4 clients do not show POSIX ACLs (`getfacl`); check ACLs on the server.
- A multi-line Jinja `set_fact` must trim whitespace (`{%- -%}`), or the
  "list" is a string and `loop` refuses it.
- An EBS root volume cannot shrink: changing `root_volume_size` down needs
  `-replace`; a rebuilt host must be released in IPA before re-enrolling.
- The login banner has no trailing newline; filtering it with grep drops the
  next output line. Use `ssh -o LogLevel=error`.

---

## 8. Decisions (details in the decision log)

D-001 RHEL 10 · D-002 5 hosts now, app01 later · D-003 Terraform builds, Ansible
configures · D-004 reuse bootstrap key, import public key · D-005/D-025/D-037
instance sizing · D-006 FreeIPA · D-007 control01 and idm01 separate · D-008
Squid per-team web filtering · D-009 Ansible by host group · D-010 named admin,
no root login · D-011 us-east-1 · D-012 superseded by D-017 tiered private
subnets + NAT · D-013 superseded by D-016 S3 state with native locking · D-014
local modules · D-015/D-019 SG per role, default deny, explicit flows · D-018/
D-020/D-023 entry point evolution -> D-026 Instance Connect break-glass ·
D-021 AMI lookup, ignore AMI changes · D-022 host map, static IPs, FQDN, IMDSv2,
encryption · D-024 routed VPN, per-team ranges, split tunnel · D-027 ansible
account · D-028 Ansible runs from control01, code from Git · D-029 dynamic
inventory · D-030 pinned venv · D-031 base role · D-032 scripted lifecycle ·
D-033 WireGuard role · D-034 patch baseline · D-035 tests as a script · D-036
host identity by instance ID · D-037 control node sizing and patch batching ·
D-038 permanent firewall zone binding · D-039 VPN entry open to any source
(rationale corrected after INC-001) · D-040 WireGuard inside wstunnel on TCP 443
· D-041 scripts split, VPN client automated · D-042 persistent Terraform layer
· D-043 Vault password in SSM · D-044 state bucket
adopted into code, versioned, TLS-only · D-045 Terraform tests with mocks ·
D-046 FreeIPA realm/CA/single server · D-047 IPA integrated DNS · D-048 IPA
rebuilt from code each session · D-049 IPA secrets in Vault · D-050
ansible-freeipa · D-051 IPA network rules, all hosts enroll · D-052 per-team
VPN policy · D-053 ops reach servers · D-054 gw01 admin SSH only · D-055 VPN
test peers · D-056 util01 data + S3 backups · D-057 forced web proxy · D-058
NFS homes · D-059 central logs over TLS · D-060 stable IPA IDs · D-061 storage, quotas,
team shares.

---

## 9. Incidents

- **INC-001** VPN handshake dropped: proven by elimination (plain UDP round trip
  works, WireGuard responses never arrive). Mitigated by wstunnel on TCP 443.
  Remaining action: client-side connectivity test in the verification script.
- **INC-002** `site.yml` run froze during a rebuild (most likely early in the
  gateway play on gw01). Cause not yet distinguished (dead shared SSH connection
  vs stalled download). Instrumentation added: `~/ansible.log`, SSH keepalives,
  task timeout. On recurrence: read `~/ansible.log` on control01 and
  `ps -ef --forest` to see which host the controller waits on.
  No recurrence in three full runs on 2026-11-01 (incl. a fresh gw01).
- **INC-003** base role failed on a freshly built gw01: firewalld module ran
  0.3 s after systemd reported firewalld started, before it was ready.
  Resolved: base role waits for `firewall-cmd --state` (4729555).

- **INC-005** (2026-11-02) leaked IAM access key of a second admin user used
  for Bedrock model calls. Contained: key blocked, extra users and roles
  deleted, lab user's key rotated; no backdoors or other resources. The
  account now has root (MFA) and `ahmeddhussain` (one key) only.
---

## 10. Current state (2026-11-02, end of session 2)

- Lab is **down** (`lab.sh down` at the end of the session; util01 backed
  up to S3 first). Persistent and bootstrap layers untouched.
- Last `lab.sh verify` before going down: **134/134** (roadmap items 1-4).
- This session: first full fresh build; polish round (D-060 stable IDs,
  roles instead of long playbooks, docs as built); roadmap item 4 storage
  (D-061); INC-005 security incident (leaked key of another IAM user,
  contained, cost $0; account now root + `ahmeddhussain` only, key rotated).
- **Start of next session:** `eval "$(ssh-agent)"; scripts/lab.sh up`, then
  roadmap item 5. Ahmed still to do: MFA + new password for `ahmeddhussain`.
- Fresh-build problems found and fixed in code: INC-004 (workstation dnf
  before Squid existed), stalled Instance Connect session (long jobs now run
  detached on control01), restore with old numeric IDs (backups by name).
- **Polish round (Ahmed: no CI/linters; simplify and reorganize):**
  D-060 stable IPA IDs (explicit UID/GID, fixed range; no-op on this lab);
  `idm.yml` 337 -> 46 lines (five `ipa_*` roles); `site.yml` consolidated;
  `terraform/network-policy.tf` split out (plan: no changes); README
  rewritten; `org-structure.md` as built; old IP-named log dirs removed.
- Laptop VPN: `scripts/vpn-client.sh connect` (needs Ahmed's sudo).

### Done: Ansible Vault for gw01's WireGuard server key
Goal met: the gateway key survives rebuilds, so client configs stay valid.
| Step | Commit | Result |
|---|---|---|
| 1 Vault password | 5cef2cc | `terraform/persistent/` (D-042): SSM SecureString `/ahmed-infra/ansible-vault-password` via ephemeral password + `value_wo` (not in state, verified). `iam.tf` `read-secrets`: control01 reads `/ahmed-infra/*`, decrypts via SSM only (denials verified). `scripts/vault-password.py` + `vault_password_file` (D-043). |
| 2 Key in vault | c3f8b6a | `group_vars/role_gateway/{main,vault}.yml`; vault holds gw01's existing key; role installs it instead of generating. `changed=0` on the live gw01. |
| Guard | 634e6b1 | `wireguard_server_public_key` recorded in `main.yml`; role refuses a vault key that does not match; new test compares the live key. |
| 3 Rebuild | (no code) | gw01 replaced via `-replace`; same EIP 100.59.129.103, same public key `pq8I2l7Q...VCk=`; the laptop's **already open** tunnel recovered by itself (no refresh). |
| Fix | 4729555 | INC-003: base role waits for firewalld to be ready (first resume failed on the fresh gw01). |

Notes:
- Rotating the Vault password: rekey every vault file *before* bumping
  `vault_password_version` in `terraform/persistent`.
- Rotating the gateway key: change `vault.yml` and `wireguard_server_public_key`
  together, then `vpn-client.sh refresh` on every client.
- During Step 2 a plaintext temp file with the key stayed on control01
  (0600, ec2-user) for about a minute (trap bug, see section 7); shredded,
  judged contained, key not rotated. Rotate if that judgment changes.
- `vpn-client.sh refresh` needs a terminal (sudo password); when run without
  one (as by Claude), `lab.sh` only warns. It is a safety net now.

### Done: Terraform review (terraform-skill, 2026-11-01; e537162 + follow-up)
- `bootstrap/` rewritten and **applied**: bucket adopted (4 imported),
  versioning + 90-day expiry + TLS-only policy added; re-plan clean (D-044).
- Lab cleanup: `admin_cidr`/`enable_bootstrap_ssh` removed; all variables in
  `variables.tf`; `hosts` validations; `control_node_role` flag;
  `terraform.tfvars.example`; module `versions.tf`; runtime `~> 1.11`.
- IAM rename **applied**: role/profile `ahmed-control-node`; control01
  verified (inventory 6 hosts, vault decrypts); 35/35 tests; re-plan clean.
  The old inline policies were deleted a few seconds before the new role
  existed (no impact, nothing was running); `create_before_destroy` now on
  the inline policies too.
- `lab.sh down` shows every resource before destroying; 12 mock tests (D-045).

### Done: FreeIPA on idm01 (roadmap item 1, 2026-11-01)
All seven steps from `docs/architecture/freeipa-options.md` done:
- Decisions D-046 to D-051 (all recommended options); Ahmed also chose: separate
  `ahmed.admin`, a test key per user in Vault, ops' network path to servers
  deferred, one example contractor.
- Terraform: 47 SG rules applied (IPA ports to idm01 only).
- Ansible: server, five clients, identity data. Six build problems found and
  fixed in code (runbook troubleshooting table).
- **Verified:** `lab.sh verify` **65/65** (incl. 20 per-user login/sudo checks,
  allowed and denied); full `site.yml` rerun `changed=0` on all six hosts.
- Not yet run: a complete `lab.sh down` + `up` with IPA from scratch. The IPA
  part of `up` is untested end to end (expect +15 to 20 min); first thing
  next session.

### Done: Per-team VPN policy (roadmap item 2, 2026-11-01)
- Ahmed chose all recommended options: gw01 firewalld + split SGs, ops
  direct from their range, gw01 SSH admin-only, test peers on control01.
  Recorded D-052 to D-055 (D-038 superseded).
- Terraform applied (SG split, ops server SSH). Problem: the old SG delete
  deadlocked; recovered (see section 7), re-plan clean.
- gw01 applied: zones/policies as designed (checked live); laptop VPN works.
- **Verified: `lab.sh verify` 87/87** (incl. 23 per-team traffic tests via
  test peers through wstunnel, allowed and blocked).

### Done: util01 services (roadmap item 3, 2026-11-01/02)
Ahmed's choices: S3 backup/restore; web policy per workstation plus a
per-user layer; workstations blocked except infra and HTTPS via the proxy,
explicit deny for social media and streaming, AI allowed; NFS sec=sys,
workstations only, IPA automount; logs over TLS with IPA certificates,
everything per host. Recorded D-056 to D-059. All applied; problems found
and fixed in code: SSSD stuck offline after the SG gap, automount guard,
NFS conf.d directory, 0755 homes, rsyslog UMask (logs unreadable for the
security team), missing PTR records (log directories named by IP).
**Verified: `lab.sh verify` 121/121.**

### Done: Storage (roadmap item 4, 2026-11-02)
Ahmed's choices: team shares on NFS from util01; workstations hold no data
(minimal OS disk), util01 gets the space; quotas per user and per team;
team-only shares plus a company share. D-061. Applied on the live lab: second
disk added to vg_data, lv_home grown online, quotas switched on by remount,
both workstations replaced (10 GiB) and re-enrolled (new: release the old IPA
entry first). Problems fixed: share list rendered as a string; ACL test ran
over NFSv4 (POSIX ACLs are only visible on util01).

### Next
Roadmap item 5: patching cadence, logging/audit, backup/restore drills
(measured RTO), OpenSCAP compliance, app01, incident drills.

---

## 11. Roadmap (after Vault)

1. **Done 2026-11-01.** FreeIPA on idm01: users, groups per team, host groups, HBAC, sudo rules,
   SSH keys, DNS for ahmed.internal; enroll all hosts (answers "one account on
   every server").
2. **Done 2026-11-01.** Per-team VPN policy on gw01 (each team range reaches only its workstations).
3. **Done 2026-11-02.** util01: Squid with per-team ACLs + workstation egress forced through the
   proxy; NFS home directories + autofs; central rsyslog; backups.
4. **Done 2026-11-02.** Storage (LVM, quotas, extra volumes), permissions/SELinux for shared team dirs.
5. Patching cadence, logging/audit, backup/restore drills (measured RTO),
   OpenSCAP compliance, app01 (web/db tier), incident drills.
6. Possible upgrades: golden image (Image Builder/Packer) to shorten rebuilds,
   SSH certificates, execution environments, SSM break-glass.

Team policy reference (`docs/org-structure`): dev (ahmed), ops (sara),
dba (omar), security (laila), contractors; each with login scope, sudo scope and
internet policy. Checklist for adding a team (e.g. HR) is in that file.

---

## 12. Open items / cleanup

- `CLAUDE.md` is tracked in Git since 2026-11-02 (Ahmed's decision). Keep
  secrets, the AWS account ID and instance IDs out of it.
- chrony's AWS time source comes from the image's default config, not from
  the base role (now guarded by a test); consider managing it in `base`.
- SSHFP records exist, but without DNSSEC OpenSSH only reports a match and
  still relies on known_hosts; D-036 trust-on-first-use is reduced, not gone.
- amazon.aws warns that the `tags` host variable is removed "after
  2026-12-01". Checked 2026-11-01: nothing in `ansible/` or `scripts/` reads
  `tags` (all use `ec2_tags`), so the removal should be harmless; recheck
  after any collection upgrade.
- Possible: default tag `Layer = "lab"` on the lab layer (touches every
  resource's tags in place, so do it in its own change).
- Per-user web/NFS controls rely on users not having root: ops have full
  sudo on ws-ops01 and could bypass both there (D-057, D-058).
- Backups are tar.gz of all of util01's data each time (fine at lab size);
  restic or incremental tar if it grows.
- No CI or linters by choice (Ahmed, 2026-11-02): the lab is verified by
  `scripts/test-lab.sh` and the Terraform mock tests.
- After INC-005: enable MFA and set a new console password for
  `ahmeddhussain`; keep a single long-term key; consider short-lived
  credentials (IAM Identity Center) instead of access keys.
- **AWS account is on the Free plan** (credits, no card charges): $107.59
  left on 2026-11-02, plan **expires 2026-12-21** (account closes unless
  upgraded to paid). Check with `aws freetier get-account-plan-state`.
  After an upgrade, lab costs hit the card: always `lab.sh down`.
- Never commit: `*.pem`, `*.key`, `*.tfvars`, vault passwords (see `.gitignore`).