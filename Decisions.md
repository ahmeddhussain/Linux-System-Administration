# Decision Log

Every design choice: what we chose, what else we considered, and why.

## D-001: Distribution - RHEL 10
- **Chosen:** Red Hat Enterprise Linux 10 (official Red Hat AMI)
- **Alternatives:** Rocky Linux 10, AlmaLinux 10, Ubuntu LTS, Amazon Linux 2023
- **Why:** It is the exact platform the Red Hat lab and most enterprises
  use, so dnf, SELinux, firewalld, systemd, and IdM behave as in the job.
  Tradeoff: per-hour license cost on EC2, mitigated by stopping instances
  when idle. Rocky 10 is the documented fallback (same commands).

## D-002: Scale - 5 hosts now, app01 added in Phase 10
- **Chosen:** control01, idm01, util01, ws-dev01, ws-ops01; app01 (web and
  database tier) is added in Phase 10
- **Alternatives:** all 6 hosts from day one; 8 hosts with separate log,
  backup, and repo servers; 3 hosts
- **Why:** The company layer (identity, endpoints, policy) is the core of the
  project; application workloads are tenants on top of it. A finished smaller
  project beats an unfinished large one, and adding hosts later through
  Terraform demonstrates growth by code.

## D-003: Tool split - Terraform builds, Ansible configures
- **Chosen:** Terraform for infrastructure, Ansible for configuration
- **Alternatives:** CloudFormation, Pulumi, shell scripts, Ansible for both
- **Why:** Terraform is the industry default for provisioning and keeps state;
  Ansible is agentless and fits sysadmin work over SSH.

## D-004: SSH bootstrap key - reuse existing key, import public key
- **Chosen:** Extract the public key from the existing ivolve key and import
  it via Terraform
- **Alternatives:** Reference an existing AWS key pair by name; generate a
  new project-specific key; SSM Session Manager only
- **Why:** Works in any region and stays reproducible; the private key never
  enters Terraform. The shared key is a bootstrap-only credential and will be
  replaced by per-user keys managed through FreeIPA.

## D-005: Instance sizing
- **Chosen:** t3.medium for idm01 (FreeIPA), t3.small for util01 and the
  workstations, t3.micro for control01
- **Alternatives:** t3.micro everywhere (cheapest)
- **Why:** FreeIPA needs more memory than a 1 GB instance provides, and
  util01 runs several services (proxy, NFS, logs).

## D-006: Identity - FreeIPA
- **Chosen:** FreeIPA (Red Hat IdM) on idm01
- **Alternatives:** local users plus Ansible, OpenLDAP, Microsoft Active
  Directory
- **Why:** Local users do not scale and have no central policy. OpenLDAP
  requires assembling Kerberos, DNS, sudo, and HBAC separately. Active
  Directory is the real-world default but is Windows-based. FreeIPA is Red
  Hat's own product and bundles all of these; it is the closest Linux
  equivalent of AD.

## D-007: control01 and idm01 are separate hosts
- **Chosen:** Separate instances
- **Alternatives:** Merge identity and management on one host
- **Why:** control01 holds admin keys and secrets and must be reachable only
  by the admin; idm01 must be reachable by every host for logins and DNS.
  Security groups work per instance, so merging would expose the control
  plane. Separate hosts can also be rebuilt independently, and FreeIPA is
  heavy and best run on a dedicated host.

## D-008: Web filtering - Squid proxy with per-team ACLs
- **Chosen:** Squid on util01, enforced by firewall rules on workstations
  that block direct outbound web traffic
- **Alternatives:** DNS blocking (BIND RPZ), AWS DNS Firewall, editing
  /etc/hosts
- **Why:** A proxy supports per-team rules and central logs of who tried to
  reach what, like a real enterprise web gateway. Limitation: HTTPS filtering
  is domain-level only (no TLS interception). DNS blocking is added later as a
  second layer.

