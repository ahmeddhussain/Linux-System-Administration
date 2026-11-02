# Network policy (D-015, D-019, D-051 to D-059): security group roles,
# role-to-role flows and IP-range rules. Anything not listed here is denied.
# The security-groups module turns these maps into rules (main.tf).

locals {
  # Security group roles. "eice" is the instance connect endpoint, not a host.
  # Each team's workstation has its own group, so AWS enforces the same
  # per-team boundary as gw01's firewall (D-052).
  roles      = toset(["eice", "gateway", "control", "idm", "util", "workstation-dev", "workstation-ops"])
  host_roles = setsubtract(local.roles, ["eice"])

  # Security group of each host: its own override, or its role.
  host_security_group = { for name, h in var.hosts : name => coalesce(h.security_group, h.role) }

  # Which workstation group each team's VPN range may reach.
  team_workstation_sg = {
    dev = "workstation-dev"
    ops = "workstation-ops"
  }
  workstation_sgs = toset(values(local.team_workstation_sg))

  # Squid ports on util01, one per web policy (D-057).
  proxy_ports = [3128, 3129]

  vpn_admin_cidr = var.vpn_ranges["admin"]

  # FreeIPA on idm01 (D-051). Every enrolled host talks to it on these ports.
  idm_ip = one([for h in values(var.hosts) : h.private_ip if h.role == "idm"])
  ipa_ports = {
    dns_tcp      = { protocol = "tcp", port = 53, description = "DNS" }
    dns_udp      = { protocol = "udp", port = 53, description = "DNS" }
    kerberos_tcp = { protocol = "tcp", port = 88, description = "Kerberos" }
    kerberos_udp = { protocol = "udp", port = 88, description = "Kerberos" }
    kpasswd_tcp  = { protocol = "tcp", port = 464, description = "Kerberos password change" }
    kpasswd_udp  = { protocol = "udp", port = 464, description = "Kerberos password change" }
    ldap         = { protocol = "tcp", port = 389, description = "LDAP" }
    ldaps        = { protocol = "tcp", port = 636, description = "LDAPS" }
    http         = { protocol = "tcp", port = 80, description = "IPA CA revocation (OCSP/CRL)" }
    https        = { protocol = "tcp", port = 443, description = "IPA enrollment, API and web UI" }
  }

  # Approved connections between roles. Anything not listed here is denied.
  # To open a new connection: add an entry, run plan, review, apply, and
  # record the change as a ticket.
  flows = merge({
    eice_to_control = {
      from        = "eice"
      to          = "control"
      protocol    = "tcp"
      port        = 22
      description = "Instance Connect Endpoint to control01 (admin entry and break-glass)"
    }
    control_to_gateway = {
      from        = "control"
      to          = "gateway"
      protocol    = "tcp"
      port        = 22
      description = "SSH control01 to gw01 (Ansible)"
    }
    control_to_idm = {
      from        = "control"
      to          = "idm"
      protocol    = "tcp"
      port        = 22
      description = "SSH control01 to idm01 (Ansible)"
    }
    control_to_util = {
      from        = "control"
      to          = "util"
      protocol    = "tcp"
      port        = 22
      description = "SSH control01 to util01 (Ansible)"
    }
    },
    # Workstations reach the web only through Squid on util01 (D-057): one
    # port per policy (3128 standard, 3129 allow-list).
    merge([
      for sg in local.workstation_sgs : {
        for port in local.proxy_ports : "${sg}_to_util_proxy_${port}" => {
          from        = sg
          to          = "util"
          protocol    = "tcp"
          port        = port
          description = "Web proxy (Squid) on util01, port ${port}"
        }
      }
    ]...),
    # Central logging over TLS to rsyslog on util01 (D-059).
    {
      for r in setsubtract(local.host_roles, ["util"]) : "${r}_to_util_syslog_tls" => {
        from        = r
        to          = "util"
        protocol    = "tcp"
        port        = 6514
        description = "Logs over TLS to rsyslog on util01"
      }
    },
    # NFSv4 home directories on util01 (D-058).
    {
      for sg in local.workstation_sgs : "${sg}_to_util_nfs" => {
        from        = sg
        to          = "util"
        protocol    = "tcp"
        port        = 2049
        description = "NFSv4 home directories on util01"
      }
    },
    {
      for sg in local.workstation_sgs : "control_to_${sg}" => {
        from        = "control"
        to          = sg
        protocol    = "tcp"
        port        = 22
        description = "SSH control01 to ${sg} (Ansible)"
      }
    }
  )

  # From outside a role: IP ranges allowed in.
  cidr_ingress = merge(
    # The VPN entry: WireGuard carried inside TLS by wstunnel on TCP 443.
    # Closed until the gateway is configured. Open to any address because
    # WireGuard inside only accepts peers with a known key.
    {
      for k, v in {
        vpn_endpoint = {
          role        = "gateway"
          cidr        = var.vpn_client_cidr
          protocol    = "tcp"
          port        = 443
          description = "VPN entry: WireGuard inside TLS (wstunnel)"
        }
      } : k => v if var.enable_vpn_endpoint
    },
    # Admin over the VPN: control01 only for SSH.
    {
      control_ssh_from_vpn_admin = {
        role        = "control"
        cidr        = local.vpn_admin_cidr
        protocol    = "tcp"
        port        = 22
        description = "SSH from VPN admin range"
      }
      control_icmp_from_vpn_admin = {
        role        = "control"
        cidr        = local.vpn_admin_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP from VPN admin range"
      }
    },
    # Admin over the VPN: every workstation (SSH and ICMP).
    {
      for sg in local.workstation_sgs : "${sg}_ssh_from_vpn_admin" => {
        role        = sg
        cidr        = local.vpn_admin_cidr
        protocol    = "tcp"
        port        = 22
        description = "SSH from VPN admin range"
      }
    },
    {
      for sg in local.workstation_sgs : "${sg}_icmp_from_vpn_admin" => {
        role        = sg
        cidr        = local.vpn_admin_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP from VPN admin range"
      }
    },
    # Employees over the VPN: only their own team's workstation (D-052).
    {
      for team, sg in local.team_workstation_sg : "${sg}_ssh_from_vpn_${team}" => {
        role        = sg
        cidr        = var.vpn_ranges[team]
        protocol    = "tcp"
        port        = 22
        description = "SSH from VPN range: ${team}"
      }
    },
    # Ops over the VPN: the servers their login rule allows (D-053).
    {
      for r in ["idm", "util"] : "${r}_ssh_from_vpn_ops" => {
        role        = r
        cidr        = var.vpn_ranges["ops"]
        protocol    = "tcp"
        port        = 22
        description = "SSH from VPN range: ops"
      }
    },
    # FreeIPA: every host in the VPC is a client; the web UI also from the
    # VPN admin range (gw01 already forwards 443 through its HTTPS egress).
    {
      for k, p in local.ipa_ports : "idm_${k}_from_vpc" => {
        role        = "idm"
        cidr        = module.network.vpc_cidr
        protocol    = p.protocol
        port        = p.port
        description = "FreeIPA ${p.description} from the VPC"
      }
    },
    {
      idm_https_from_vpn_admin = {
        role        = "idm"
        cidr        = local.vpn_admin_cidr
        protocol    = "tcp"
        port        = 443
        description = "FreeIPA web UI from VPN admin range"
      }
    },
    # Troubleshooting inside the VPC.
    {
      for r in local.host_roles : "${r}_icmp_in" => {
        role        = r
        cidr        = module.network.vpc_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP from inside the VPC"
      }
    }
  )

  # To outside a role: HTTPS for package repos via NAT, internal ICMP, and the
  # forwarding paths gw01 needs for VPN traffic.
  cidr_egress = merge(
    {
      # Servers only: workstations reach the web through Squid (D-057).
      for r in setsubtract(local.host_roles, local.workstation_sgs) : "${r}_https_out" => {
        role        = r
        cidr        = "0.0.0.0/0"
        protocol    = "tcp"
        port        = 443
        description = "HTTPS to internet via NAT (package repos, updates)"
      }
    },
    {
      for r in local.host_roles : "${r}_icmp_out" => {
        role        = r
        cidr        = module.network.vpc_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP to inside the VPC"
      }
    },
    # FreeIPA client traffic, to idm01's address only. Servers already have
    # HTTPS everywhere above; workstations do not, so they get it here.
    merge([
      for r in setsubtract(local.host_roles, ["idm"]) : {
        for k, p in local.ipa_ports : "${r}_to_idm_${k}" => {
          role        = r
          cidr        = "${local.idm_ip}/32"
          protocol    = p.protocol
          port        = p.port
          description = "FreeIPA ${p.description} to idm01"
        } if k != "https" || contains(local.workstation_sgs, r)
      }
    ]...),
    {
      gateway_forward_ssh_infra = {
        role        = "gateway"
        cidr        = var.subnets["infra"].cidr
        protocol    = "tcp"
        port        = 22
        description = "Forward VPN SSH into the infra subnet"
      }
      gateway_forward_ssh_workstation = {
        role        = "gateway"
        cidr        = var.subnets["workstation"].cidr
        protocol    = "tcp"
        port        = 22
        description = "Forward VPN SSH into the workstation subnet"
      }
    }
  )
}
