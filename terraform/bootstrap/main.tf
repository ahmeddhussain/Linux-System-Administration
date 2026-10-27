locals {
  # Host roles. One security group is created for each.
  roles = toset(["bastion", "control", "idm", "util", "workstation"])

  # Approved connections between roles. Anything not listed here is denied.
  # To open a new connection: add an entry, run plan, review, apply, and
  # record the change as a ticket.
  flows = {
    bastion_to_control = {
      from        = "bastion"
      to          = "control"
      protocol    = "tcp"
      port        = 22
      description = "SSH bastion01 to control01 (admin path)"
    }
    bastion_to_workstation = {
      from        = "bastion"
      to          = "workstation"
      protocol    = "tcp"
      port        = 22
      description = "SSH jump from bastion01 to workstations (employee path)"
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

  # From outside the VPC: only your IP, only SSH, only to bastion01,
  # plus ICMP from inside the VPC for troubleshooting.
  cidr_ingress = merge(
    {
      admin_ssh_to_bastion = {
        role        = "bastion"
        cidr        = var.admin_cidr
        protocol    = "tcp"
        port        = 22
        description = "SSH from admin IP"
      }
    },
    {
      for r in local.roles : "${r}_icmp_in" => {
        role        = r
        cidr        = module.network.vpc_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP from inside the VPC"
      }
    }
  )

  # To outside: HTTPS only (package repos and updates via the NAT gateway),
  # plus ICMP inside the VPC. Workstation internet access will be restricted
  # to the proxy in Phase 6.
  cidr_egress = merge(
    {
      for r in local.roles : "${r}_https_out" => {
        role        = r
        cidr        = "0.0.0.0/0"
        protocol    = "tcp"
        port        = 443
        description = "HTTPS to internet via NAT (package repos, updates)"
      }
    },
    {
      for r in local.roles : "${r}_icmp_out" => {
        role        = r
        cidr        = module.network.vpc_cidr
        protocol    = "icmp"
        port        = -1
        description = "ICMP to inside the VPC"
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