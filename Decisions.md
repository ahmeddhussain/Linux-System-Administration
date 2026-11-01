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
- **Correction (2026-11-01):** a review found versioning was never enabled
  and there was no TLS-only policy, and terraform/bootstrap held stale
  network code instead of the bucket. Fixed by D-044.

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
  rebuild regenerates the server key (closed by D-043: the key now comes
  from Ansible Vault).

## D-034: Patch baseline - fleet-wide update before configuration
- **Chosen:** patch.yml updates every package, verifies systemd, and
  reboots only when dnf needs-restarting says so; control01 is rebooted
  manually; patching runs first in site.yml
- **Alternatives:** Golden image built with Image Builder or Packer;
  Red Hat Satellite content views; pinning repositories to 10.0; patching
  inside the base role
- **Why:** The image is RHEL 10.0 while the repositories serve 10.2 builds,
  so hosts drifted apart depending on what was installed and when. A partial
  update on gw01 broke systemctl. A single patch level plus a health check
  before reboot prevents both. Golden images are the production upgrade.

## D-035: Verification - tests as a script in Git
- **Chosen:** scripts/test-lab.sh run on control01, grouped by layer, with
  explicit "must be blocked" checks and an optional idempotency run
- **Alternatives:** Manual spot checks; Molecule or InSpec
- **Why:** Repeatable after every change and rebuild, and it tests denial as
  well as access, which is where default-deny designs usually fail.
## D-036: SSH host identity - keyed to instance ID, not IP
- **Chosen:** HostKeyAlias set to the EC2 instance ID in the dynamic
  inventory; accept-new (trust on first use) kept
- **Alternatives:** Remove stale known_hosts lines by hand after each
  replacement; disable host key checking; central host keys through FreeIPA
  (SSHFP)
- **Why:** Fixed private IPs are reused when a server is replaced, but
  instance IDs are not, so a new host is a new identity and impersonation is
  still detected. Disabling checking would make every connection blind.
  FreeIPA-managed host keys are the planned upgrade and close the
  trust-on-first-use gap.
## D-037: Control node sizing and patch batching
- **Chosen:** control01 and gw01 on t3.small (2 GB); patch.yml runs two
  hosts at a time and checks that the SSH configuration still parses before
  any reboot
- **Alternatives:** Swap file on 1 GB hosts; excluding control01 from
  patching; patching all hosts at once
- **Why:** On 1 GB, control01 ran out of memory while patching itself and
  the fleet; the killed update left crypto-policies ahead of the SSH client,
  which broke every outbound SSH connection. A control node must not be the
  weakest machine, and batching limits load during updates.

## D-038: VPN firewall zone - permanent interface binding
- **Chosen:** wg0 bound to the trusted zone in firewalld's permanent
  configuration; the tunnel config no longer runs firewall commands; the
  role fails if the running tunnel does not have every configured peer
- **Superseded (2026-11-01) by D-052:** wg0 is now in a DROP zone and each
  team range in its own zone; the permanent-configuration lesson stands.
- **Alternatives:** Runtime binding through PostUp in wg0.conf
- **Why:** Runtime firewall state is wiped by any firewalld reload, restart,
  or package update, which silently broke VPN forwarding after patching. A
  permanent binding survives all of these.

## D-039: VPN endpoint open to any source address
- **Chosen:** UDP 51820 on gw01 allowed from 0.0.0.0/0 (vpn_client_cidr);
  access is controlled by WireGuard peer keys
- **Alternatives:** Allow only the admin's IP; allow the provider's address
  range; AWS Client VPN
- **Why:** Employees connect from anywhere, and a VPN gateway cannot know
  their addresses in advance. WireGuard silently drops any packet not signed
  by a known key, so the open port reveals nothing. All other ports stay
  closed to the internet. (The original reason, a changing admin address,
  was disproved during INC-001.) Amends D-023 and D-026.

## D-040: VPN transport - WireGuard inside TLS on TCP 443 (wstunnel)
- **Chosen:** wstunnel server on gw01 (pinned version, SHA-256 verified,
  unprivileged systemd service) carrying WireGuard inside TLS on TCP 443;
  WireGuard's UDP 51820 is closed to the internet and reached only through
  wstunnel on localhost
- **Alternatives:** Plain WireGuard on UDP 51820; WireGuard on a different
  UDP port; OpenVPN over TCP 443; AmneziaWG
