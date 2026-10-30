locals {
  # Security group roles. "eice" is the instance connect endpoint, not a host.
  roles      = toset(["eice", "gateway", "control", "idm", "util", "workstation"])
  host_roles = setsubtract(local.roles, ["eice"])

  vpn_admin_cidr = var.vpn_ranges["admin"]

  # Approved connections between roles. Anything not listed here is denied.
  # To open a new connection: add an entry, run plan, review, apply, and
  # record the change as a ticket.
  flows = {
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
    control_to_workstation = {
      from        = "control"
      to          = "workstation"
      protocol    = "tcp"
      port        = 22
      description = "SSH control01 to workstations (Ansible)"
    }
  }

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
      workstation_icmp_from_vpn_admin = {
        role        = "workstation"
        cidr        = local.vpn_admin_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP from VPN admin range"
      }
    },
    # Employees over the VPN: workstations only. Which workstation each team
    # may reach is enforced on gw01's firewall (later phase).
    {
      for team, cidr in var.vpn_ranges : "workstation_ssh_from_vpn_${team}" => {
        role        = "workstation"
        cidr        = cidr
        protocol    = "tcp"
        port        = 22
        description = "SSH from VPN range: ${team}"
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
      for r in local.host_roles : "${r}_https_out" => {
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

module "network" {
  source = "./modules/network"

  name_prefix        = var.company_name
  vpc_cidr           = var.vpc_cidr
  availability_zone  = var.availability_zone
  subnets            = var.subnets
  enable_nat_gateway = var.enable_nat_gateway
}

module "security_groups" {
  source = "./modules/security-groups"

  name_prefix  = var.company_name
  vpc_id       = module.network.vpc_id
  roles        = local.roles
  flows        = local.flows
  cidr_ingress = local.cidr_ingress
  cidr_egress  = local.cidr_egress
}