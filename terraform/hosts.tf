module "hosts" {
  source   = "./modules/ec2-instance"
  for_each = var.hosts

  name               = each.key
  domain             = var.domain
  ami_id             = data.aws_ami.os.id
  instance_type      = each.value.instance_type
  subnet_id          = module.network.subnet_ids[each.value.subnet]
  private_ip         = each.value.private_ip
  security_group_ids = [module.security_groups.security_group_ids[local.host_security_group[each.key]]]
  key_name           = aws_key_pair.bootstrap.key_name
  iam_instance_profile = (
    each.value.control_node_role ? aws_iam_instance_profile.control_node.name :
    each.value.backup_writer ? aws_iam_instance_profile.backup_writer.name : null
  )
  allocate_eip      = each.value.allocate_eip
  source_dest_check = each.value.source_dest_check
  extra_volumes     = each.value.extra_volumes
  root_volume_size  = each.value.root_volume_size

  tags = {
    Role = each.value.role
    Team = each.value.team
  }
}