- **Why:** INC-001 proved that WireGuard traffic is dropped on the admin's
  network while ordinary HTTPS passes. Changing the port would not help
  because the traffic is recognized by content. wstunnel keeps every part
  of the WireGuard design. The TLS layer is camouflage only; WireGuard
  inside provides encryption and peer authentication. Tradeoffs: one
  third-party binary, and TCP adds latency. Amends D-023 and D-039.
## D-041: Lab scripts split by responsibility; VPN client automated
- **Chosen:** lab.sh as a thin entry point over lib/ (infra, control01,
  configure); a separate vpn-client.sh for the laptop; up reboots control01
  when patching requires it, runs the tests, and refreshes the VPN client
- **Alternatives:** One long lab.sh; a Makefile; manual steps after rebuild
- **Why:** Each file has one job, and a rebuild ends ready to connect with
  no manual edits. The gateway key still changes per rebuild until it is
  stored in Ansible Vault.

## D-042: Persistent Terraform layer for resources that outlive the lab
- **Chosen:** terraform/persistent with its own state
  (ahmed-infra/persistent.tfstate) in the same bucket; every resource has
  prevent_destroy; lab.sh down never touches it
- **Alternatives:** keep everything in the lab layer and exclude resources
  from destroy with -target; create long-lived resources by hand; a separate
  AWS account for shared services
- **Why:** The lab is destroyed every session, but some things must survive
  rebuilds (first: the Ansible Vault password). A separate state makes the
  boundary structural instead of relying on remembering -target flags, and
  keeps those resources in code. Separate accounts are the production
  pattern but too heavy for a single-operator lab.

