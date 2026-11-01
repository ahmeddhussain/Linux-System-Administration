variable "aws_region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name (null uses the default credential chain)"
  type        = string
  default     = null
}

variable "company_name" {
  description = "Company name, used as a prefix for resource names"
  type        = string
  default     = "ahmed"
}

variable "domain" {
  description = "Internal DNS domain. .internal is reserved for private use."
  type        = string
  default     = "ahmed.internal"
}

variable "availability_zone" {
  description = "Availability zone for the lab subnets"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "CIDR block for the company VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Subnets by tier: CIDR block and whether the subnet is public"
  type = map(object({
    cidr   = string
    public = bool
  }))
  default = {
    public      = { cidr = "10.0.0.0/24", public = true }
    infra       = { cidr = "10.0.1.0/24", public = false }
    workstation = { cidr = "10.0.2.0/24", public = false }
    app         = { cidr = "10.0.3.0/24", public = false }
  }
}

variable "enable_nat_gateway" {
  description = "Create the NAT gateway. Set false between sessions to save cost."
  type        = bool
  default     = true
}

variable "vpn_cidr" {
  description = "Address space of all VPN clients. Must not overlap the VPC or your home network."
  type        = string
  default     = "10.8.0.0/16"
}

variable "vpn_ranges" {
  description = "VPN address range per team. The admin range is required."
  type        = map(string)
  default = {
    admin = "10.8.0.0/24"
    dev   = "10.8.1.0/24"
    ops   = "10.8.2.0/24"
  }

  validation {
    condition     = contains(keys(var.vpn_ranges), "admin")
    error_message = "vpn_ranges must contain an \"admin\" entry."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the public key imported as the bootstrap key pair"
  type        = string
  default     = "~/.ssh/ivolve.pub"
}

variable "ami_owner_id" {
  description = "AWS account ID that publishes the OS image (Red Hat's official account)"
  type        = string
  default     = "309956199498"
}

variable "ami_name_pattern" {
  description = "Image name pattern; change this and ami_owner_id to switch distribution"
  type        = string
  default     = "RHEL-10.0.0_HVM-20260922-x86_64-0-Hourly2-GP3"
}

variable "enable_vpn_endpoint" {
  description = "Open TCP 443 (wstunnel, carrying WireGuard) on gw01 to vpn_client_cidr. Set true in terraform.tfvars."
  type        = bool
  default     = false
}

variable "vpn_client_cidr" {
  description = "Where VPN clients may connect from. WireGuard ignores any packet not signed by a known peer key, so the port is safe to expose; set a narrower range only if every client has a fixed address."
  type        = string
  default     = "0.0.0.0/0"
}

variable "hosts" {
  description = "Host inventory: every server and workstation in the company"
  type = map(object({
    role              = string
    subnet            = string
    private_ip        = string
    instance_type     = string
    team              = string
    allocate_eip      = optional(bool, false)
    source_dest_check = optional(bool, true)
    control_node_role = optional(bool, false)
    security_group    = optional(string) # defaults to role
    backup_writer     = optional(bool, false)
    extra_volumes = optional(map(object({
      device_name = string
      size        = number
    })), {})
  }))

  default = {
    gw01 = {
      role              = "gateway"
      subnet            = "public"
      private_ip        = "10.0.0.10"
      instance_type     = "t3.small"
      team              = "platform"
      allocate_eip      = true
      source_dest_check = false # required: gw01 forwards VPN traffic
    }
    control01 = {
      role              = "control"
      subnet            = "infra"
      private_ip        = "10.0.1.10"
      instance_type     = "t3.small" # runs Ansible against the whole fleet
      team              = "platform"
      control_node_role = true # dynamic inventory + read secrets from SSM (iam.tf)
    }
    idm01 = {
      role          = "idm"
      subnet        = "infra"
      private_ip    = "10.0.1.11"
      instance_type = "c7i-flex.large" # 4 GB for FreeIPA
      team          = "platform"
    }
    util01 = {
      role          = "util"
      subnet        = "infra"
      private_ip    = "10.0.1.12"
      instance_type = "t3.small"
      team          = "platform"
      backup_writer = true # writes backups to S3 (iam.tf, D-056)
      extra_volumes = {
        data = { device_name = "/dev/sdf", size = 20 }
      }
    }
    ws-dev01 = {
      role           = "workstation"
      security_group = "workstation-dev"
      subnet         = "workstation"
      private_ip     = "10.0.2.10"
      instance_type  = "t3.small"
      team           = "dev"
    }
    ws-ops01 = {
      role           = "workstation"
      security_group = "workstation-ops"
      subnet         = "workstation"
      private_ip     = "10.0.2.11"
      instance_type  = "t3.small"
      team           = "ops"
    }
  }

  validation {
    condition     = alltrue([for h in values(var.hosts) : contains(keys(var.subnets), h.subnet)])
    error_message = "Every host's subnet must be a key of var.subnets."
  }

  validation {
    condition     = alltrue([for h in values(var.hosts) : contains(local.host_roles, coalesce(h.security_group, h.role))])
    error_message = "Every host's security group (security_group, or role) must be one of local.roles in main.tf, without eice."
  }

  validation {
    condition = alltrue([
      for h in values(var.hosts) : can(cidrnetmask("${h.private_ip}/32"))
    ])
    error_message = "Every private_ip must be a plain IPv4 address."
  }

  validation {
    condition     = length(distinct([for h in values(var.hosts) : h.private_ip])) == length(var.hosts)
    error_message = "Two hosts share a private_ip."
  }

  validation {
    condition     = length([for h in values(var.hosts) : h if h.control_node_role]) <= 1
    error_message = "Only one host may hold the control node role (it can read secrets)."
  }

  validation {
    condition     = alltrue([for h in values(var.hosts) : !(h.control_node_role && h.backup_writer)])
    error_message = "A host can have only one instance role: control_node_role or backup_writer."
  }
}
