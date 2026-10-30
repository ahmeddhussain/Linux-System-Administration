variable "enable_vpn_endpoint" {
  description = "Open the WireGuard port on gw01. Keep false until WireGuard is configured on gw01."
  type        = bool
  default     = false
}

variable "vpn_client_cidr" {
  description = "Where VPN clients may connect from. WireGuard ignores any packet not signed by a known peer key, so the port is safe to expose; set a narrower range only if every client has a fixed address."
  type        = string
  default     = "0.0.0.0/0"
}

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