## D-043: Ansible Vault password stored in SSM, read by control01's role
- **Chosen:** SSM SecureString /ahmed-infra/ansible-vault-password (AWS
  managed key aws/ssm), generated by an ephemeral random_password and written
  through the write-only value_wo argument; control01's instance role may
  read /ahmed-infra/* and decrypt only via SSM; ansible.cfg calls
  scripts/vault-password.py
- **Alternatives:** password file on control01 (lost on rebuild, or copied by
  hand); password typed at every run (breaks unattended lab.sh); AWS Secrets
  Manager (about $0.40/month per secret, rotation features unused);
  HashiCorp Vault (another server to run); a normal random_password resource
  (the password would sit in plain text in state)
- **Why:** Survives rebuilds, needs no human step, and no copy of the
  password exists in Git, state, or on disk. Standard parameters are free.
  The role cannot write or read outside the project prefix (verified from
  control01). Tradeoff: anyone with control01 root can read the password,
  which matches control01 already being the most trusted host. Rotating
  means rekeying every vault file before bumping vault_password_version.
- **First use:** gw01's WireGuard private key in
  group_vars/role_gateway/vault.yml, encrypted as a whole file (rather than
  encrypt_string) so not even variable names are visible. The matching
  public key is recorded in plain text next to it; the role refuses a vault
  key that does not match, so a wrong vault file cannot silently break every
  client.

## D-044: State bucket adopted into code, versioned, TLS-only
- **Chosen:** terraform/bootstrap rewritten to describe only the existing
  ahmed-statefile bucket, adopted with import blocks; versioning enabled,
  old versions expire after 90 days, TLS-only bucket policy; SSE-S3 with a
  bucket key kept as created; its own state in the same bucket
  (ahmed-infra/bootstrap.tfstate)
- **Alternatives:** leave the bucket hand-managed; recreate it from code
  (would mean migrating every state); local state for the bootstrap layer;
  customer managed KMS key
- **Why:** The bucket holds every layer's state and was the one piece not in
  code, and its missing versioning meant an overwritten state could not be
  recovered. Import blocks make adoption reviewable and repeatable without
  touching the data. Keeping its state in the bucket avoids a laptop-only
  file; if the bucket is ever lost, the backend block is commented out and
  the layer is applied locally. KMS adds cost and key policy work with no
  benefit for a single-account lab.

## D-045: Terraform tests with mocked providers
- **Chosen:** native terraform test with mock_provider: module tests for
  security-groups (default deny, both halves of each flow, unknown roles
  rejected) and network (NAT toggle, public addressing), and root tests for
  the host inventory validations
- **Alternatives:** Terratest against real AWS; plan review only; tflint or
  checkov only
- **Why:** Free, fast, need no credentials, and test the rules this design
  depends on (default deny, one control node, no duplicate addresses).
  Real-infrastructure checks stay in scripts/test-lab.sh. Static scanners
  (tflint, trivy, checkov) are a planned addition.

## D-046: FreeIPA installation shape - realm, CA, single server
- **Chosen:** realm AHMED.INTERNAL, domain ahmed.internal; integrated IPA
  CA (self-signed root); one server (idm01), no replica
- **Alternatives:** subdomain ipa.ahmed.internal; CA-less install or an
  external CA; a replica on a second instance
- **Why:** The hostnames already live in ahmed.internal, so realm and DNS
  domain match without renaming. The realm cannot be changed after install.
  The integrated CA issues host and service certificates automatically,
  which the web UI and LDAPS need; there is no external CA to chain to. A
  replica needs another 4 GB instance outside the free plan; the lab is
  rebuilt every session, so idm01 being a single point of failure is
  accepted and a replica is kept as a later exercise. Details and rejected
  options: docs/architecture/freeipa-options.md.

## D-047: DNS - FreeIPA integrated DNS, forwarding to the VPC resolver
- **Chosen:** ipa-server-dns serves ahmed.internal and forwards everything
  else to the VPC resolver (10.0.0.2); clients list idm01 first and
  10.0.0.2 second, switched by Ansible after idm01 is installed
- **Alternatives:** Route 53 private hosted zone with IPA installed without
  DNS; /etc/hosts with explicit --server enrollment; resolver set through
  the VPC DHCP options
- **Why:** Enrollment creates host and service records automatically, and
  SSHFP records let SSH verify host keys, closing the trust-on-first-use gap
  in D-036. Route 53 would duplicate the host list and need service records
  by hand. DHCP options would point hosts at idm01 at boot, before it
  exists. Tradeoff: name resolution depends on idm01; the second resolver
  only helps when idm01 does not answer, not when it answers wrongly.

## D-048: FreeIPA lifecycle - rebuilt from code every session
- **Chosen:** idm01 is destroyed with the lab and rebuilt by Ansible;
  users, groups, host groups, HBAC and sudo rules are data in Git;
  logins by SSH key; nothing is changed by hand in IPA
- **Alternatives:** keep idm01 alive across sessions; rebuild then restore
  ipa-backup from S3
- **Why:** Same rule as the rest of the lab (D-032): what is not code is
  lost, which keeps the identity layer reviewable and adding a team a data
  change. Keeping idm01 alive would let it drift from the code; restoring
  backups daily would tie every session to an exact IPA version. Tradeoffs:
  an estimated 15 to 20 minutes more per lab.sh up, and a new CA root every
  session. Backup and restore is kept as a planned drill.

## D-049: FreeIPA secrets in Ansible Vault
- **Chosen:** admin and Directory Manager passwords (and any initial user
  passwords) generated once and stored in group_vars/role_idm/vault.yml,
  decrypted with the SSM-held Vault password (D-043); tasks use no_log
- **Alternatives:** prompt at install time; separate SSM parameters read
  by idm01 through its own IAM role
- **Why:** Reuses a mechanism already proven in this lab and keeps
  lab.sh up unattended. A second mechanism would give idm01 an IAM role for
  no gain. Tradeoff as in D-043: root on control01 can read them.
- **As built (2026-11-01):** clients never receive the admin password.
  Each host is enrolled with a one-time password that the playbook creates
  on idm01. Private test keys for the IPA users are in
  ansible/tests/test-user-keys.vault.yml.

## D-050: FreeIPA automation - freeipa.ansible_freeipa collection
- **Chosen:** the collection maintained by the FreeIPA project, pinned in
  ansible/requirements.yml: ipaserver and ipaclient roles, and the ipauser,
  ipagroup, ipahostgroup, ipahbacrule and ipasudorule modules; the
  underlying install commands documented in a runbook
- **Alternatives:** ipa-server-install and ipa-client-install through
  command tasks, ipa CLI scripts for users
- **Why:** Idempotent and data-driven, and the same modules install the
  server and manage identity data. Command tasks would need hand-written
  guards and turn user management into scripts. The runbook keeps the
  course-level commands visible.
- **As built (2026-11-01), deviations from the role defaults, each with a
  comment in the code:** `state: present` passed to the roles (the AWS
  inventory defines a host variable `state`); clients enroll against
  idm01's full name; the one-time password is created by the play through
  idm01's inventory name instead of by the role; modules on control01 use
  the system Python; SSSD's cache is reset on clients when the identity data
  changes, because SSSD otherwise keeps an empty sudo rule cache.

## D-051: FreeIPA network access and enrollment scope
- **Chosen:** idm01 accepts DNS 53 (TCP/UDP), Kerberos 88 and 464
  (TCP/UDP), LDAP 389, LDAPS 636, HTTP 80 and HTTPS 443 from the VPC CIDR;
  every other host role may send those ports to idm01's address only; the
  web UI (443) is also reachable from the VPN admin range; all six hosts
  enroll, with HBAC limiting gw01 to the admin group; the local ansible
  account stays everywhere (D-027)
- **Alternatives:** role-to-role flows per port (about 72 rules, near the
  60-rule default limit per group); enrolling everything except gw01
- **Why:** Every host in the VPC is an IPA client by design, so the VPC
  CIDR is the honest boundary, and egress is still pinned to idm01's single
  address. Enrolling gw01 makes admin logins on the edge host named and
  audited, at the cost of a host keytab that only identifies gw01. The
  local automation account means Ansible never depends on IPA being up.

## D-052: Per-team VPN policy - firewalld on gw01 plus split security groups
- **Chosen:** on gw01, one firewalld zone per team VPN range (vpn-admin,
  vpn-dev, vpn-ops, by source address) and one forwarding policy per team
  that allows only the hosts and ports listed in group_vars; wg0 itself sits
  in a zone that drops everything else. Zones and policies are written as
  firewalld XML from templates, so the files on gw01 always equal the data.
  In AWS, the shared workstation security group is split into
  workstation-dev and workstation-ops, each accepting SSH only from admin
  and its own team's range.
- **Alternatives:** firewalld only; security groups only; firewall-cmd
  commands per rule; nftables written directly
- **Why:** Two independent layers enforce the same boundary, so one mistake
  is not an open path. firewalld matches the design of the rest of the
  lab; whole-file templates make removing a rule as reliable as adding one
  (rule-by-rule commands only ever add). The ansible.posix firewalld module
  has no policy support. Supersedes the trusted-zone binding of D-038 and
  the single vpn_to_vpc policy.

## D-053: Ops reach servers directly from the ops VPN range
- **Chosen:** 10.8.2.0/24 may SSH to idm01 and util01 (gw01 policy and a
  security group rule on each); IPA login rules remain the second check
- **Alternatives:** jump through ws-ops01; keep it deferred; through control01
- **Why:** Routed without NAT (D-024), so server logs show sara's own VPN
  address. A jump host adds a hop and a workstation-to-server path that dev
  workstations must not get. control01 stays admin-only (D-010).

## D-054: gw01 itself - SSH from the admin VPN range only
- **Chosen:** from the tunnel, only the admin range may open SSH to gw01;
  other ranges get ICMP only
- **Alternatives:** nothing from the VPN (admins via control01 only); leave
  every port open to every peer (the state before this change)
- **Why:** gw01 is admin-only (D-051). Admin SSH from the VPN helps when the
  gateway itself needs debugging; every other port and team is refused.

## D-055: Per-team VPN tests with synthetic peers on control01
- **Chosen:** one WireGuard test peer per team (10.8.0.250, 10.8.1.250,
  10.8.2.250), keys in Vault, run by test-lab.sh in network namespaces on
  control01 and carried by wstunnel to gw01's TCP 443, like a real client
- **Alternatives:** check the firewall configuration only; wait for real
  team devices; plain WireGuard over UDP inside the VPC
- **Why:** Proves each team's allowed and blocked paths with real traffic
  through the real transport. Going through wstunnel needs no new security
  group flow and keeps UDP 51820 closed. The WireGuard interface is created
  in the main namespace and moved into the test namespace, so its socket
  can reach wstunnel on localhost while the test traffic is isolated.

## D-056: util01 data - rebuilt each session, backed up to S3, restored on up
- **Chosen:** the 20 GB data volume stays in the lab layer, as LVM (volume
  group vg_data: lv_home for NFS homes, lv_logs for central logs);
  util01 backs homes and logs up with tar + awscli2 to a versioned S3
  bucket in the persistent layer (old versions expire after 30 days) on a
  daily timer and before lab.sh down; Ansible restores the latest backup
  when the volume is new; util01 gets an instance role limited to that
  bucket
- **Alternatives:** a persistent EBS volume attached on every up; ephemeral
  data; restic from EPEL; AWS Backup
- **Why:** Keeps the lab rebuilt from code (D-032) and turns every session
  into a real backup and restore drill with a measurable restore time
  (roadmap item 5). A persistent volume would cost while the lab is down
  and would still not be a backup. awscli2 and tar come from Red Hat's own
  repositories, so no new third-party repository is added (as in D-033);
  S3 versioning provides the history restic's snapshots would.

## D-057: Web access - forced proxy, policy per workstation and per user
- **Chosen:** workstations have no direct internet access; their security
  groups allow only IPA/DNS on idm01, SSH from control01, and Squid on
  util01. Squid allows HTTPS (CONNECT to port 443) only, with one listening
  port per policy: "standard" (everything except explicit deny lists:
  social media, video streaming; AI sites allowed) for dev and ops, and
  "allowlist" (package repositories, GitHub, Red Hat and Python docs) for
  dba and contractors. Each workstation's nftables lets a user reach only
  the port of their own team's policy, matched by the user's primary group,
  which IPA sets to the team group.
- **Alternatives:** per workstation only; per user with Kerberos proxy
  authentication (needs user passwords, changes D-048); host firewall only
  for the forced proxy; DNS-level blocking
- **Why:** The security groups make the proxy unavoidable even for root
  on a workstation. Policy by workstation alone would give contractors on
  ws-dev01 the dev policy and dba on ws-ops01 the ops policy; matching the
  socket owner's group on the workstation adds the per-user layer without
  passwords. Contractors and dba have no root on their workstations, so
  they cannot remove it; ops have full sudo on ws-ops01 but already get the
  more open policy. HTTPS is filtered by domain only (no TLS interception,
  as D-008 says). Plain HTTP is not proxied (port 80 stays closed, D-034).

## D-058: NFS home directories - util01, workstations only, sec=sys, IPA automount
- **Chosen:** util01 exports /export/home over NFSv4 only (no v3, no UDP)
  with sec=sys and root_squash, to the two workstation addresses only;
  TCP 2049 is open only from the workstation security groups. IPA holds the
  automount map (location default, auto.home mounted at /users, key *);
  only the workstations run autofs. IPA users' home directory is
  /users/<name>; local accounts (ansible, ec2-user) keep /home. Home
  directories are created on util01 from the identity data.
- **Alternatives:** sec=krb5p (needs user passwords and tickets, changes
  D-048); homes on every host; automount maps as files from Ansible;
  automounting /home itself
- **Why:** Works with key-only logins now. Workstations only, so servers
  never depend on util01 for logins. The IPA map is central, like the rest
  of identity. /home cannot be automounted because that would hide the
  local accounts, including the ansible account's SSH key. Known gap: with
  sec=sys the server trusts the workstation's user IDs, so root on a
  workstation (ops on ws-ops01) could read other users' homes; the
  upgrade is krb5p once users have passwords.

## D-059: Central logs - rsyslog over TLS with IPA certificates, per host
- **Chosen:** every host sends all messages to rsyslog on util01 over TCP
  6514 with TLS (OpenSSL driver), using its own certificate from the IPA
  CA (certmonger requests and renews it) and checking util01's name; a
  disk-backed queue holds messages while util01 is down. util01 accepts
  only senders with a valid IPA certificate and stores
  /srv/logs/<host>/<program>.log, the host taken from the sender's address
  (reverse DNS in IPA), readable by the IPA group security; 14 days of
  rotation, older copies in the S3 backups (D-056). Squid's access log is
  sent to syslog too.
- **Alternatives:** plain TCP 514; RELP; only security-relevant logs; the
  journal's own remote upload (systemd-journal-remote)
- **Why:** Logs carry authentication and sudo records, so they are
  encrypted and only accepted from hosts the IPA CA vouches for; the CA
  already exists, so no new PKI. Naming directories by the sender's
  address stops one host from writing into another's. Everything per host
  is the easiest to search and to grant to the security team.
