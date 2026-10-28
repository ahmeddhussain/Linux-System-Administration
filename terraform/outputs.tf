output "vpc_id" {
  description = "ID of the company VPC"
  value       = module.network.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs by tier"
  value       = module.network.subnet_ids
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway (null when disabled)"
  value       = module.network.nat_public_ip
}

output "security_group_ids" {
  description = "Security group IDs by host role"
  value       = module.security_groups.security_group_ids
}

output "gateway_public_ip" {
  description = "Public IP of gw01, the only entry point"
  value       = module.hosts["gw01"].public_ip
}

output "vpn_endpoint" {
  description = "WireGuard endpoint clients connect to"
  value       = "${module.hosts["gw01"].public_ip}:51820"
}

output "hosts" {
  description = "Private IP and instance ID of every host"
  value = {
    for name, h in module.hosts : name => {
      private_ip  = h.private_ip
      instance_id = h.instance_id
    }
  }
}