## D-009: Endpoint configuration - Ansible by host group
- **Chosen:** Ansible roles applied per host group, matching FreeIPA groups
- **Alternatives:** Red Hat Satellite, Puppet, Chef
- **Why:** Agentless and reuses the same inventory and groups. Satellite is
  the enterprise tool but heavy and licensed.

## D-010: Access model - named admin accounts, no root login
- **Chosen:** Admin uses a named account with sudo; root SSH disabled.
  control01 is admin-only. Employees SSH into their team's workstation
  (simulating sitting at their PC). Servers accept SSH only from control01.
- **Alternatives:** Shared root access; employees connect through control01
- **Why:** Every action is tied to a person in the logs, and the management
  host stays out of reach of staff.

## D-011: Region - us-east-1
- **Chosen:** us-east-1 (N. Virginia)
- **Alternatives:** eu-central-1 (Frankfurt), eu-south-1 (Milan)
- **Why:** Widest service and instance availability and usually the lowest
  prices. Higher latency from Egypt is acceptable for SSH work.

## D-012: Network - single VPC, single public subnet, no NAT gateway
- **Chosen:** One VPC and one public subnet; security groups restrict access
- **Alternatives:** Private subnets with a NAT gateway; NAT instance;
  VPC endpoints only
- **Why:** Hosts need outbound internet for packages and a NAT gateway costs
  about $32/month idle. Production design would use private subnets and a
  NAT gateway; this is a documented cost tradeoff.

## D-013: Terraform state - local for now
- **Chosen:** Local state file (gitignored)
- **Alternatives:** S3 backend with locking; Terraform Cloud
- **Why:** Single operator and nothing built yet; migrate to S3 later.

## D-014: Terraform structure - local modules, single root
- **Chosen:** Local modules (network, security-groups, ec2-instance) called
  from one root configuration
- **Alternatives:** Flat files; community registry modules; per-environment
  directories or workspaces
- **Why:** Each module owns one responsibility and has explicit inputs and
  outputs, so adding a host or team is a one-line change. Writing our own
  keeps every line explainable; the structure carries over to registry
  modules later.

## D-015: Security groups - one per host role, separate rule resources
- **Chosen:** One group per role (control, idm, util, workstation); rules as
  separate resources; servers accept SSH only from control01's group; service
  ports opened only when each service is built
- **Alternatives:** One group per host; inline rule blocks; wide-open
  internal rules
- **Why:** New hosts join an existing role group; separate rules avoid
  circular references; least privilege with changes tied to tickets.

## D-016: Terraform state - S3 with native locking
- **Chosen:** S3 bucket ahmed-statefile (versioned, encrypted, public access
  blocked, HTTPS-only) with use_lockfile; bucket created by a separate
  bootstrap config
- **Alternatives:** DynamoDB lock table (deprecated approach); Terraform
  Cloud; local state
- **Why:** Native locking needs no extra table, state is recoverable through
  versioning, and a team could share it. The bootstrap config is needed
  because the bucket must exist before it can hold state.

## D-017: Network - tiered private subnets behind a NAT gateway
- **Chosen:** Public subnet (bastion01, NAT gateway) plus private infra,
  workstation, and app subnets
- **Alternatives:** Single public subnet (cheaper); NAT instance; VPC
  endpoints only; SSM-only access
- **Why:** No server or workstation has a public address. Tier subnets allow
  per-tier policy (for example, proxy rules keyed on the workstation subnet).
  Cost: about $32/month for the NAT gateway if left running, controlled with
  enable_nat_gateway. Supersedes D-012.

## D-018: bastion01 added as the only public host
- **Chosen:** A small public bastion accepting SSH only from the admin IP
- **Alternatives:** control01 as the public host; SSM Session Manager only;
  a VPN gateway
- **Why:** Keeps control01 unreachable from the internet. Admin path:
  laptop -> bastion01 -> control01 -> hosts. Employee path: laptop ->
  bastion01 (jump only) -> workstation. A VPN is the production equivalent;
  SSM will be added later as a break-glass path. Amends D-010 and D-002.

## D-019: Security groups - default deny, explicit flows
- **Chosen:** One group per role generated from a flows map; both sides of
  every connection declared; VPC default group emptied; egress limited to
  HTTPS and internal ICMP
