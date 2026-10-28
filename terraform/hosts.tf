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
      instance_type     = "t3.micro"
      team              = "platform"
      allocate_eip      = true
      source_dest_check = false # required: gw01 forwards VPN traffic
    }
    control01 = {
      role          = "control"
      subnet        = "infra"
      private_ip    = "10.0.1.10"
      instance_type = "t3.micro"
      team          = "platform"
    }
    idm01 = {
      role          = "idm"
      subnet        = "infra"
      private_ip    = "10.0.1.11"
      instance_type = "c7i-flex.large" # 4 GB for FreeIPA; confirm it is on your free-tier list
      team          = "platform"
    }
    util01 = {
      role          = "util"
      subnet        = "infra"
      private_ip    = "10.0.1.12"
      instance_type = "t3.small"
      team          = "platform"
      extra_volumes = {
        data = { device_name = "/dev/sdf", size = 20 }
      }
    }
    ws-dev01 = {
      role          = "workstation"
      subnet        = "workstation"
      private_ip    = "10.0.2.10"
      instance_type = "t3.small"
      team          = "dev"
    }
    ws-ops01 = {
      role          = "workstation"
      subnet        = "workstation"
      private_ip    = "10.0.2.11"
      instance_type = "t3.small"
      team          = "ops"
    }
  }
}

module "hosts" {
  source   = "./modules/ec2-instance"
  for_each = var.hosts

  name               = each.key
  domain             = var.domain
  ami_id             = data.aws_ami.os.id
  instance_type      = each.value.instance_type
  subnet_id          = module.network.subnet_ids[each.value.subnet]
  private_ip         = each.value.private_ip
  security_group_ids = [module.security_groups.security_group_ids[each.value.role]]
  key_name           = aws_key_pair.bootstrap.key_name
  allocate_eip       = each.value.allocate_eip
  source_dest_check  = each.value.source_dest_check
  extra_volumes      = each.value.extra_volumes

  tags = {
    Role = each.value.role
    Team = each.value.team
  }
}