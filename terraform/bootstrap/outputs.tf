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