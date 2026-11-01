# FreeIPA on idm01: options to decide before any code

Status: **proposal, awaiting Ahmed's decisions** (2026-11-01). Each chosen
option becomes a `D-0xx` entry in `Decisions.md`; this file then records
why the others were rejected.

Goal (roadmap item 1): one account on every server. Users, team groups, host
groups, login rules (HBAC), sudo rules and SSH keys are managed centrally,
and every host is enrolled. This matches the teams in `org-structure`.

Fixed by earlier decisions: FreeIPA (D-006) on its own host idm01
(D-007, `c7i-flex.large`, 4 GB, D-025); hostnames are already FQDNs in
`ahmed.internal` (D-022); chrony is running everywhere (D-031). Kerberos
fails if clocks drift, so that matters here.

---

## Summary: recommendations

| # | Decision | Recommended | Main alternative |
|---|---|---|---|
| 1 | Realm and domain | `AHMED.INTERNAL` / `ahmed.internal` | separate subdomain `ipa.ahmed.internal` |
| 2 | DNS | FreeIPA integrated DNS, forwarding to the VPC resolver | Route 53 private zone, IPA without DNS |
| 3 | Lifecycle across `lab.sh down` | rebuild from code every session | keep idm01 alive / backup and restore |
| 4 | Certificate authority | integrated IPA CA (self-signed root) | no CA / external CA |
| 5 | Secrets | Vault, same as D-043 | prompt at install |
| 6 | Automation | `freeipa.ansible_freeipa` collection, pinned | `ipa-server-install` via command tasks |
| 7 | Network rules | CIDR rules from the VPC to idm01 | role-to-role flows per port |
| 8 | Which hosts enroll | all six, including gw01 and control01 | everything except gw01 |
| 9 | Replica | none (single server) | second IPA server |

Each item below gives the options, the tradeoffs and the reason for the
recommendation.

---

## 1. Realm and domain

| Option | For | Against |
|---|---|---|
| **A. `AHMED.INTERNAL` realm, `ahmed.internal` domain** | Matches hostnames that already exist; no renaming; the conventional layout | IPA becomes authoritative for the whole domain |
| B. `ipa.ahmed.internal` subdomain | Keeps the parent domain free for other DNS | Hosts would have to be renamed into the subdomain, or the Kerberos realm and DNS domain no longer match, which complicates every client |

**Recommended: A.** The realm cannot be renamed after installation, so this
is the one decision that cannot be undone without reinstalling.

## 2. DNS

Today every host uses the AWS VPC resolver (10.0.0.2). Names like
`gw01.ahmed.internal` resolve only through each host's own hostname.

| Option | For | Against |
|---|---|---|
| **A. IPA integrated DNS** (`ipa-server-dns`) for `ahmed.internal`, forwarding everything else to 10.0.0.2 | Host records and service records (how clients find Kerberos and LDAP) are created automatically on enrollment; **SSHFP records** let SSH verify host keys, which closes the trust-on-first-use gap in D-036; it is how the Red Hat course and most IPA sites run | idm01 becomes the name resolver for every host: if it is down, hosts cannot resolve anything, including package mirrors; every host's resolver must be switched, in Ansible, after idm01 is up |
| B. Route 53 private hosted zone (Terraform), IPA installed without DNS | Resolution survives idm01 being down; records are Terraform code | Service records must be maintained by hand in Terraform; no SSHFP automation; about $0.50/month; two systems describe the same hosts |
| C. No DNS: `/etc/hosts` from Ansible; clients enroll with explicit `--server` and `--domain` | Simplest | No service discovery, no SSHFP, nothing like a real deployment; every new host is a manual list change |

**Recommended: A.**
- The resilience risk is real. It is reduced by listing idm01 first and
  10.0.0.2 second on every client: if idm01 is unreachable, resolution
  falls back after a timeout. A wrong answer from idm01 does *not* fall back.
- Security groups do not filter traffic to the VPC resolver. Evidence:
  every host resolves package mirrors today without any port 53 rule.
- **Ordering constraint:** idm01 must be installed before any host is
  switched to it. That fits `site.yml`: patch, then base, then idm server,
  then clients. Changing the resolver through the VPC DHCP options was
  rejected because hosts would use idm01 at boot, before it exists.

## 3. Lifecycle: the lab is destroyed every session

This is the biggest design question. `lab.sh down` destroys idm01, and with
it every user, password, group and certificate.

| Option | For | Against |
|---|---|---|
| **A. Rebuild from code every session**: users, groups, host groups, HBAC and sudo rules are Ansible data (`ipauser`, `ipagroup`, `ipahbacrule`, `ipasudorule`); login by SSH key; initial passwords from Vault | Same model as the rest of the lab (D-032): everything is code; adding a team is a data change (`org-structure` checklist); reviewable in Git | Adds an estimated 15 to 20 minutes to `lab.sh up`; anything changed by hand in the IPA web UI is lost; the IPA CA is new each session, so nothing outside the lab may trust it |
| B. Keep idm01 alive (stop/start, excluded from destroy) | Fast sessions; IPA state persists | Splits the lab layer (D-042-style move into the persistent layer); costs EBS while stopped; drift between code and a long-lived server; breaks "rebuild proves it works" |
| C. Rebuild, then restore `ipa-backup` from S3 | Keeps manual changes | Restore must match the IPA version exactly; adds a backup bucket and a restore path to maintain. Better as a later **backup/restore drill** (roadmap item 5) than as the daily mechanism |

