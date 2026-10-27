output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "subnet_ids" {
  description = "Subnet IDs by name"
  value       = { for name, s in aws_subnet.this : name => s.id }
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway (null when disabled)"
  value       = try(aws_eip.nat[0].public_ip, null)
}