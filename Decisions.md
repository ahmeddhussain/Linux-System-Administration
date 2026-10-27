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