variable "hosts" {
  description = "Host inventory: every server and workstation in the company"
  type = map(object({
    role          = string
    subnet        = string
    private_ip    = string
    instance_type = string
    team          = string
    allocate_eip  = optional(bool, false)
    extra_volumes = optional(map(object({
      device_name = string
      size        = number
    })), {})
  }))

  default = {
    gw01 = {
      role          = "gateway"
      subnet        = "public"
      private_ip    = "10.0.0.10"
      instance_type = "t3.micro"
      team          = "platform"
      allocate_eip  = true
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
      instance_type = "t3.medium"
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
  extra_volumes      = each.value.extra_volumes

  tags = {
    Role = each.value.role
    Team = each.value.team
  }
}