**Recommended: A.** Rule: never change IPA by hand; change the data and
rerun. Option C is kept for the planned restore drill.

## 4. Certificate authority

| Option | For | Against |
|---|---|---|
| **A. Integrated IPA CA** (self-signed root) | Host and service certificates are issued automatically; required for the web UI and LDAPS; default install | Root is new every rebuild (see 3A); browsers warn unless you import it each session |
| B. CA-less install | No CA to run | Every certificate must be supplied by hand; much more work |
| C. External CA signs the IPA CA | Enterprise pattern | No external CA exists in this lab |

**Recommended: A.**

## 5. Secrets

The install needs the `admin` password and the Directory Manager password.
User initial passwords may also be needed.

| Option | For | Against |
|---|---|---|
| **A. Ansible Vault**: `group_vars/role_idm/vault.yml`, password from SSM (D-043) | Already proven in this lab; unattended; never in Git or logs | Anyone with root on control01 can read them (same tradeoff as D-043) |
| B. Prompt at install time | Nothing stored | Breaks unattended `lab.sh up` |
| C. New SSM parameters read by idm01 directly | Separate from Ansible | Gives idm01 an IAM role; duplicates the Vault mechanism |

**Recommended: A.** Generate the passwords once; every task that touches
them uses `no_log: true`, and the logs are checked for leaks as in Step 2
of the Vault work.

## 6. Automation

| Option | For | Against |
|---|---|---|
| **A. `freeipa.ansible_freeipa` collection** (maintained by the FreeIPA project; `ipaserver`, `ipaclient` roles plus modules for users, groups, HBAC and sudo), pinned in `requirements.yml` | Idempotent; data-driven; same modules for install and for managing users | A large collection to understand; the roles have many variables |
| B. `ipa-server-install` / `ipa-client-install` via command tasks, `ipa` CLI for users | Transparent; matches the course exactly | Not idempotent without hand-written guards; user management becomes a shell script |

**Recommended: A**, with the actual install commands documented in a
runbook so the underlying steps stay visible.

## 7. Network rules (security groups)

Clients need these ports to idm01: DNS 53 (TCP/UDP), Kerberos 88 and 464
(TCP/UDP), LDAP 389, LDAPS 636, HTTPS 443, and HTTP 80 (certificate
revocation checks). Time comes from AWS, so no NTP rule is needed.

| Option | For | Against |
|---|---|---|
| **A. CIDR ingress on the idm group from the VPC CIDR** (one rule per port and protocol, about 9) | Few rules; any host added to the VPC can enroll; fits the existing `cidr_ingress` map | Wider than strictly needed (the Instance Connect Endpoint subnet is included) |
| B. Role-to-role flows (gateway, control, util, workstation to idm, per port) | Exact least privilege; same style as today's SSH flows | About 36 flows (72 rules); the `flows` map has one port per entry, so it grows a lot; nears the default limit of 60 inbound rules per group |
| Plus, either way | Web UI (443) to idm01 from the VPN admin range only | |

Each host's egress also needs the same ports to idm01: today egress is only
443 and ICMP. That is one egress rule per port, for all host roles together.

**Recommended: A.** Every host in the VPC is an IPA client by design, so
the VPC CIDR is the honest boundary. Revisit B if the VPC ever holds hosts
that must not reach identity.

## 8. Which hosts enroll

| Option | For | Against |
|---|---|---|
| **A. All six** | "One account on every server" holds without exceptions; admin logins on gw01 become named and audited | gw01 is internet-facing; a compromise exposes its host keytab (which identifies only gw01) |
| B. All except gw01 | Smaller exposure on the edge host | gw01 keeps local accounts, an exception to manage and audit separately |

**Recommended: A**, with HBAC limiting gw01 logins to the admin group.
The local `ansible` account stays on every host (D-027), so automation never
depends on IPA being healthy.

## 9. Replica

| Option | For | Against |
|---|---|---|
| **A. Single server** | Fits the free-tier plan and cost; acceptable because the lab is rebuilt every session | idm01 is a single point of failure for logins and (with 2A) DNS |
| B. Second IPA server (replica) | Real high availability; practise replication | Another 4 GB instance; not free-tier at this size |

**Recommended: A.** A replica is a good later exercise, documented as
such.

---

## What happens after the decisions

One step at a time, each verified before the next:

1. Record D-046 onward from the choices above.
2. **Terraform**: idm01 ingress and host egress rules (7). Plan, review, apply.
3. **Vault**: `group_vars/role_idm/vault.yml` with the generated passwords (5).
4. **Ansible `idm_server`**: install IPA on idm01 (1, 2, 4, 6) and verify
   `kinit admin`, `ipa ping`, DNS answers.
5. **Ansible `idm_client`**: enroll hosts one at a time, control01 last.
   Then switch resolvers (2).
6. **Identity data**: teams, users and keys from `org-structure`, plus host
   groups, HBAC and sudo rules (3A).
7. **Tests** in `test-lab.sh`: an IPA user can log into their team's
   workstation and is refused elsewhere; sudo rules behave; SSHFP records
   exist; resolution falls back when idm01 is unreachable.

## Questions for Ahmed

Answer with the numbers (for example "all recommended", or "3B, rest
recommended"):

1. Realm `AHMED.INTERNAL`: OK? (cannot be changed later)
2. DNS: IPA integrated (A), Route 53 (B), or none (C)?
3. Lifecycle: rebuild from code every session (A), keep idm01 alive (B),
   or backup and restore (C)?
4. to 9.: accept the recommendations?