- **Alternatives:** Open egress; inline rules; network ACLs as the main layer
- **Why:** Least privilege, and every opened path is a reviewable one-line
  change tied to a ticket. NACLs may be added later as a second layer.

## D-020: Entry point - a gateway role, SSH jump host now, VPN later
- **Chosen:** gw01 in the public subnet with role `gateway`; hardened SSH
  jump host first, upgraded to a WireGuard VPN gateway in a later phase
- **Alternatives:** control01 as the public host; SSM Session Manager only;
  VPN from day one
- **Why:** The internet can only reach a host that holds no secrets.
  Employees reaching workstations through the gateway simulates the company
  VPN. The role is named for its function, so the upgrade needs no security
  group redesign. SSM is planned as a break-glass path. Supersedes the name
  and scope in D-018.

## D-021: OS image - looked up by name, never replaced by newer images
- **Chosen:** data lookup of the official Red Hat image; instances ignore
  AMI changes after creation
- **Alternatives:** hardcoded AMI ID; custom golden image (Packer or Image
  Builder)
- **Why:** The lookup survives image retirement. Ignoring AMI changes
  prevents Terraform from replacing servers that are patched in place with
  dnf. Golden images are the production upgrade path.

## D-022: Host inventory and instance hardening
- **Chosen:** All hosts defined in one map (hosts.tf), static private IPs,
  FQDN hostnames in ahmed.internal set by cloud-init, IMDSv2 required,
  encrypted gp3 root volumes
- **Alternatives:** One module block per host; DHCP addresses; default
  metadata settings
- **Why:** Adding a host or team is a one-entry change. Stable addresses and
  FQDNs are required by FreeIPA and keep documentation accurate. IMDSv2 and
  encryption are baseline security at no real cost.

## D-023: Remote access - WireGuard VPN on gw01 from day one
- **Chosen:** WireGuard on gw01; public SSH is bootstrap-only and closed
  once the VPN works; only UDP 51820 is exposed
- **Alternatives:** SSH jump host; Libreswan/IPsec; OpenVPN; AWS Client VPN
- **Why:** A VPN is how employees and admins really reach private company
  networks. WireGuard has minimal configuration and one key plus one IP per
  user. Libreswan is the fallback if the kernel module is unavailable.
  Supersedes the jump-host behavior in D-018 and D-020.

## D-024: VPN routing - routed without NAT, per-team address ranges
- **Chosen:** gw01 forwards VPN traffic unmodified; source/destination check
  disabled; private route table sends 10.8.0.0/16 to gw01; admin 10.8.0.0/24,
  dev 10.8.1.0/24, ops 10.8.2.0/24; split tunnel (10.0.0.0/16 only)
- **Alternatives:** Masquerade behind gw01's address; one shared VPN range;
  full tunnel
- **Why:** Destination hosts and logs see the real user address, enabling
  per-team firewall rules and auditing. Note: security group egress also
  applies to forwarded packets, so gw01 needs explicit forwarding egress.

## D-025: Instance types limited by the account plan
- **Chosen:** idm01 on c7i-flex.large (free-tier eligible, 4 GB) instead of
  t3.medium
- **Alternatives:** Upgrade to a paid account plan; run FreeIPA on 2 GB
- **Why:** The free plan rejects non-eligible instance types. 4 GB meets
  FreeIPA's recommended memory without leaving the plan.

## D-026: Bootstrap and break-glass access - EC2 Instance Connect Endpoint
- **Chosen:** AWS Instance Connect Endpoint to control01; gw01 has no
  inbound internet rules until WireGuard is configured, then only UDP 51820;
  gw01 is configured from control01 over SSH
- **Alternatives:** Move control01 to the public subnet with an IP allow
  rule; SSM Session Manager; keep public SSH on gw01 for bootstrap
- **Why:** The control node stays private and the entry is authenticated by
  AWS credentials instead of an IP address. The endpoint remains as
  break-glass access if the VPN fails. Supersedes the temporary public SSH
  in D-023.
