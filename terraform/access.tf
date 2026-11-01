# AWS-managed tunnel into private instances, authenticated with AWS
# credentials. No inbound rule from the internet. Also serves as the
# break-glass path to control01 if the VPN fails.
resource "aws_ec2_instance_connect_endpoint" "break_glass" {
  subnet_id          = module.network.subnet_ids["infra"]
  security_group_ids = [module.security_groups.security_group_ids["eice"]]
  preserve_client_ip = false

  tags = {
    Name = "${var.company_name}-eice"
  }
}