## D-027: Automation account - dedicated ansible user with its own key
- **Chosen:** Local `ansible` user on every host, key-only, passwordless
  sudo, key generated on control01; created once via agent forwarding
- **Alternatives:** Continue as ec2-user with the shared bootstrap key;
  root SSH; FreeIPA-managed access only
- **Why:** An accountable, auditable identity separate from humans. Local
  because idm01 itself must be configured before FreeIPA exists.
  Tradeoff: no passphrase for unattended runs; production would use
  short-lived SSH certificates or a secrets vault.

## D-028: Ansible runs from control01, code pulled from Git
- **Chosen:** Repo cloned on control01; changes made on the laptop, pushed,
  then pulled and applied from control01
- **Alternatives:** Run Ansible from the laptop; copy files manually
- **Why:** Git is the source of truth and control01 is the only place
  changes are applied, which keeps the audit trail and the network model
  intact.

## D-029: Ansible inventory - AWS dynamic inventory grouped by tags
- **Chosen:** amazon.aws.aws_ec2 plugin; groups from the Role and Team tags;
  control01 reads it through an IAM instance profile that can only describe
  instances (no stored credentials)
- **Alternatives:** Static hosts file; Terraform-generated inventory file
- **Why:** AWS is the source of truth, so the inventory cannot drift, and
  adding a host or team in Terraform makes it appear in the right groups
  automatically. Tradeoff: depends on correct tags and API reachability.

## D-030: Ansible runtime - Python virtual environment with pinned versions
- **Chosen:** venv on control01 with ansible-core 2.18 and boto3, versions
  pinned in ansible/requirements.txt
- **Alternatives:** OS-packaged ansible-core; pip --user into system Python;
  container execution environments
- **Why:** The packaged ansible-core is older than current collections
  support, and system Python should stay untouched. A pinned venv is
  reproducible and rebuildable from Git. Execution environments are the
  production upgrade path.
  
## D-031: Baseline configuration - Ansible base role on every host
- **Chosen:** Role applied by site.yml: troubleshooting packages, UTC and
  chrony, SELinux enforcing, firewalld with SSH, SSH hardening as a drop-in
  file validated with sshd -t before restart, login banner
- **Alternatives:** One long playbook; shell scripts; editing sshd_config
  in place; disabling SELinux or firewalld for convenience
- **Why:** A role is reusable and every later layer follows the same
  structure. Host firewall and SELinux sit behind the security groups as
  independent layers. A drop-in avoids editing vendor files, and validating
  before restarting prevents self-inflicted lockouts. Timekeeping is
  required for Kerberos and for correlating logs.

  ## D-032: Lab lifecycle - scripted rebuild and teardown from the laptop
- **Chosen:** scripts/lab.sh (up, resume, verify, status, down) plus a helper
  that prepares control01 over SSH; the lab is destroyed between sessions
- **Alternatives:** Manual steps; Makefile or Taskfile; CI pipeline;
  control01 bootstrapping itself via cloud-init
- **Why:** Rebuilds are repeatable and every step is idempotent. Destroying
  between sessions removes the NAT gateway, instance, and address costs.
  The flow needs the laptop's AWS credentials, SSH agent, and tunnel, so
  it runs there. Anything not in Git or Ansible is lost on destroy, which
  enforces infrastructure as code.

## D-033: WireGuard role - scoped HTTPS-only repo, peers as data
- **Chosen:** Dedicated repo definition limited to wireguard-tools over
  HTTPS; server key generated on gw01; peers listed in group_vars; routed
  forwarding through a firewalld policy; VPN port opened in Terraform only
  after the tunnel was configured
- **Alternatives:** epel-release package (plain-HTTP mirrors blocked by our
  egress rules and a broader third-party surface); compiling from source;
  Libreswan; hand-editing the server
- **Why:** Works within default-deny egress, limits third-party packages to
  one, and makes adding a VPN user a one-line data change. Known gap: a
  rebuild regenerates the server key; Ansible Vault is the planned fix.